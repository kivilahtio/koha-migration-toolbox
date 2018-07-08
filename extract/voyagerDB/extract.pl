#!/opt/CSCperl/current/bin/perl

use warnings;
use strict;

use Getopt::Long qw(:config no_ignore_case);

$|=1;

sub print_usage {
  (my $basename = $0) =~ s|.*/||;
  print <<USAGE;
$basename
  Exports all data from Voyager using various export strategies

  There used to be a bunch of scripts lying around. Now all of those are merged into one program where they can share common infrastucture.

Usage:
  -e, --everything        Exports all DB tables as is.
  -b, --bound             Exports bound MFHD records.
  -c, --config=PATH       Default 'config.yml'
                          PATH to the DB connection config.
  --bywater               Export everything but MARC using ByWater export sql statements
  -h, --help              Show this help
  -v, --verbose           Show debug information
USAGE
}

# Getting parameters
my $config = 'config.yml';
my ($help, $verbose, $exportEverything, $exportBoundRecords, $exportBibliographicRecords, $exportAuthoritiesRecords, $exportHoldingsRecords, $exportByWaterStyle);

GetOptions(
    'e|everything'  => \$exportEverything,
    'b|bound'       => \$exportBoundRecords,
    'B|bib'         => \$exportBibliographicRecords,
    'A|auth'        => \$exportAuthoritiesRecords,
    'H|holdings'    => \$exportHoldingsRecords,
    'bywater'       => \$exportByWaterStyle,
    'c|config=s'    => \$config,
    'h|help'        => \$help,
    'v|verbose'     => \$verbose,
) or print_usage, exit 1;

if ($help) {
    print_usage;
    exit;
}

$ENV{DEBUG} = 1 if ($verbose);
$ENV{VOYAGER_EXPORTER_CONFIG_PATH} = $config if ($config);

if ($exportEverything) {
  require Exp::Everything;
  Exp::Everything::exportAllTables();
}

my $boundRecordIds;
if ($exportBoundRecords) {
  require Exp::BoundRecords;
  $boundRecordIds = Exp::BoundRecords::export();
}

if ($exportBibliographicRecords) {
  require Exp::MARC;
  Exp::MARC::exportBiblios({exclude => $boundRecordIds});
}

if ($exportAuthoritiesRecords) {
  require Exp::MARC;
  Exp::MARC::exportAuth();
}

if ($exportHoldingsRecords) {
  require Exp::MARC;
  Exp::MARC::exportMFHD();
}

if ($exportByWaterStyle) {
  require Exp::ByWaterExport;
  Exp::ByWaterExport::export();
}

