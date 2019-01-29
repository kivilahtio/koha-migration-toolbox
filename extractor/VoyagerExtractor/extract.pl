#!/opt/CSCperl/current/bin/perl

use warnings;
use strict;
$|=1;

use Getopt::Long qw(:config no_ignore_case);

use Exp::Config;

# Getting parameters
my $config = 'config.pl';
my $noanonymize = 0;
my ($help, $verbose, $exportEverything, $exportBoundRecords, $exportBibliographicRecords, $exportAuthoritiesRecords, $exportHoldingsRecords, $exportByWaterStyle, $runQuery);
my $excludedTables = '(BIB_USAGE_LOG|OPAC_SEARCH_LOG)';
my $includedTables;
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
  --exclude=REGEXP        - When exporting --everything, excludes the given tables.
                            String of table names, case insensitively.
                            Defaults to 'BIB_USAGE_LOG OPAC_SEARCH_LOG'
                          - When exporting with --precision, excludes the given exportable filenames.
  --include=REGEXP        - When exporting with --precision, exports only the filenames that match the given regexp.
                            Used to test changes to extract SQL. Not useful when going live.
  -b, --bound             Exports bound MFHD records as MARC21 XML.
  -B, --bib               Exports bibliographic records as MARC21 XML.
  -A, --auth              Exports authorities records as MARC21 XML.
  -H, --holdings          Exports holdings records as MARC21 XML.
  --bywater               Export everything but MARC using ByWater export sql statements
  --precision=MODULE      Defaults to '$exportWithPrecision'.
                          Export with precision everything but MARC.
                          Parameter is the Exp::Strategy::Precision -export module name,
                          eg. HAMK
  -r --runq               Run a query. Outputs invalid .csv to STDOUT.
                          SQL as the parameter value, or a path to file containing the SQL.
                          Used to test SQL.
  -c, --config=PATH       Defaults to '$config'
                          PATH to the DB connection config.
  -h, --help              Show this help
  -v, --verbose           Show debug information

Examples:

  Dump all tables except some nasty ones
  $0 --everything --exclude (BIB_USAGE_LOG|OPAC_SEARCH_LOG) -v

  Export Helka-DB with precision, export only filenames starting with 02, but exclude the given file
  $0 --precision Helka --exclude 02a-item_notes.csv --include ^02

USAGE
}

GetOptions(
    'noanonymize'   => \$noanonymize,
    'e|everything'  => \$exportEverything,
    'exclude:s'     => \$excludedTables,
    'include:s'     => \$includedTables,
    'b|bound'       => \$exportBoundRecords,
    'B|bib'         => \$exportBibliographicRecords,
    'A|auth'        => \$exportAuthoritiesRecords,
    'H|holdings'    => \$exportHoldingsRecords,
    'bywater'       => \$exportByWaterStyle,
    'p|precision:s' => \$exportWithPrecision,
    'r|runq:s'      => \$runQuery,
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
  Exp::Strategy::Everything::exportAllTables($excludedTables);
}

if ($exportWithPrecision) {
  require Exp::Strategy::Precision;
  Exp::Strategy::Precision::extract($exportWithPrecision, $excludedTables, $includedTables);
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

if ($runQuery) {
  if (-e $runQuery) {
    warn "INFO: Treating parameter \$runQuery='$runQuery' as a file to slurp the SQL from";
    open(my $FH, '<:encoding(UTF-8)', $runQuery) or die "Opening query file '$runQuery' failed: $!";
    local $/ = undef;
    $runQuery = <$FH>;
    close($FH);
  }
  require Exp::DB;
  my $dbh = Exp::DB::dbh();
  warn "INFO: Starting DB query"; my $start = time;
  my $res = $dbh->selectall_arrayref($runQuery) || die("Executing query '$runQuery' failed: ".$dbh->errstr);
  warn "INFO: Ending DB query, runtime ".(time - $start)."s";
  warn "INFO: Dumping results"; $start = time;
  print join(',', map {$_ // ''} @$_)."\n" for @$res; #For now this is intended only for testing SQL, nothing more. It is faster for me to make a simple SQL interface, than start fiddling with orcale cli tools on Solaris.
  warn "INFO: Dump complete, runtime ".(time - $start)."s";
}
