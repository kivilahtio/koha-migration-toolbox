package MMT::TranslationTable::FineTypes;

use MMT::Pragmas;

#External modules

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::ATranslationTable;
use base qw(MMT::ATranslationTable);

#Exceptions

=head1 NAME

MMT::TranslationTable::FineTypes - voyager.fine_fee.fine_fee_type to koha.accountlines.accounttype mapping table

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/fine_fee_type.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub example($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  return $tableParams->[0];
}

return 1;