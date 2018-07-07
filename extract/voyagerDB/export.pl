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

Usage:
  -e, --everything        Exports all DB tables as is.
  -b, --bound             Exports bound MFHD records.
  -c, --config=PATH       Default 'config.yml'
                          PATH to the DB connection config.
  -s, --separator=CHAR    This character will be used to separate fields.
                          Some characters like | or ; will need to be escaped
                          in the parameter setting, like -s=\\| or -s=\\;
                          If no separator is specified, the delimiter pref
                          will be used (or a comma, if the pref is empty)
  -h, --help              Show this help
  -v, --verbose           Show debug information
USAGE
}

# Getting parameters
my $config = 'config.yml';
my ($help, $verbose, $exportEverything, $exportBoundRecords);

GetOptions(
    'e|everything'  => \$exportEverything,
    'b|bound'       => \$exportBoundRecords,
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
