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
use Koha::Patron::Debarments qw/AddDebarment/;
use Koha::Patron;
use Koha::Patron::Message::Preferences;

use Bulk::ConversionTable::BorrowernumberConversionTable;
use Bulk::PatronImporter;

binmode( STDOUT, ":encoding(UTF-8)" );
our $verbosity = 3;
my %args;
$args{borrowernumberConversionTableFile} = 'borrowernumberConversionTable';

GetOptions(
    'file:s'                   => \$args{importFile},
    'deduplicate'              => \$args{deduplicate},
    'defaultadmin'             => \$args{defaultAdmin},
    'b|bnConversionTable:s'    => \$args{borrowernumberConversionTableFile},
    'v|verbosity:i'            => \$verbosity,
    'messagingPreferencesOnly' => \$args{messagingPreferencesOnly},
    'profile'                  => \$args{profile},
);

my $help = <<HELP;

NAME
  $0 - Import patrons en masse

SYNOPSIS
  perl bulkPatronImport.pl --file /home/koha/pielinen/patrons.migrateme --deduplicate --defaultadmin \
      --bnConversionTable borrowernumberConversionTable

  then

  perl bulkPatronImport.pl --messagingPreferencesOnly --bnConversionTable borrowernumberConversionTable

DESCRIPTION
  Migrates the Perl-serialized MMT-processed patrons-files to Koha.
  Some very slow, but not dependency-inducing for later migration, steps have been delegated to post
  migration steps, such as:
    --messagingPreferencesOnly
  Those can be ran parallel to the rest of the migration scripts.

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

    --messagingPreferencesOnly
          Only set the default messaging preferences for the borrower category.
          Reads the borrowernumber conversion table for the added Patrons that need
          to have their messaging preferences set.

    --profile
          Profile different aspects of Patron migration.
          Currently profiles different levels of Bcrypt hashing strength to speed up password migration

HELP

require Bulk::Util; #Init logging && verbosity

my $patronImporter = Bulk::PatronImporter->new(\%args);
if ($args{profile}) {
    $patronImporter->profileBcrypts();
    exit 0;
}
if ($args{messagingPreferencesOnly}) {
    $patronImporter->setDefaultMessagingPreferences();
    exit 0;
}

unless ($args{importFile}) {
    die "$help\n\n--file is mandatory";
}

INFO "Opening BorrowernumberConversionTable '$args{borrowernumberConversionTableFile}' for writing";
my $borrowernumberConversionTable = Bulk::ConversionTable::BorrowernumberConversionTable->new($args{borrowernumberConversionTableFile}, 'write');
my $now = DateTime->now()->ymd();
INFO "Now is $now";

my @guarantees;#Store all the juveniles with a guarantor here.
#Guarantor is linked via barcode, but it won't be available if a guarantor
#is added after the guarantee. After all borrowers have been migrated, migrate guarantees.

$patronImporter->addDefaultAdmin() if $args{defaultAdmin};


INFO "Looping Patron rows";
my $fh = Bulk::Util::openFile($args{importFile});
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
INFO "Opening BorrowernumberConversionTable '$args{borrowernumberConversionTableFile}' for reading";
my $borrowernumberConversionTableReadable = Bulk::ConversionTable::BorrowernumberConversionTable->new($args{borrowernumberConversionTableFile}, 'read');
INFO "Opening BorrowernumberConversionTable '$args{borrowernumberConversionTableFile}' for writing";
$borrowernumberConversionTable = Bulk::ConversionTable::BorrowernumberConversionTable->new($args{borrowernumberConversionTableFile}, 'write');
INFO "Looping guarantees";
$i = 0;
foreach my $patron (@guarantees) {
    $i++;
    INFO "Processed $i Patrons" if ($i % 100 == 0);

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
    if ($args{deduplicate}) {
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
    unless ($old_borrowernumber) {
        eval { $patron->{borrowernumber} = $patronImporter->AddMember($patron) };
        if ($@) {
            if ($@ =~ /Duplicate entry '.*?' for key 'cardnumber'/) {
                # Duplicate cardnumber? Mark the cardnumber as duplicate and retry.
                $patron->{cardnumber} .= '_TUPLA';
                $patron->{opacnote} = '' unless $patron->{opacnote};
                $patron->{opacnote} .= 'Järjestelmävaihdoksen yhteydessä havaittu tuplakirjastokortti. Ota yhteyttä kirjastoosi asian korjaamiseksi.';
                $patron->{borrowernumber} = $patronImporter->AddMember($patron);
            }
            else {
                die $@;
            }
        }
    }

    ##Save the new borrowernumber to a conversion table so legacy systems references can keep track of the change.
    $borrowernumberConversionTable->writeRow($legacy_borrowernumber, $patron->{borrowernumber}, $patron->{cardnumber});

    if ($standingPenalties) { #Catch borrower_debarments
        my $standing_penalties = [  split('<\d\d>', $standingPenalties)  ];
        shift @$standing_penalties; #Remove the empty index in the beginning

        for (my $j=0 ; $j<@$standing_penalties ; $j++) {
            my $penaltyComment = $standing_penalties->[$j];

            if ($penaltyComment =~ /maksamattomia maksuja (\d+\.\d+)/) { #In Libra3, only the sum of fines is migrated.
                $patronImporter->fineImport($patron->{borrowernumber}, $penaltyComment, 'Konve', $1, $now);
            }
            else {
                my @dateComment = split("<>",$penaltyComment);
                $patronImporter->AddDebarment({
                    borrowernumber => $patron->{borrowernumber},
                    type           => 'MANUAL', ## enum('FINES','OVERDUES','MANUAL')
                    comment        => $dateComment[1],
                    created        => $dateComment[0],
                });
            }
        }
    }

    #Adding the SSN
    if ($ssn) {
        $patronImporter->addBorrowerAttribute($patron, 'SSN', $patron->{ssn});
    }
    else {
        WARN "Patron '".$patron->{cardnumber}."' doesn't have a ssn?";
    }

    if ($extendedPatronAttributes) {
        while (my ($attr, $vals) = each(%$extendedPatronAttributes)) {
            for my $val (@$vals) {
                $patronImporter->addBorrowerAttribute($patron, $attr, $val);
            }
        }
    }
}
