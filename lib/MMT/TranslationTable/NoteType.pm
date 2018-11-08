package MMT::TranslationTable::NoteType;

use MMT::Pragmas;

#External modules

#Local modules
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

sub popUp($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  if (defined($transParams->[0]->{note})) {
    unless ($transParams->[0]->{modify_date}) {
      $log->debug($kohaObject->logId()." - Given patron_note '".$transParams->[0]->{patron_note_id}."' is missing the note's message_date|MODIFY_DATE?");
    }
    $kohaObject->_addPopUpNote($builder,
                  $transParams->[0]->{note},
                  $builder->{Branchcodes}->translate($kohaObject, $voyagerObject, $builder, '_DEFAULT_'),
                  $transParams->[0]->{modify_date}
    );
  }
  else {
    $log->warn($kohaObject->logId()." - Given patron_note '".$transParams->[0]->{patron_note_id}."' is missing the note itself?");
  }

  return 0; #return false, to prevent readding this note in the core handler.
}

sub example($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  return $tableParams->[0];
}

return 1;