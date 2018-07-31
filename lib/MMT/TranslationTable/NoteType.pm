use 5.22.1;

package MMT::TranslationTable::NoteType;
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

MMT::TranslationTable::NoteType - map note types integers to plain text

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/note_type.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub example($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  return $tableParams->[0];
}

return 1;