use 5.22.1;

package MMT::TranslationTable::ItemStatistics;
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

MMT::TranslationTable::ItemStatistics - map Voyager.item_stats.item_stat_id types to koha.items.?

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/item_stat_code.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub warning($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $log->error($kohaObject->logId()." has an unknown item_stat_id '$originalValue'.");
}

return 1;