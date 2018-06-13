use 5.22.1;

package MMT::Table::LocationId;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';

#External modules
#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::ATranslator;
use base qw(MMT::ATranslator);

#Exceptions

=head1 NAME

MMT::Table::LocationId - map voyager.location_id to Koha

=cut

my $translationTableFile = MMT::Config::translationsDir."/location_id.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub branchLoc($s, $originalValue, $branch, $loc, $error) {
  $log->warn("Cannot translate Voyager location_id '$originalValue'. Defaulting to branchcode '$branch' and location '$loc'");
  return [uc($branch), uc($loc)];
}

return 1;