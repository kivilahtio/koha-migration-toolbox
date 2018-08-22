package MMT::TranslationTable::PatronCategorycode;

use MMT::Pragmas;

#External modules

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::ATranslationTable;
use base qw(MMT::ATranslationTable);

#Exceptions

=head1 NAME

MMT::TranslationTable::PatronCategorycode - borrowers.categorycode mapping table

=head2 DESCRIPTION

Special functions to handle translation of Voyager data points to Koha borrower categorycode.

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/borrowers.categorycode.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub example($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $log->error("example invoked without a parameter in translation table '$translationTableFile'") unless $tableParams->[0];
  return $tableParams->[0];
}

sub warning($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $log->warn("No mapping for value '$originalValue'");
}

return 1;