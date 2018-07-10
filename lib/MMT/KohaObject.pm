use 5.22.1;

package MMT::KohaObject;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';
use English;

#External modules
use YAML::XS;

#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::KohaObject - Base class for importable Koha data objects

=cut

=head2 new

Create the bare reference. Reference is needed to be returned to the builder, so we can do better post-mortem analysis for each die'd Patron.
build() later.

=cut

sub new {
  my ($class) = @_;
  my $self = bless({}, $class);
  return $self;
}

=head2 createTemporaryBarcode

Used when the Koha object doesn't have a barcode/cardnumber
 @returns String

=cut

sub createTemporaryBarcode($s) {
  return 'TEMP'.$s->id();
}

=head2 id

 @returns String, a unique id for the given object type

=cut

sub id($s) {
  $log->logdie("Method 'id' must be overloaded from the extending subclass '".ref($s)."'!");
}

=head2 logId

 @returns String, unique descriptor of this Koha Object suitable for logging.

=cut

sub logId($s) {
  $log->logdie("Method 'logId' must be overloaded from the extending subclass '".ref($s)."'!");
}

=head2 serialize

Serializes the Koha Object to a Perl-data structure, ready for digestion by the Koha's bulk*Import.pl-tools
 @returns String

=cut

$Data::Dumper::Indent = 0;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Useqq = 1;
$Data::Dumper::Purity = 1;
sub serialize($s) {
  my $dump = Data::Dumper::Dumper($s);
  $dump =~ s/\n/\\n/g;
  return $dump;
}

=head2 toYaml

Serializes this object as a YAML list element
 @returns String pointer, to the YAML text.

=cut

sub toYaml {
  my $yaml = YAML::XS::Dump([$_[0]]);
  $yaml =~ s/^---.*$//gm;
  return \$yaml;
}

=head2 sourceKeyExists

Checks if the source data is valid and has they key expected.
This is used to validate that extract scripts' SQL-column definitions match what is expected here.
Logs a warning if key doesn't exists

 @param1 Data source .csv-row
 @param2 expected column name
 @returns Boolean, true if exists

=cut

sub sourceKeyExists($s, $o, $key) {
  unless (exists $o->{$key}) {
    $log->warn($s->logId()." has no '$key'-key in the extracted data row. Have the extract scripts changed?");
    return 0;
  }
  return 1;
}

return 1;