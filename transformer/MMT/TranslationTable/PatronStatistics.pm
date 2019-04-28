package MMT::TranslationTable::PatronStatistics;

use MMT::Pragmas;

#External modules

#Local modules
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