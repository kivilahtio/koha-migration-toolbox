package MMT::TranslationTable::BibLinkTypes;

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

my $translationTableFile = MMT::Config::translationTablesDir."/biblio_link_types.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub warning($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $log->fatal($kohaObject->logId()." has an unknown biblio link type '$originalValue'. You must update the contents of your translation table '$translationTableFile' to match Voyager configurations or fix the biblio.");
}

return 1;
