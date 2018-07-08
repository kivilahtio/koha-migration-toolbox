use 5.22.1;

package MMT::TranslationTable::PatronStatistics;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';

#External modules
#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::ATranslationTable;
use base qw(MMT::ATranslationTable);

#Exceptions

=head1 NAME

MMT::TranslationTable::PatronStatistics - Patron stat cat mappings

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/patron_stat.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

return 1;