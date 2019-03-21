#!/usr/bin/perl

use Modern::Perl;
use experimental 'smartmatch', 'signatures';
$|=1;
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDIN, ":encoding(UTF-8)");

use Getopt::Long;
use Log::Log4perl qw(:easy);

use Getopt::Long;
use C4::Items;
use C4::Members;
use C4::Accounts;
use Bulk::ConversionTable::BorrowernumberConversionTable;
use Bulk::ConversionTable::ItemnumberConversionTable;

my $importFile;
our $verbosity = 3;
my $borrowernumberConversionTable = 'borrowernumberConversionTable';
my $itemnumberConversionTable = 'itemnumberConversionTable';

my $help = <<HELP;

NAME
  $0 - Import fines en masse

SYNOPSIS
  perl ./bulkFinesImport.pl --file /home/koha/pielinen/fines.migrateme -v 6 \
      --bnConversionTable $borrowernumberConversionTable \
      --inConversionTable $itemnumberConversionTable

DESCRIPTION
  Loads the Perl-serialized MMT-processed fines to Koha.

    --file filepath
          The perl-serialized HASH of Fines.

    --bnConversionTable filepath
          From which file to read the converted borrowernumber?
          Defaults to '$borrowernumberConversionTable'

    --inConversionTable filepath
          To which file to write the itemnumber to barcode conversion. Items are best referenced
          by their barcodes, because the itemnumbers can overlap with existing Items.
          Defaults to '$itemnumberConversionTable'

    -v level
          Verbose output to the STDOUT,
          Defaults to $verbosity, 6 is max verbosity, 0 is fatal only.

HELP

GetOptions(
    'file:s'                   => \$importFile,
    'b|bnConversionTable:s'    => \$borrowernumberConversionTable,
    'i|inConversionTable:s'    => \$itemnumberConversionTable,
    'v|verbosity:i'            => \$verbosity,
);

require Bulk::Util; #Init logging && verbosity

unless ($importFile) {
    die "$help\n\n--file is mandatory";
}

my $fh = Bulk::Util::openFile($importFile);

INFO "Opening BorrowernumberConversionTable '$borrowernumberConversionTable' for reading";
$borrowernumberConversionTable = Bulk::ConversionTable::BorrowernumberConversionTable->new($borrowernumberConversionTable, 'read');
INFO "Opening ItemnumberConversionTable '$itemnumberConversionTable' for reading";
$itemnumberConversionTable =     Bulk::ConversionTable::ItemnumberConversionTable->new($itemnumberConversionTable, 'read');


my $dbh = C4::Context->dbh;
my $fineStatement = $dbh->prepare(
    'INSERT INTO  accountlines
        (borrowernumber, itemnumber, accountno, date, amount, description, accounttype, amountoutstanding, notify_id, manager_id, issue_id)
    VALUES (?, ?, ?, ?, ?,?, ?,?,?,?,?)'
);
my $issueStatement = $dbh->prepare(
    'SELECT issue_id FROM issues where itemnumber = ? AND borrowernumber = ? AND returndate IS NULL'
);


sub finesImport($fine) {
    my $accountno  = C4::Accounts::getnextacctno( $fine->{borrowernumber} );
    my $notifyid = 0;
    my $manager_id = C4::Context->userenv ? C4::Context->userenv->{'number'} : 0;
    my @issue_id = ();

    if ($fine->{accounttype} eq "FU") {
	$issueStatement->execute($fine->{itemnumber}, $fine->{borrowernumber});
	my $row_count = 0;
	while (my @row = $issueStatement->fetchrow_array()) {
	    $issue_id[0] = @row[0];
	    $row_count++;
	}

	if ($row_count > 1) {
	    ERROR "Fine '".fineId($fine)."' is related to multiple checkouts!";
	    $issue_id[0] = undef; # Fallback to not connecting it to anything
	}
    }

    $fineStatement->execute(
        $fine->{borrowernumber}, $fine->{itemnumber}, $accountno, $fine->{date}, $fine->{amount},
        $fine->{description}, $fine->{accounttype}, $fine->{amountoutstanding}, $notifyid, $manager_id, $issue_id[0]
    );

    if ($fineStatement->errstr) {
        ERROR "Error INSERT:ing Fine '".fineId($fine)."': ".$fineStatement->errstr;
    }
}

sub validateAndConvertKeys($fine) {
    #Convert old source system primary key to a new borrowernumber 
    my $borrowernumber = $borrowernumberConversionTable->fetch( $fine->{borrowernumber} );
    unless ($borrowernumber) {
        WARN "Fine '".fineId($fine)."' has no Borrower in conversion table!";
        return undef;
    }
    #Make sure the borrower exists!
    my $testingBorrower = C4::Members::GetMember(borrowernumber => $borrowernumber);
    unless (defined $testingBorrower) {
        WARN "Fine '".fineId($fine)."'. Patron ".$fine->{borrowernumber}."->$borrowernumber doesn't exist in Koha!";
        return undef;
    }
    $fine->{borrowernumber} = $borrowernumber;

    if ($fine->{itemnumber}) {
        my $itemnumber = $itemnumberConversionTable->fetch( $fine->{itemnumber} );
        unless ($itemnumber) {
            #WARN "Fine for borrowernumber ".$fine->{borrowernumber}." has no Item in conversion table!";
            #next();
            $itemnumber = undef; #There could be an old fine for a deleted item
        }
        $fine->{itemnumber} = $itemnumber;
    }
    return 1;
}

my $i = 0;
while (<$fh>) {
    $i++;
    INFO "Processed $i Items" if ($i % 1000 == 0);

    my $fine = Bulk::Util::newFromBlessedMigratemeRow($_);
    next unless validateAndConvertKeys($fine);
    finesImport($fine);
}

sub fineId($fine) {
    return 'b:'.$fine->{borrowernumber}.'-i:'.$fine->{itemnumber};
}
