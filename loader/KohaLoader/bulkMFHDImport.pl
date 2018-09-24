#!/usr/bin/perl

#Pragmas
use Modern::Perl;
use experimental 'smartmatch', 'signatures';
binmode( STDOUT, ":encoding(UTF-8)" );
binmode( STDIN,  ":encoding(UTF-8)" );
use utf8;
use Carp;
#$|=1; #Are hot filehandles necessary?

# External modules
use Getopt::Long;
use Log::Log4perl qw(:easy);

#Local modules
use Bulk::MFHDImporter;

our $verbosity = 3;
my %args = (inputMarcFile =>                      ($ENV{MMT_DATA_SOURCE_DIR}//'.').'/holdings.marcxml',
            biblionumberConversionTable =>        ($ENV{MMT_WORKING_DIR}//'.').'/biblionumberConversionTable',
            holding_idConversionTable =>          ($ENV{MMT_WORKING_DIR}//'.').'/holding_idConversionTable',
            legacyIdFieldDef => '004',
            workers =>           4);

Getopt::Long::GetOptions(
  'file:s'              => \$args{inputMarcFile},
  'bnConversionTable:s' => \$args{biblionumberConversionTable},
  'hiConversionTable:s' => \$args{holding_idConversionTable},
  'v|verbosity:i'       => \$verbosity,
  'legacyBibIdField:s'  => \$args{legacyBibIdFieldDef},
  'workers:i'           => \$args{workers},
  'version'             => sub { Getopt::Long::VersionMessage() },
  'h|help'              => sub {
  print <<HELP;

NAME
  $0 - Import MFHDs en masse

SYNOPSIS
  perl ./bulkMFHDImport.pl --file '/home/koha/holdings.marcxml' -v $verbosity \
      --bnConversionTable '$args{biblionumberConversionTable}'

DESCRIPTION
  -Migrates a MARC21XML Holdings Collection file into Koha.
  --File MUST be in UTF-8
  --File MUST contain MARC21 holdings records

    --file filepath
          The MARC21XML file

    --legacyBibIdField field[subfield] definition
          From where to get the legacy system bibliographic record database id?
          Defaults to '$args{legacyBibIdFieldDef}'.
          Example: 999\$d
          This is converted using the biblionumberConversionTable to a fresh Koha biblionumber.
          The old field[subfield] is not deleted.

    --bnConversionTable filepath
          Where to write the converted biblionumbers?
          We are adding Biblios to a database with existing Biblios, so we need to convert
          biblionumbers so they won't overlap with existing ones.
          biblionumberConversionTable has the following format, where first column is the original
          biblio id and the second column is the mapped Koha biblionumber:

              id;newid;operation;status
              685009;685009;insert;ok
              685010;685010;insert;ok
              685011;685011;insert;ok
              685012;685012;insert;ok
              ...

          Defaults to '$args{biblionumberConversionTable}'

    --hiConversionTable filepath
          Defaults to '$args{holding_idConversionTable}'

    --workers count
          Into how many workers the migration is parallellized to.
          Defaults to '$args{workers}'

    -v --verbosity level
          Verbose output to the STDOUT,
          Defaults to $verbosity, 6 is max verbosity, 0 is fatal only.

    --version
          Print version info

    --help
          Print this helpful help

HELP
  exit 0;
},
); #EO Getopt::Long::GetOptions()

require Bulk::Util; #Init logging && verbosity

unless ($args{inputMarcFile}) {
    die "--file is mandatory";
}

my $mfhder = Bulk::MFHDImporter->new(\%args);
$mfhder->doImport();
