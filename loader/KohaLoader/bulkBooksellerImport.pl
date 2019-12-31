#!/usr/bin/perl

use Modern::Perl;
use experimental 'smartmatch', 'signatures';
$|=1;
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDIN, ":encoding(UTF-8)");

use Getopt::Long;
use Log::Log4perl qw(:easy);

use Getopt::Long;
use C4::Context;

my $booksellerFile = $ENV{DATA_SOURCE_DIR}.'/Bookseller.migrateme';
our $verbosity = 3;

my $help = <<HELP;

NAME
  $0 - Import Booksellers en masse

SYNOPSIS
  perl ./bulkBooksellerImport.pl --file $booksellerFile -v 6

DESCRIPTION
  Loads the Perl-serialized MMT-processed Bookserllers to Koha.

    --file filepath
          The perl-serialized HASH of Booksellers.

    -v level
          Verbose output to the STDOUT,
          Defaults to $verbosity, 6 is max verbosity, 0 is fatal only.

HELP

GetOptions(
    'file:s'                   => \$booksellerFile,
    'v|verbosity:i'            => \$verbosity,
);

require Bulk::Util; #Init logging && verbosity

unless ($booksellerFile) {
    die "$help\n\n--file is mandatory";
}

my $fh = Bulk::Util::openFile($booksellerFile);


my $dbh = C4::Context->dbh;
my $sthBooksellers = $dbh->prepare(
  'INSERT INTO aqbooksellers
    (
id, name, address1, address2,
address3, address4, phone, accountnumber,
othersupplier, currency, booksellerfax, notes,
bookselleremail, booksellerurl, postal, url,
active, listprice, invoiceprice, gstreg,
listincgst, invoiceincgst, tax_rate, discount,
fax, deliverytime
    )
  VALUES (
?, ?, ?, ?,
?, ?, ?, ?,
?, ?, ?, ?,
?, ?, ?, ?,
?, ?, ?, ?,
?, ?, ?, ?,
?, ?
  )'
);


my $sthBooksellerContacts = $dbh->prepare(
  'INSERT INTO aqcontacts
    (
id, booksellerid, name, position,
phone, altphone, fax, email,
notes, orderacquisition, claimacquisition, claimissues,
acqprimary, serialsprimary
    )
  VALUES (
?, ?, ?, ?,
?, ?, ?, ?,
?, ?, ?, ?,
?, ?
  )'
);


my $i = 0;
while (<$fh>) {
    $i++;
    INFO "Processed $i Booksellers" if ($i % 100 == 0);

    my $bs = Bulk::Util::newFromBlessedMigratemeRow($_);
    $sthBooksellers->execute(
undef, $bs->{name}, $bs->{address1}, $bs->{address2},
$bs->{address3}, $bs->{address4}, $bs->{phone}, $bs->{accountnumber},
$bs->{othersupplier}, $bs->{currency}, $bs->{booksellerfax}, $bs->{notes},
$bs->{bookselleremail}, $bs->{booksellerurl}, $bs->{postal}, $bs->{url},
$bs->{active}, $bs->{listprice}, $bs->{invoiceprice}, $bs->{gstreg},
$bs->{listincgst}, $bs->{invoiceincgst}, $bs->{tax_rate}, $bs->{discount},
$bs->{fax}, $bs->{deliverytime},
    );
    my $booksellerid = $sthBooksellers->{mysql_insertid};

    my $cs = $bs->{aqcontacts};
    $sthBooksellerContacts->execute(
undef, $booksellerid, $cs->{name}, $cs->{position},
$cs->{phone}, $cs->{altphone}, $cs->{fax}, $cs->{email},
$cs->{notes}, $cs->{orderacquisition}, $cs->{claimacquisition}, $cs->{claimissues},
$cs->{acqprimary}, $cs->{serialsprimary},
    );
}
