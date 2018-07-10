use Modern::Perl '2016';

package MMT::TranslationTable::FineTypes;
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

MMT::TranslationTable::FineTypes - voyager.fine_fee.fine_fee_type to koha.accountlines.accounttype mapping table

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/fine_fee_type.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub example($s, $kohaObject, $voyagerObject, $builder, $originalValue, @tableParams) {
  return $tableParams[0];
}

return 1;