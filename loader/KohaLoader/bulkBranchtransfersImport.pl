#!/usr/bin/perl

use Modern::Perl '2015';
use experimental 'smartmatch', 'signatures';
$|=1;
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDIN, ":encoding(UTF-8)");

use Getopt::Long;
use Log::Log4perl qw(:easy);

use C4::Context;

use Bulk::ConversionTable::ItemnumberConversionTable;

my ($transfersFile);
our $verbosity = 3;
my $itemnumberConversionTableFile = 'subscriptionidConversionTable';
my $itemnumberConversionTable;

my $help = <<HELP;

NAME
  $0 - Import Subscriptions and Serials en masse

SYNOPSIS
  perl bulkSubscriptionImport.pl --subscriptionFile /home/koha/pielinen/subs.migrateme \
    --file /file/path.csv -v $verbosity \
    --inConversionTable $itemnumberConversionTableFile


DESCRIPTION

    --file filepath
          The perl-serialized HASH of Branchtransfers.

    --inConversionTable filePath
          Defaults to $itemnumberConversionTableFile
          Where to read the converted itemnumbers.

    -v level
          Verbose output to the STDOUT,
          Defaults to $verbosity, 6 is max verbosity, 0 is fatal only.

HELP

GetOptions(
    'file:s'                   => \$transfersFile,
    'inConversionTable:s'      => \$itemnumberConversionTableFile,
    'v|verbosity:i'            => \$verbosity,
    'h|help'                   => sub {print $help; exit 0;},
);

require Bulk::Util; #Init logging && verbosity

unless ($transfersFile) {
    die "$help\n\n--file is mandatory";
}

my $sth;
sub getSth() {
    my $dbh = C4::Context->dbh();

    ## Aside from Koha::Item::Transfer there doesn't seem to be an easy API for creating branchtransfers internally.
    ## Using SQL
    $sth = $dbh->prepare("INSERT INTO branchtransfers
                                      (itemnumber, datesent, frombranch, tobranch, comments)
                           VALUES     (?,          ?,        ?,          ?,        ?)")
        unless $sth;
    return $sth;
}

sub validateAndConvertKeys($t) {
    my $newItemnumber = $itemnumberConversionTable->fetch($t->{itemnumber});
    unless ($newItemnumber) {
        WARN "Transfer itemnumber='".$t->{itemnumber}."' at row '$.':  No new itemnumber in the itemnumberConversionTable!";
        return undef;
    }
    $t->{itemnumber} = $newItemnumber;
    return $t;
}

sub migrateTransfer($t) {
    eval {
        $sth->execute($t->{itemnumber}, $t->{datesent}, $t->{frombranch}, $t->{tobranch}, $t->{comments});
    };
    if ($@) {
        print $@."\nTrying to recover by recreating the DB connection and statements...";
        sleep 10; #Waiting a bit for the connection to possibly get back on
        getSth();
        $sth->execute($t->{itemnumber}, $t->{datesent}, $t->{frombranch}, $t->{tobranch}, $t->{comments});
    }
}

INFO "Opening ItemnumberConversionTable '$itemnumberConversionTableFile' for reading";
$itemnumberConversionTable     = Bulk::ConversionTable::ItemnumberConversionTable->new(     $itemnumberConversionTableFile,     'read' );
getSth();

my $fh = Bulk::Util::openFile($transfersFile);
my $i = 0;
while (<$fh>) {
    $i++;
    INFO "Processed $i transfers" if ($i % 100 == 0);

    my $transfer = Bulk::Util::newFromBlessedMigratemeRow($_);
    next unless validateAndConvertKeys($transfer);
    migrateTransfer($transfer);
}
$fh->close();
