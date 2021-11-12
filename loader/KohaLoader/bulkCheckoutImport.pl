#!/usr/bin/perl

use Modern::Perl;
use experimental 'smartmatch', 'signatures';
$|=1;
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDIN, ":encoding(UTF-8)");

use Getopt::Long;
use Log::Log4perl qw(:easy);

use C4::Items;
use C4::Members;
use Bulk::ConversionTable::ItemnumberConversionTable;
use Bulk::ConversionTable::BorrowernumberConversionTable;
use Bulk::Util;
use Bulk::Item;
use Bulk::PatronImporter;

my $importFile = $ENV{MMT_DATA_SOURCE_DIR}.'/Issue.migrateme';
our $verbosity = 3;
my $borrowernumberConversionTable =      ($ENV{MMT_WORKING_DIR}//'.').'/borrowernumberConversionTable';
my $itemnumberConversionTable =          ($ENV{MMT_WORKING_DIR}//'.').'/itemnumberConversionTable';

GetOptions(
    'file:s'                   => \$importFile,
    'b|bnConversionTable:s'    => \$borrowernumberConversionTable,
    'i|inConversionTable:s'    => \$itemnumberConversionTable,
    'v|verbosity:i'            => \$verbosity,
);

my $help = <<HELP;

NAME
  $0 - Import checkouts en masse

SYNOPSIS
  perl bulkCheckoutImport.pl --file /home/koha/pielinen/checkouts.migrateme -v 6 \
      --bnConversionTable borrowernumberConversionTable


DESCRIPTION

    --file filepath
          The perl-serialized HASH of Issues.

    --bnConversionTable filepath
          From which file to read the converted borrowernumber?
          Defaults to 'borrowernumberConversionTable'

    --inConversionTable filepath
          To which file to write the itemnumber to barcode conversion. Items are best referenced
          by their barcodes, because the itemnumbers can overlap with existing Items.
          Defaults to 'itemnumberConversionTable'

    -v level
          Verbose output to the STDOUT,
          Defaults to 3, 6 is max verbosity, 0 is fatal only.

HELP

require Bulk::Util; #Init logging && verbosity

unless ($importFile) {
    die "$help\n\n--file is mandatory";
}


use C4::Biblio;
## Overload C4::Biblio::ModZebra to prevent indexing during migration.
package C4::Biblio {
  no warnings 'redefine';
  sub ModZebra {
    return undef;
  }
  use warnings 'redefine';
}
## Overload C4::Items::ModZebra to prevent indexing during migration.
##          I know there is no such subroutine, but the exporter apparently clones the subroutine definition.
package C4::Items {
  no warnings 'redefine';
  sub ModZebra {
    return undef;
  }
  use warnings 'redefine';
}

my $dbh = C4::Context->dbh;

## Get the id from where we start adding old issues. It is the biggest issue_id in use. It is important the issue_ids don't overlap.
my $old_issue_id = Bulk::Util::getMaxIssueId($dbh);



my $fh = Bulk::Util::openFile($importFile);
INFO "Opening BorrowernumberConversionTable '$borrowernumberConversionTable' for reading";
$borrowernumberConversionTable = Bulk::ConversionTable::BorrowernumberConversionTable->new($borrowernumberConversionTable, 'read');
INFO "Opening ItemnumberConversionTable '$itemnumberConversionTable' for reading";
$itemnumberConversionTable =     Bulk::ConversionTable::ItemnumberConversionTable->new($itemnumberConversionTable, 'read');

my $checkoutStatement = $dbh->prepare(
    "INSERT INTO issues
        (issue_id, borrowernumber, itemnumber, issuedate, date_due, branchcode, renewals)
    VALUES (?,?,?,?,?,?,?)"
);
my $updateItemSth = $dbh->prepare("
    UPDATE items SET holdingbranch = ?, onloan = ? WHERE itemnumber = ?;
");
sub migrate_checkout($c) {
    $checkoutStatement->execute(
        $old_issue_id++,
        $c->{borrowernumber},      # borrowernumber
        $c->{itemnumber},          # itemnumber
        $c->{issuedate},           # issuedate
        $c->{date_due},            # date_due
        $c->{branchcode},          # branchcode
        $c->{renewals},
    );

    $updateItemSth->execute($c->{branchcode}, $c->{date_due}, $c->{itemnumber});
}

sub validateAndConvertKeys($checkout) {
    my $errId = "Checkout itemnumber='".$checkout->{itemnumber}."', borrowernumber='".$checkout->{borrowernumber}."'";


    my $newItemnumber = $itemnumberConversionTable->fetch(  $checkout->{itemnumber}  );
    unless ($newItemnumber) {
        WARN "$errId has no itemnumber in itemnumberConversionTable!";
        return undef;
    }

    my $newBorrowernumber = $borrowernumberConversionTable->fetch(  $checkout->{borrowernumber}  );
    unless ($newBorrowernumber) {
        WARN "$errId has no Patron in the borrowernumberConversionTable!";
        return undef;
    }

    #Make sure the borrower exists!
    my $testingBorrower = Bulk::PatronImporter::GetBorrower($newBorrowernumber);
    unless (defined $testingBorrower) {
        WARN "$errId has no Patron '".$checkout->{borrowernumber}."->$newBorrowernumber' in Koha!";
        return undef;
    }

    #Make sure the parent biblio exists!
    my $i = Bulk::Item::getItemIn($newItemnumber);
    unless ($i && $i->{biblionumber}) {
        WARN "$errId has no biblio in Koha!";
        return;
    }

    if ($checkout->{barcode}) {
        unless ($i->{barcode}) {
            WARN "$errId has no Item in Koha!";
            return undef;
        }
        #Make sure barcode exists and matches the converted primary key from items import. This helps to detect issues with the ItemnumberConversionTable and
        #double check the issues actually match the items
        my $convertedItemBarcode = $itemnumberConversionTable->fetchBarcode(  $checkout->{itemnumber}  );
        unless ($convertedItemBarcode) {
            WARN "$errId has no Barcode/Item in the itemnumberConversionTable!";
            return undef;
        }
        unless ($checkout->{barcode} eq $convertedItemBarcode) {
            WARN "$errId. barcode='$convertedItemBarcode' from the itemnumberConversionTable doesn't match the Issue's own barcode '".$checkout->{barcode}."'!";
            return undef;
        }
        unless ($checkout->{barcode} eq $i->{barcode}) {
            WARN "$errId. barcode='".$i->{barcode}."' from the Koha database doesn't match the Issue's own barcode '".$checkout->{barcode}."'!";
            return undef;
        }
    }


    $checkout->{borrowernumber} = $newBorrowernumber;
    $checkout->{biblionumber}   = $i->{biblionumber};
    $checkout->{itemnumber}     = $newItemnumber;
    return $checkout;
}


my $i = 0;
while (<$fh>) {
    $i++;
    INFO "Processed $i Items" if ($i % 1000 == 0);

    my $checkout = Bulk::Util::newFromBlessedMigratemeRow($_);
    next unless validateAndConvertKeys($checkout);
    migrate_checkout($checkout);
}
