#!/opt/CSCperl/current/bin/perl

use warnings;
use strict;
$|=1;

use Getopt::Long qw(:config no_ignore_case);

use Exp::Config;

# Getting parameters
my $config = 'config.pl';
my $noanonymize = 0;
my ($help, $verbose, $exportEverything, $exportBoundRecords, $exportBibliographicRecords, $exportAuthoritiesRecords, $exportHoldingsRecords, $exportByWaterStyle);
my $exportWithPrecision = 0;

sub print_usage {
  (my $basename = $0) =~ s|.*/||;
  print <<USAGE;
$basename
  Exports all data from Voyager using various export strategies

  There used to be a bunch of scripts lying around. Now all of those are merged into one program where they can share common infrastucture.

Usage:
  --noanonymize           Do not anonymize confidential and personally identifiable information? Used when going live.
                          Anonymizes by default.
  -e, --everything        Exports all DB tables as is.
  -b, --bound             Exports bound MFHD records as MARC21 XML.
  -B, --bib               Exports bibliographic records as MARC21 XML.
  -A, --auth              Exports authorities records as MARC21 XML.
  -H, --holdings          Exports holdings records as MARC21 XML.
  --bywater               Export everything but MARC using ByWater export sql statements
  --precision=1|REGEXP    Defaults '$exportWithPrecision'.
                          Export with precision everything but MARC.
                          Parameter is a boolean or a regexp:
                            Boolean (true): When you want to run the whole Precise extract strategy.
                            Regexp: Used to select only a desired subset of filenames queries from
                                    the HASH in \%Exp::Strategy::Precision::queries.
                                    Used to test changes to extract SQL. Not useful when going live.
                          Parameter is mandatory if option given, but the
                          parameter is used only to limit the precision
  -c, --config=PATH       Default '$config'
                          PATH to the DB connection config.
  -h, --help              Show this help
  -v, --verbose           Show debug information
USAGE
}

GetOptions(
    'noanonymize'   => \$noanonymize,
    'e|everything'  => \$exportEverything,
    'b|bound'       => \$exportBoundRecords,
    'B|bib'         => \$exportBibliographicRecords,
    'A|auth'        => \$exportAuthoritiesRecords,
    'H|holdings'    => \$exportHoldingsRecords,
    'bywater'       => \$exportByWaterStyle,
    'p|precision:s' => \$exportWithPrecision,
    'c|config=s'    => \$config,
    'h|help'        => \$help,
    'v|verbose'     => \$verbose,
) or print_usage, exit 1;

if ($help) {
    print_usage;
    exit;
}

$ENV{ANONYMIZE} = ($noanonymize) ? 0 : 1;
$ENV{DEBUG} = 1 if ($verbose);
$ENV{VOYAGER_EXPORTER_CONFIG_PATH} = $config if ($config);
Exp::Config::LoadConfig($ENV{VOYAGER_EXPORTER_CONFIG_PATH});


if ($exportEverything) {
  require Exp::Strategy::Everything;
  Exp::Strategy::Everything::exportAllTables();
}

if ($exportWithPrecision) {
  require Exp::Strategy::Precision;
  Exp::Strategy::Precision::extract($exportWithPrecision);
}

my $boundRecordIds;
if ($exportBoundRecords) {
  require Exp::Strategy::BoundRecords;
  $boundRecordIds = Exp::Strategy::BoundRecords::export();
}

if ($exportBibliographicRecords) {
  require Exp::Strategy::MARC;
  Exp::Strategy::MARC::exportBiblios({exclude => $boundRecordIds});
}

if ($exportAuthoritiesRecords) {
  require Exp::Strategy::MARC;
  Exp::Strategy::MARC::exportAuth();
}

if ($exportHoldingsRecords) {
  require Exp::Strategy::MARC;
  Exp::Strategy::MARC::exportMFHD();
}

if ($exportByWaterStyle) {
  require Exp::Strategy::ByWaterExport;
}

