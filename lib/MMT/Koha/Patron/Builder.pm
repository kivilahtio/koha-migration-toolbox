use 5.22.1;

package MMT::Koha::Patron::Builder;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';

#External modules
use Text::CSV_XS;
use Data::Dumper;

#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);
use MMT::Validator;
use MMT::Cache;
use MMT::Tester;
use MMT::Koha::Patron;
use MMT::TranslationTable::Branchcodes;
use MMT::TranslationTable::NoteType;
use MMT::TranslationTable::PatronCategorycode;
use MMT::TranslationTable::PatronStatistics;

=head1 NAME

MMT::Patron::Builder - Manages the build of Koha borrowers

=head2 DESCRIPTION

=cut

#Introduce the exported files needed to mash the patrons up!
my $patron_names_dates_file     = MMT::Config::voyagerExportDir."/07-patron_names_dates.csv";
my $patron_addresses_file       = MMT::Config::voyagerExportDir."/05-patron_addresses.csv";
my $patron_groups_file          = MMT::Config::voyagerExportDir."/06-patron_groups.csv";
my $patron_groups_nulls_file    = MMT::Config::voyagerExportDir."/08-patron_groups_nulls.csv";
my $patron_notes_file           = MMT::Config::voyagerExportDir."/09-patron_notes.csv";
my $patron_phones_file          = MMT::Config::voyagerExportDir."/10-patron_phones.csv";
my $patron_stat_codes_file      = MMT::Config::voyagerExportDir."/11-patron_stat_codes.csv";

my $outputFile = MMT::Config::kohaImportDir."/borrowers.migrateme";

#Add a bit of type-safety
use fields qw(addresses groups groups_nulls notes phones statisticalCategories categorycodeTranslator branchcodeTranslation
              noteTypeTranslation patronStatisticsTranslation);

sub new {
  $log->trace("Constructor(@_)") if $log->is_trace();
  my ($class, $p) = @_;
  my $self = bless({}, $class);
  $self->_loadRepositories();
  $self->_loadTranslationTables();
  $self->{tester} = MMT::Tester->new(MMT::Config::testDir.'/patrons.yaml');
  return $self;
}

sub build($s) {
  $log->info("Starting to build Patrons");

  my $csv=Text::CSV_XS->new({ binary => 1 });
  open(my $inFH, '<:encoding(UTF-8)', $patron_names_dates_file);
  $csv->column_names($csv->getline($inFH));
  $log->info("Loading file '$patron_names_dates_file', identified columns '".join(',', $csv->column_names())."'");

  #Open output file
  $log->info("Opening file '$outputFile' for export");
  open(my $outFH, '>:encoding(UTF-8)', $outputFile);

  my $i = 0; #Track how many patrons are processed
  my $w = 0; #Track how many patrons actually survived the build
  while (my $o = $csv->getline_hr($inFH)){
    $i++;
    my $ko = MMT::Koha::Patron->new();
    eval {
      $ko->build($o, $s);
    };
    if ($@) {
      if (ref($@) eq 'MMT::Exception::Delete') {
        $log->debug($ko->logId()." was killed in action") if $log->is_debug();
      }
      else {
        $log->fatal("Received an unhandled exception '".MMT::Validator::dumpObject($@)."'") if $log->is_fatal();
      }
    }
    else {
      print $outFH $ko->serialize()."\n";
      $log->debug("Wrote ".$ko->logId()) if $log->is_debug();
      $s->{tester}->test($ko);
      $w++;
    }
  }

  close $outFH;
  close $inFH;
  $log->info("Built, $w/$i objects survived");
}

sub _loadRepositories($s) {
  $s->{addresses            } = MMT::Cache->new({name => "Patron address data"                            , file => $patron_addresses_file   , keys => ['patron_id']});
  $s->{groups               } = MMT::Cache->new({name => "Patron group and bracode data"                  , file => $patron_groups_file      , keys => ['patron_id']});
  $s->{groups_nulls         } = MMT::Cache->new({name => "Patron group and bracode data from nulled table", file => $patron_groups_nulls_file, keys => ['patron_id']});
  $s->{notes                } = MMT::Cache->new({name => "Patron notes"                                   , file => $patron_notes_file       , keys => ['patron_id']});
  $s->{phones               } = MMT::Cache->new({name => "Patron phone numbers"                           , file => $patron_phones_file      , keys => ['patron_id']});
  $s->{statisticalCategories} = MMT::Cache->new({name => "Patron statistical categories"                  , file => $patron_stat_codes_file  , keys => ['patron_id']});
}
sub _loadTranslationTables($s) {
  $s->{categorycodeTranslator}      = MMT::TranslationTable::PatronCategorycode ->new();
  $s->{branchcodeTranslation}       = MMT::TranslationTable::Branchcodes        ->new();
  $s->{noteTypeTranslation}         = MMT::TranslationTable::NoteType           ->new();
  $s->{patronStatisticsTranslation} = MMT::TranslationTable::PatronStatistics   ->new();
}

return 1;