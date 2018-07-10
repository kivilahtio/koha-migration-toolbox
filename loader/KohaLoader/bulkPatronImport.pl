#!/usr/bin/perl

use Modern::Perl;
use experimental 'smartmatch', 'signatures';
$|=1;
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDIN, ":encoding(UTF-8)");

use Getopt::Long;
use Log::Log4perl qw(:easy);
use DateTime;

use C4::Members;
use C4::Members::Attributes;
use Koha::AuthUtils qw(hash_password);
use Koha::Patron::Debarments qw/AddDebarment/;
use Koha::Auth::PermissionManager;
use Koha::Patron;
use Koha::Patron::Message::Preferences;

use Bulk::ConversionTable::BorrowernumberConversionTable;

binmode( STDOUT, ":encoding(UTF-8)" );
our $verbosity = 3;
my ( $importFile, $deduplicate, $defaultAdmin );
my $borrowernumberConversionTableFile = 'borrowernumberConversionTable';

GetOptions(
    'file:s'                => \$importFile,
    'deduplicate'           => \$deduplicate,
    'defaultadmin'          => \$defaultAdmin,
    'b|bnConversionTable:s' => \$borrowernumberConversionTableFile,
    'v|verbosity:i'         => \$verbosity,
);

my $help = <<HELP;

NAME
  $0 - Import patrons en masse

SYNOPSIS
  perl bulkPatronImport.pl --file /home/koha/pielinen/patrons.migrateme --deduplicate --defaultadmin
      --bnConversionTable borrowernumberConversionTable

DESCRIPTION
  Migrates the Perl-serialized MMT-processed patrons-files to Koha.

    --file filepath
          The perl-serialized HASH of Patrons.

    --bnConversionTable filepath
          From which file to read the converted borrowernumber?
          Defaults to 'borrowernumberConversionTable'

    --deduplicate
          Should we deduplicate the Patrons? Case-insensitively checks for same
          surname, firstnames, othernames, dateofbirth

    --defaultadmin
          Should we populate the default test admin 1234?

    -v level
          Verbose output to the STDOUT,
          Defaults to 3, 6 is max verbosity, 0 is fatal only.

HELP

require Bulk::Util; #Init logging && verbosity

unless ($importFile) {
    die "$help\n\n--file is mandatory";
}

INFO "Opening BorrowernumberConversionTable '$borrowernumberConversionTableFile' for writing";
my $borrowernumberConversionTable = Bulk::ConversionTable::BorrowernumberConversionTable->new($borrowernumberConversionTableFile, 'write');
my $now = DateTime->now()->ymd();
INFO "Now is $now";

my @guarantees;#Store all the juveniles with a guarantor here.
#Guarantor is linked via barcode, but it won't be available if a guarantor
#is added after the guarantee. After all borrowers have been migrated, migrate guarantees.

my $permissionManager = Koha::Auth::PermissionManager->new();

my $dbh = C4::Context->dbh;
my $fineStatement = $dbh->prepare( #Used for Libra3
    'INSERT INTO  accountlines
        (borrowernumber, accountno, date, amount, description, accounttype, amountoutstanding, notify_id, manager_id)
    VALUES (?,           ?,         ?,    ?,      ?,           ?,           ?,                 ?,         ?)'
);

my ($sth_addBorrower, $borrowerColumns) = prepareAddBorrowersStatement();


sub AddMember($data, $useDBIx=0) {
#    my $dbh = C4::Context->dbh;

    # generate a proper login if none provided
    $data->{'userid'} = C4::Members::Generate_Userid($data->{'borrowernumber'}, $data->{'firstname'}, $data->{'surname'}) unless $data->{'userid'};
    delete $data->{'borrowernumber'};

    # add expiration date if it isn't already there
    unless ( $data->{'dateexpiry'} ) {
        $data->{'dateexpiry'} = $now;
    }

    # add enrollment date if it isn't already there
    unless ( $data->{'dateenrolled'} ) {
        $data->{'dateenrolled'} = $now;
    }

    # create a disabled account if no password provided
    $data->{'password'} = ($data->{'password'})? hash_password($data->{'password'}) : '!';

    # Default privacy if none provided
    $data->{privacy} = 1 unless exists $data->{privacy};
    $data->{'privacy_guarantor_checkouts'} = 0;

    $data->{checkprevcheckout} = 0 unless $data->{checkprevcheckout};
    $data->{lang} = 'fi' unless $data->{lang};

    if ($useDBIx) { #DBIx migrated 8800 Patrons in 8 minutes
        my $patron=Koha::Patron->new($data);
        $patron->store;
        $data->{'borrowernumber'}=$patron->borrowernumber;
    }
    else {          #DBD::MySQL migrated 10500 Patrons in 11 minutes
        executeAddBorrowersStatement($data);
    }

    return $data->{'borrowernumber'};
}


addDefaultAdmin() if $defaultAdmin;


