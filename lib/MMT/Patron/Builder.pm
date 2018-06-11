use 5.22.1;

package MMT::Patron::Builder;
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
use MMT::Patron::Tester;
use MMT::Patron;
use MMT::Table::Branchcodes;
use MMT::Table::NoteType;
use MMT::Table::PatronCategorycode;
use MMT::Table::PatronStatistics;

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
#Translation tables
my $patronCategorycodeFile = MMT::Config::translationsDir."/borrowers.categorycode.yaml";
my $branchcodeFile         = MMT::Config::translationsDir."/branchcodes.yaml";
my $noteTypeFile           = MMT::Config::translationsDir."/note_type.yaml";
my $patronStatisticsFile   = MMT::Config::translationsDir."/patron_stat.yaml";

my $outputFile = MMT::Config::kohaImportDir."/borrowers.migrateme";

sub new {
  $log->trace("Constructor(@_)") if $log->is_trace();
  my ($class, $p) = @_;
  my $self = bless({}, $class);
  $self->_loadRepositories();
  $self->_loadTranslationTables();
  $self->{tester} = MMT::Patron::Tester->new();
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
    my $patron = MMT::Patron->new();
    eval {
      $patron->build($o, $s);
    };
    if ($@) {
      if (ref($@) eq 'MMT::Exception::Delete') {
        $log->debug($patron->logId()." was killed in action") if $log->is_debug();
      }
      else {
        $log->fatal("Received an unhandled exception '".MMT::Validator::dumpObject($@)."'") if $log->is_fatal();
      }
    }
    else {
      print $outFH serialize($patron)."\n";
      $log->debug("Wrote ".$patron->logId()) if $log->is_debug();
      $s->{tester}->test($patron);
      $w++;
    }
  }

  close $outFH;
  close $inFH;
  $log->info("Patrons built, $w/$i objects survived");
}

sub addresses {
  $_[0]->{addresses} = $_[1] if @_ == 2;
  return $_[0]->{addresses};
}
sub groups {
  $_[0]->{groups} = $_[1] if @_ == 2;
  return $_[0]->{groups};
}
sub groups_nulls {
  $_[0]->{groups_nulls} = $_[1] if @_ == 2;
  return $_[0]->{groups_nulls};
}
sub notes {
  $_[0]->{notes} = $_[1] if @_ == 2;
  return $_[0]->{notes};
}
sub phones {
  $_[0]->{phones} = $_[1] if @_ == 2;
  return $_[0]->{phones};
}
sub statisticalCategories {
  $_[0]->{statisticalCategories} = $_[1] if @_ == 2;
  return $_[0]->{statisticalCategories};
}
sub categorycodeTranslator {
  $_[0]->{categorycodeTranslator} = $_[1] if @_ == 2;
  return $_[0]->{categorycodeTranslator};
}
sub branchcodeTranslation {
  $_[0]->{branchcodeTranslation} = $_[1] if @_ == 2;
  return $_[0]->{branchcodeTranslation};
}
sub noteTypeTranslation {
  $_[0]->{noteTypeTranslation} = $_[1] if @_ == 2;
  return $_[0]->{noteTypeTranslation};
}
sub patronStatisticsTranslation {
  $_[0]->{patronStatisticsTranslation} = $_[1] if @_ == 2;
  return $_[0]->{patronStatisticsTranslation};
}

sub _loadRepositories($s) {

  $s->addresses( MMT::Cache->new({
    name => "Patron address data",
    file => $patron_addresses_file,
    keys => ['patron_id'],
  }) );
  $s->groups( MMT::Cache->new({
    name => "Patron group and bracode data",
    file => $patron_groups_file,
    keys => ['patron_id'],
  }) );
  $s->groups_nulls( MMT::Cache->new({
    name => "Patron group and bracode data from nulled table",
    file => $patron_groups_nulls_file,
    keys => ['patron_id'],
  }) );
  $s->notes( MMT::Cache->new({
    name => "Patron notes",
    file => $patron_notes_file,
    keys => ['patron_id'],
  }) );
  $s->phones( MMT::Cache->new({
    name => "Patron phone numbers",
    file => $patron_phones_file,
    keys => ['patron_id'],
  }) );
  $s->statisticalCategories( MMT::Cache->new({
    name => "Patron statistical categories",
    file => $patron_stat_codes_file,
    keys => ['patron_id'],
  }) );
}
sub _loadTranslationTables($s) {
  $s->categorycodeTranslator      ( MMT::Table::PatronCategorycode ->new({file => $patronCategorycodeFile }) );
  $s->branchcodeTranslation       ( MMT::Table::Branchcodes        ->new({file => $branchcodeFile         }) );
  $s->noteTypeTranslation         ( MMT::Table::NoteType           ->new({file => $noteTypeFile           }) );
  $s->patronStatisticsTranslation ( MMT::Table::PatronStatistics   ->new({file => $patronStatisticsFile   }) );
}

sub serialize($o) {
  $Data::Dumper::Indent = 0;
  $Data::Dumper::Sortkeys = 1;
  $Data::Dumper::Useqq = 1;
  $Data::Dumper::Varname = 'VAR1';
  $Data::Dumper::Purity = 1;
  my $dump = Data::Dumper::Dumper($o);
  $dump =~ s/\n/\\n/g;
  return $dump;
}

return 1;