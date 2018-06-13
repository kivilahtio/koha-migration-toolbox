use 5.22.1;

package MMT::Koha::Issue::Builder;
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
use MMT::Koha::Issue;
use MMT::Table::LocationId;
use MMT::Table::Branchcodes;

#Introduce the exported files needed to mash the objects up!
my $current_circ_file      = MMT::Config::voyagerExportDir."/12-current_circ.csv";
my $last_borrow_dates_file = MMT::Config::voyagerExportDir."/13-last_borrow_dates.csv";

my $outputFile = MMT::Config::kohaImportDir."/issues.migrateme";

#Add a bit of type-safety
use fields qw(lastBorrowDates locationIdTranslation);

sub new {
  $log->trace("Constructor(@_)") if $log->is_trace();
  my ($class, $p) = @_;
  my $self = bless({}, $class);
  $self->_loadRepositories();
  $self->_loadTranslationTables();
  $self->{tester} = MMT::Tester->new(MMT::Config::testDir.'/issues.yaml');
  return $self;
}

sub build($s) {
  $log->info("Starting to build");

  my $csv=Text::CSV_XS->new({ binary => 1 });
  open(my $inFH, '<:encoding(UTF-8)', $current_circ_file);
  $csv->column_names($csv->getline($inFH));
  $log->info("Loading file '$current_circ_file', identified columns '".join(',', $csv->column_names())."'");

  #Open output file
  $log->info("Opening file '$outputFile' for export");
  open(my $outFH, '>:encoding(UTF-8)', $outputFile);

  my $i = 0; #Track how many KohaObjects are processed
  my $w = 0; #Track how many KohaObjects actually survived the build
  while (my $o = $csv->getline_hr($inFH)){
    $i++;
    my $ko = MMT::Koha::Issue->new();
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
  $s->{lastBorrowDates} = MMT::Cache->new({name => "Last borrow dates", file => $last_borrow_dates_file, keys => ['barcode']});
}
sub _loadTranslationTables($s) {
  $s->{locationIdTranslation} = MMT::Table::LocationId->new();
  $s->{branchcodeTranslation} = MMT::Table::Branchcodes->new();
}

return 1;