INFO "Looping Patron rows";
my $fh = Bulk::Util::openFile($importFile);
my $i = 0;
while (<$fh>) {
    $i++;
    INFO "Processed $i Items" if ($i % 1000 == 0);

    my $patron = Bulk::Util::newFromBlessedMigratemeRow($_);
    DEBUG "Row:$i - Patron ".$patron->{cardnumber};

    if ($patron->{guarantorid} || $patron->{guarantorbarcode}) {
        push @guarantees, $patron;
        next;
    }

    processNewFromRow($patron);
}
$borrowernumberConversionTable->close(); #Flush to disk so guarantees can pick the most latest changes as well.

#Migrate all guarantees now that we certainly know their guarantors exist in the DB.
INFO "Opening BorrowernumberConversionTable '$borrowernumberConversionTableFile' for reading";
my $borrowernumberConversionTableReadable = Bulk::ConversionTable::BorrowernumberConversionTable->new($borrowernumberConversionTableFile, 'read');
INFO "Opening BorrowernumberConversionTable '$borrowernumberConversionTableFile' for writing";
my $borrowernumberConversionTable = Bulk::ConversionTable::BorrowernumberConversionTable->new($borrowernumberConversionTableFile, 'write');
INFO "Looping guarantees";
$i = 0;
foreach my $patron (@guarantees) {
    $i++;
    print "$i\n" unless $i % 100;

    DEBUG "Row:$i - Patron ".$patron->{cardnumber};
    processNewFromRow( $patron );
}
$borrowernumberConversionTable->close();

sub processNewFromRow($patron) {
    bless($patron, 'HASH'); #Unbless so DBIx wont complain
    my $legacy_borrowernumber = $patron->{borrowernumber};
    my ($old_borrowernumber, $old_categorycode);

    #Get the guarantor's id
    if ($patron->{guarantorbarcode}) {
        my $guarantor = C4::Members::GetMember( cardnumber => $patron->{guarantorbarcode} );
        $patron->{guarantorid} = $guarantor->{borrowernumber};
    }
    elsif ($patron->{guarantorid}) {
        my $newGuarantorid = $borrowernumberConversionTableReadable->fetch($patron->{guarantorid});
        $patron->{guarantorid} = $newGuarantorid;
    }

    #Check if the same borrower exists already
    if ($deduplicate) {
        ($old_borrowernumber, $old_categorycode) = C4::Members::checkuniquemember(0, $patron->{surname}, $patron->{firstname}, $patron->{dateofbirth});
        if ($old_borrowernumber) {
            INFO "Matching borrower found for $patron->{surname}, $patron->{firstname}, $patron->{dateofbirth} having borrowernumber $old_borrowernumber";
            $patron->{borrowernumber} = $old_borrowernumber;
            $patron->{categorycode} = $old_categorycode;
        }
    }
    #If not, then just add a borrower
    #Extra columns need to be cleaned away, otherwise DBIx cant handle the data.
    my $standingPenalties = $patron->{standing_penalties};              delete $patron->{standing_penalties};
    my $extendedPatronAttributes = $patron->{ExtendedPatronAttributes}; delete $patron->{ExtendedPatronAttributes};
    my $ssn = $patron->{ssn};                                           delete $patron->{ssn};
    $patron->{borrowernumber} = AddMember($patron) unless $old_borrowernumber;

    ##Save the new borrowernumber to a conversion table so legacy systems references can keep track of the change.
    $borrowernumberConversionTable->writeRow($legacy_borrowernumber, $patron->{borrowernumber}, $patron->{cardnumber});

    if ($standingPenalties) { #Catch borrower_debarments
        my $standing_penalties = [  split('<\d\d>', $standingPenalties)  ];
        shift @$standing_penalties; #Remove the empty index in the beginning

        for (my $j=0 ; $j<@$standing_penalties ; $j++) {
            my $penaltyComment = $standing_penalties->[$j];

            if ($penaltyComment =~ /maksamattomia maksuja (\d+\.\d+)/) { #In Libra3, only the sum of fines is migrated.
                fineImport($patron->{borrowernumber}, $penaltyComment, 'Konve', $1, $now);
            }
            else {
                my @dateComment = split("<>",$penaltyComment);
                AddDebarment({
                    borrowernumber => $patron->{borrowernumber},
                    type           => 'MANUAL', ## enum('FINES','OVERDUES','MANUAL')
                    comment        => $dateComment[1],
                    created        => $dateComment[0],
                });
            }
        }
    }

    my $patron_ko = Koha::Patrons->find($patron->{borrowernumber});
    $patron_ko->set_default_messaging_preferences;

    #Adding the SSN
    if ($ssn) {
        addBorrowerAttribute($patron, 'SSN', $patron->{ssn});
    }
    else {
        WARN "Patron '".$patron->{cardnumber}."' doesn't have a ssn?";
    }

    if ($extendedPatronAttributes) {
        while (my ($attr, $vals) = each(%$extendedPatronAttributes)) {
            for my $val (@$vals) {
                addBorrowerAttribute($patron, $attr, $val);
            }
        }
    }
}

my $sth_addBorrowerAttribute;
#C4::Members::Attributes doesn't have an accessor to simply add a single entry.
sub addBorrowerAttribute($patron, $attribute, $value) {
    unless ($sth_addBorrowerAttribute) {
      $sth_addBorrowerAttribute = $dbh->prepare(
          "INSERT INTO borrower_attributes (borrowernumber, code, attribute) VALUES (?, ?, ?)"
      );
    }
    $sth_addBorrowerAttribute->execute($patron->{borrowernumber}, $attribute, $value);
}

