use 5.22.1;

package MMT::TranslationTable::ItemNoteTypes;
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

MMT::TranslationTable::ItemNoteTypes - map voyager.item_note_type to Koha

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/item_note_type.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub toItemnotes($s, $kohaObject, $voyagerObject, $builder, $originalValue, @tableParams) {
  $kohaObject->{itemnotes} = $voyagerObject->{item_note};
}
sub toItemnotes_nonpublic($s, $kohaObject, $voyagerObject, $builder, $originalValue, @tableParams) {
  $kohaObject->{itemnotes_nonpublic} = $voyagerObject->{item_note};
}

return 1;
