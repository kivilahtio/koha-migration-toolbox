package MMT::TranslationTable::ItemStatus;

use MMT::Pragmas;

#External modules

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::ATranslationTable;
use base qw(MMT::ATranslationTable);

#Exceptions

=head1 NAME

MMT::TranslationTable::ItemStatus - voyager.item_status to koha.items.* mapping table

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/item_statuses.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub warning($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $log->error($kohaObject->logId()." has an unknown item_status '$originalValue'.");
}

return 1;