sub addDefaultAdmin {
    INFO "Adding default admin";
    my $dbh = C4::Context->dbh;
    my $categorycode = $dbh->selectrow_array("SELECT categorycode from categories LIMIT 1") or die "Failed to get default admin categorycode ".$dbh->errstr(); #Pick any borrower.categorycode
    my $branchcode = $dbh->selectrow_array("SELECT branchcode from branches LIMIT 1") or die "Failed to get default admin branchcode ".$dbh->errstr(); #Pick any borrower.branchcode
    my %defaultAdmin = (
        cardnumber =>   "kalifi",
        surname =>      "Kalifi",
        firstname =>    "Kalifin",
        othernames =>   "paikalla",
        address =>      "Kalifinkuja 12 b 7",
        city =>         "Kalifila",
        zipcode =>      "12345",
        dateofbirth =>  "1985-09-06",
        branchcode =>   $branchcode,
        categorycode => $categorycode,
        dateenrolled => "2015-09-25",
        dateexpiry =>   "2018-09-25",
        password =>     "Baba-Gnome",
        userid =>       "kalifi",
        privacy =>      1,
    );
    eval {
        $defaultAdmin{borrowernumber} = C4::Members::AddMember(%defaultAdmin);
        INFO "Granting default admin permissions";
        $permissionManager->grantPermission($defaultAdmin{borrowernumber}, 'superlibrarian', 'superlibrarian');
    };
    if ($@) {
        print "Error while adding the default admin: $@";
    }
}



sub fineImport {
    my ( $borrowernumber, $desc, $accounttype, $amount, $date ) = @_;

    #Make sure the borrowerexists!
    my $testingBorrower = C4::Members::GetMember(borrowernumber => $borrowernumber);
    unless (defined $testingBorrower) {
        warn "Patron $borrowernumber doesn't exist in Koha!\n";
        return;
    }

    my $accountno  = C4::Accounts::getnextacctno( $borrowernumber );
    my $amountleft = $amount;
    my $notifyid = 0;
    my $manager_id = C4::Context->userenv ? C4::Context->userenv->{'number'} : 1;

    $fineStatement->execute($borrowernumber, $accountno, $date, $amount, $desc, $accounttype, $amountleft, $notifyid, $manager_id);

    if ($fineStatement->errstr) {
        println $fineStatement->errstr;
    }

}

sub AddDebarment {
    my ($params) = @_;

    my $borrowernumber = $params->{'borrowernumber'};
    my $expiration     = $params->{'expiration'} || undef;
    my $type           = $params->{'type'} || 'MANUAL';
    my $comment        = $params->{'comment'} || undef;
    my $created        = $params->{'created'} || undef;

    return unless ( $borrowernumber && $type );

    my $manager_id;
    $manager_id = C4::Context->userenv->{'number'} if C4::Context->userenv;

    my $sql = "
        INSERT INTO borrower_debarments ( borrowernumber, expiration, type, comment, manager_id, created )
        VALUES ( ?, ?, ?, ?, ?, ? )
    ";

    my $r = C4::Context->dbh->do( $sql, {}, ( $borrowernumber, $expiration, $type, $comment, $manager_id, $created ) );

    Koha::Patron::Debarments::_UpdateBorrowerDebarmentFlags($borrowernumber);

    return $r;
}

=head2 prepareAddBorrowersStatement

Hypothesis that DBIx is sloooow. It doesn't seem that way now.

 @returns LIST of
               - DBI prepared statement
               - All the column names in the borrowers-table. This is used to populate the INSERT statements later.

=cut

sub prepareAddBorrowersStatement() {
    my $sth = $dbh->column_info( undef, undef, 'borrowers', '%' );
    my $cols = $sth->fetchall_arrayref({}) or die("Fetching koha.borrowers column definitions failed: ".$sth->errstr());
    my @borrowerColumns = map {$_->{COLUMN_NAME}} @$cols;
    my @placeholders = map {'?'} (1..@borrowerColumns);

    my $sth_addBorrower = $dbh->prepare( #DBIx is just so freaking sloooooowwwww.
        "INSERT INTO borrowers\n".
        "    (".join(',',@borrowerColumns).")\n".
        "VALUES\n".
        "    (".join(',',@placeholders).")\n"
    ) or die "Preparing the koha.borrowers insertion statement failed: ".$sth_addBorrower->errstr();

    return ($sth_addBorrower, \@borrowerColumns);
}

sub executeAddBorrowersStatement($patron) {
    my @params = map {$patron->{$_}} @$borrowerColumns;
    $sth_addBorrower->execute(@params) or die("Adding borrower failed: ".$sth_addBorrower->errstr());
    $patron->{borrowernumber} = $dbh->last_insert_id(undef, undef, 'borrowers', undef);
    unless ($patron->{borrowernumber}) {
      die "last_insert_id() not available after adding a borrower?: ".$dbh->errstr();
    }
}
