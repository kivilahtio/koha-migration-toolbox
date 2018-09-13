package MMT::TranslationTable::CallSlipStatuses;

use MMT::Pragmas;

#External modules

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::ATranslationTable;
use base qw(MMT::ATranslationTable);

#Exceptions

=head1 NAME

MMT::TranslationTable::CallSlipStatuses - voyager.call_slip.status mapping table

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/call_slip_status_type.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub isWaitingForFulfilment($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $kohaObject->{found} = undef;
  return $kohaObject->{found}; #return value is arbitrary, but logged, so might as well return something useful to log
}
sub isWaitingForPickup($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {

  MMT::Exception::Delete->throw($kohaObject->logId()." is a call slip request, and already has an attached hold_recall|hold in Voyager. Preventing hold duplication by terminating this entry.") if ($voyagerObject->{linked_hold_recall_id});
  MMT::Exception::Delete->throw($kohaObject->logId()." is a call slip request, and no longer has an attached hold_recall|hold in Voyager. Making a hold from this call slip request is no longer needed.") unless ($voyagerObject->{linked_hold_recall_id});
  #Wait a minute, this portion of code is never reached, because call slip requests waiting for pickup should actually never be migrated as holds.
  #A nice solution would be to clean up the remnants of the 'linked_hold_recall_id'-column usages, eg. $DELETE from the translation tables, but that would remove this trail of thought maybe, and make somebody else follow this rabbit hole,
  # with the presumption that call_slip requests don't create hold_recall entries.
  # Maybe refactor when the error messages start to annoy?

  $kohaObject->{found} = 'W';
  $kohaObject->{waitingdate} = $voyagerObject->{hold_recall_status_date};
  $kohaObject->{priority} = $voyagerObject->{queue_position} -1; #Koha priority 0 is top priority. In voyager 1 is top priority.

  unless ($kohaObject->{priority} == 0) {
    $log->warn($kohaObject->logId()." is waiting for pickup but hold priority 'voyager('".$voyagerObject->{queue_position}."')->koha(".$kohaObject->{priority}.")' is not 0?");
  }

  MMT::Exception::Delete->throw($kohaObject->logId()." has no item even if it is waiting for pickup?!") unless ($kohaObject->{itemnumber});

  return $kohaObject->{found};
}

sub whatDoWeDo($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  MMT::Exception::Delete->throw($kohaObject->logId()." has hr_status_desc '$originalValue'. What do we do with it?");
}
return 1;