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

$transParams->[0] has the matching Voyager.ITEM_NOTE -row

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/item_note_type.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub toItemnotes($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $kohaObject->{itemnotes} = $transParams->[0]->{item_note};
}
sub toItemnotes_nonpublic($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $kohaObject->{itemnotes_nonpublic} = $transParams->[0]->{item_note};
}

return 1;
