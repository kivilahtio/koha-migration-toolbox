package MMT::TranslationTable::ItemNoteTypes;

use MMT::Pragmas;

#External modules

#Local modules
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
sub warning($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $log->error($kohaObject->logId()." has an unknown item_note_type '$originalValue'. Note contents: '".$transParams->[0]->{item_note}."'");
}

return 1;
