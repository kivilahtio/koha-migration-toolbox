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
use Koha::Patron::Message;

use Bulk::ConversionTable::BorrowernumberConversionTable;
use Bulk::PatronImporter;

binmode( STDOUT, ":encoding(UTF-8)" );
our $verbosity = 3;
my %args = (importFile =>                         ($ENV{MMT_DATA_SOURCE_DIR}//'.').'/Patron.migrateme',
            uploadSSNKeysFile =>                  ($ENV{MMT_DATA_SOURCE_DIR}//'.').'/Patron.ssn.csv',
            uploadSSNKeysHetulaCredentialsFile => ($ENV{MMT_DATA_SOURCE_DIR}//'.').'/Hetula.credentials',
            preserveIds =>                        $ENV{MMT_PRESERVE_IDS} // 0,
            defaultAdmin =>                       0,
            borrowernumberConversionTableFile =>  ($ENV{MMT_WORKING_DIR}//'.').'/borrowernumberConversionTable');

my $help = <<HELP;

NAME
  $0 - Import patrons en masse

SYNOPSIS
  perl bulkPatronImport.pl --file $args{importFile} --deduplicate --defaultAdmin kalifi:Baba-Gnome \
      --bnConversionTable $args{borrowernumberConversionTableFile}

  then

  perl bulkPatronImport.pl --messagingPreferencesOnly --bnConversionTable $args{borrowernumberConversionTableFile}
  perl bulkPatronImport.pl --uploadSSNKeysOnly --uploadSSNKeysFile $args{uploadSSNKeysFile} \
                           --uploadSSNKeysHetulaCredentialsFile $args{uploadSSNKeysHetulaCredentialsFile} \
                           --bnConversionTable $args{borrowernumberConversionTableFile}

DESCRIPTION
  Migrates the Perl-serialized MMT-processed patrons-files to Koha.

  Some very slow, but not dependency-inducing for later migration, steps have been delegated to post
  migration steps, such as:
    --messagingPreferencesOnly
    --uploadSSNKeysOnly
  Those can be ran parallel to the rest of the migration scripts.

    --file filepath
          The perl-serialized HASH of Patrons.
          Defaults to '$args{importFile}'.

    --bnConversionTable filepath
          From which file to read the converted borrowernumber?
          Defaults to '$args{borrowernumberConversionTableFile}'

    --deduplicate
          Should we deduplicate the Patrons? Case-insensitively checks for same
          surname, firstnames, othernames, dateofbirth

    --defaultAdmin username:password
          Should we populate the default test superlibrarian?
          Defaults to '$args{defaultAdmin}'

    --preserveIds
          Should the source system database IDs be preserved or should they be overridden by defaults from Koha?
          Defaults to off, new IDs are generated

    -v level
          Verbose output to the STDOUT,
          Defaults to $verbosity, 6 is max verbosity, 0 is fatal only.

    --messagingPreferencesOnly
          Only set the default messaging preferences for the borrower category.
          Reads the borrowernumber conversion table for the added Patrons that need
          to have their messaging preferences set.

    --uploadSSNKeysOnly
          Upload SSN keys to Hetula using Hetula::Client and then to Koha.borrower_attributes.
          --uploadSSNKeysFile can be set if this is selected.

    --uploadSSNKeysFile filepath
          Upload SSN keys to Hetula using Hetula::Client and then to Koha.borrower_attributes.
          Defaults to '$args{uploadSSNKeysFile}'.

    --uploadSSNKeysHetulaCredentialsFile filepath
          Where to find the Hetula credentials to use for the import?
          Defaults to '$args{uploadSSNKeysHetulaCredentialsFile}'.

    --profile
          Profile different aspects of Patron migration.
          Currently profiles different levels of Bcrypt hashing strength to speed up password migration

HELP

GetOptions(
    'file:s'                   => \$args{importFile},
    'deduplicate'              => \$args{deduplicate},
    'defaultAdmin:s'           => \$args{defaultAdmin},
    'b|bnConversionTable:s'    => \$args{borrowernumberConversionTableFile},
    'v|verbosity:i'            => \$verbosity,
    'preserveIds'              => \$args{preserveIds},
    'messagingPreferencesOnly' => \$args{messagingPreferencesOnly},
    'uploadSSNKeysOnly'        => \$args{uploadSSNKeysOnly},
    'uploadSSNKeysFile:s'      => \$args{uploadSSNKeysFile},
    'uploadSSNKeysHetulaCredentialsFile:s' => \$args{uploadSSNKeysHetulaCredentialsFile},
    'profile'                  => \$args{profile},
    'version'             => sub { Getopt::Long::VersionMessage() },
    'h|help'              => sub { print $help."\n"; exit 0; },
);

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
if ($args{uploadSSNKeysOnly}) {
    $patronImporter->uploadSSNKeys();
    exit 0;
}


$patronImporter->addDefaultAdmin($args{defaultAdmin}) if $args{defaultAdmin};


INFO "Opening BorrowernumberConversionTable '$args{borrowernumberConversionTableFile}' for writing";
my $borrowernumberConversionTable = Bulk::ConversionTable::BorrowernumberConversionTable->new($args{borrowernumberConversionTableFile}, 'write');
my $now = DateTime->now()->ymd();
INFO "Now is $now";

my @guarantees;#Store all the juveniles with a guarantor here.
#Guarantor is linked via barcode, but it won't be available if a guarantor
#is added after the guarantee. After all borrowers have been migrated, migrate guarantees.


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
    my $debarments = $patron->{debarments};                             delete $patron->{debarments};
    my $extendedPatronAttributes = $patron->{ExtendedPatronAttributes}; delete $patron->{ExtendedPatronAttributes};
    my $ssn = $patron->{ssn};                                           delete $patron->{ssn};
    my $popup_message = $patron->{popup_message};                       delete $patron->{popup_message};
    unless ($old_borrowernumber) {
        eval { $patron->{borrowernumber} = $patronImporter->AddMember($patron) };
        if ($@) {
            if ($@ =~ /Duplicate entry '.*?' for key 'cardnumber'/) {
                WARN "Patron cn:'$patron->{cardnumber}' has a duplicate cardnumber|userid. Prepending 'TUPLA_' and retrying.";
                # Duplicate cardnumber? Mark the cardnumber as duplicate and retry.
                $patron->{userid} .= '_TUPLA' if $patron->{userid} eq $patron->{cardnumber};
                $patron->{cardnumber} .= '_TUPLA';
                $patron->{opacnote} = '' unless $patron->{opacnote};
                $patron->{opacnote} .= 'Järjestelmävaihdoksen yhteydessä havaittu tuplakirjastokortti. Ota yhteyttä kirjastoosi asian korjaamiseksi.';

                eval {
                  $patron->{borrowernumber} = $patronImporter->AddMember($patron);
                };
                if ($@) {
                    ERROR "Patron cn:'$patron->{cardnumber}' has a duplicate cardnumber|userid. Couldn't save it:\n$@"; #Then let it slide
                    return undef;
                }
            }
            else {
                ERROR "Patron cn:'$patron->{cardnumber}' couldn't be added to Koha:\n$@";
                return undef;
            }
        }
    }

    ##Save the new borrowernumber to a conversion table so legacy systems references can keep track of the change.
    $borrowernumberConversionTable->writeRow($legacy_borrowernumber, $patron->{borrowernumber}, $patron->{cardnumber});

    if ($debarments) { #Catch borrower_debarments
        for my $debarment (@$debarments) {
            $patronImporter->AddDebarment({
                borrowernumber => $patron->{borrowernumber},
                type           => 'MANUAL', ## enum('FINES','OVERDUES','MANUAL')
                comment        => $debarment->{comment},
                created        => $debarment->{created},
            });
        }
    }

    #Adding the SSN directly
    if ($ssn) {
        if ($ssn ne 'via Hetula') {
            $patronImporter->addBorrowerAttribute($patron, 'SSN', $ssn);
        }
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

    if ($popup_message) {
      my $patron_message = Koha::Patron::Message->new({
        borrowernumber => $patron->{borrowernumber},
        message_type   => 'L', ## circulation messages for librarians, 'B' stands for borrowers
        message        => $popup_message->{message},
        message_date   => $popup_message->{message_date},
        branchcode     => $popup_message->{branchcode},
      })->store;
      WARN "Patron '".$patron->{cardnumber}."' has a popup message, but adding that failed?: $!" unless $patron_message;
    }
}