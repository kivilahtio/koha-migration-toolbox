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
use Data::Dumper;

#Local modules
use Bulk::BibImporter;
use Bulk::OplibMatcher;

our $verbosity = 3;
my %args = (inputMarcFile =>                      ($ENV{MMT_DATA_SOURCE_DIR}//'.').'/biblios.marcxml',
            biblionumberConversionTable =>        ($ENV{MMT_WORKING_DIR}//'.').'/biblionumberConversionTable',
            matchLog =>                           ($ENV{MMT_WORKING_DIR}//'.').'/matchVerifications.log',
            mergeStrategy =>    'defer',
            migrateStrategy =>  'chunk',
            preserveIds =>      $ENV{MMT_PRESERVE_IDS} // 0,
            legacyIdFieldDef => '001',
            workers =>           4);

Getopt::Long::GetOptions(
  'file:s'              => \$args{inputMarcFile},
  'matchLog:s'          => \$args{matchLog},
  'mergeStrategy:s'     => \$args{mergeStrategy},
  'migrateStrategy:s'   => \$args{migrateStrategy},
  'bnConversionTable:s' => \$args{biblionumberConversionTable},
  'preserveIds'         => \$args{preserveIds},
  'workers:i'           => \$args{workers},
  'v:i'                 => \$verbosity,
  'legacyIdField:s'     => \$args{legacyIdFieldDef},
  'version'             => sub { Getopt::Long::VersionMessage() },
  'h|help'              => sub {
  print <<HELP;

NAME
  $0 - Import Biblios en masse

SYNOPSIS
  perl ./bulkBibImport.pl --file '/home/koha/biblios.marcxml' -v $verbosity \
      --bnConversionTable '$args{biblionumberConversionTable}' \
      --matchLog 'matchVerifications.log' --mergeStrategy '$args{mergeStrategy}'

DESCRIPTION
  -Migrates a MARC21XML Collection file into Koha.
  --File MUST be in UTF-8
  --File MUST contain MARC21 bibliographic records

    --file filepath
          The MARC21XML file

    --legacyIdField field[subfield] definition
          From where to get the legacy system bibliographic record database id?
          Defaults to '$args{legacyIdFieldDef}'.
          Example: 999\$c
          This is converted using the biblionumberConversionTable to a fresh Koha biblionumber.
          The old field[subfield] is not deleted.

    --matchLog filepath
          Where to write the MARC match/deduplication log?
          Each incoming MARC Record is matched against the search index using
          several search-steps of increasingly decreasing match certainty.
          Matchlog collects a report of confident matches and matches that need
          to be manually verified.
          The matchlog is also read for manual overrides to fuzzy matches, so
          one can:
          1) first run the Biblio import with a blank matchlog
          2) then fill the manual verification info to the matchlog
          3) remove new biblios
          4) migrate biblios again using the existing matchlog, thus fuzzy
             matches are manually overridden.
          See. Bulk::OplibMatcher for more information.

    --migrateStrategy name
          Defaults to '$args{migrateStrategy}'.
          Importing a lot of bibs takes a lot of time. Trying different import strategies
          to speed up the ginormous task. This is a compromise between maintainability vs
          speed. 2 000 000 bibs MUST be importable in 4 hours.
          Currently supported values:
            'fast' - A memory intensive crunch of hand-tailored direct-SQL migration.
                     ATM is 4 times faster than the 'koha'-strategy. 100 bibs in 1s on koha*-kktest
            'chunk' - Like fast, uses less memory.
            'koha' - do it like they do it on the Koha channel!

    --mergeStrategy name
          Defaults to '$args{mergeStrategy}'.
          Which merge strategy to use when a match has been found?
          Could use a C4::Matcher or MARC modification templates to intelligently
          merge records.
          Currently only supported values are:
            'overwrite' - The incoming records completely overwrites
                          the existing one
            'defer' - The incoming record is completely lost and doesn't
                      touch the existing record

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

    --preserveIds
          Should the source system database IDs be preserved or should they be overridden by defaults from Koha?
          Defaults to off, new IDs are generated

    --workers count
          Into how many workers the migration is parallellized to.
          Defaults to '$args{workers}'

    -v level
          Verbose output to the STDOUT,
          Defaults to $verbosity, 6 is max verbosity, 0 is fatal only.

    --version
          Print version info

HELP
  exit 0;
},
); #EO Getopt::Long::GetOptions()

require Bulk::Util; #Init logging && verbosity

Bulk::Util::logArgs(\%args);

unless ($args{inputMarcFile}) {
    die "--file is mandatory";
}

my $bimporter = Bulk::BibImporter->new(\%args);
#TODO:: Make sure the biblio_metadata -row is created!

my $disablePrefs = {
  CataloguingLog => {
    old => C4::Context->preference( 'CataloguingLog' ),
    new => 0,
  },
  AuthoritiesLog => {
    old => C4::Context->preference( 'AuthoritiesLog' ),
    new => 0,
  },
};

$bimporter->disableUnnecessarySystemSettings($disablePrefs);

END { #Make sure this block of code runs after this program ends.
  $bimporter->reEnableSystemSettings($disablePrefs) if $bimporter;
}

$bimporter->bimp();
