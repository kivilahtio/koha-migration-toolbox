package MMT::TranslationTable::HoldStatuses;

use MMT::Pragmas;

#External modules

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::ATranslationTable;
use base qw(MMT::ATranslationTable);

#Exceptions

=head1 NAME

MMT::TranslationTable::HoldStatuses - voyager.hold_recall.hold_recall_status to koha.reserves.found et. al. mapping table

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/hold_recall_statuses.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub isWaitingForFulfilment($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $kohaObject->{found} = undef;
  $kohaObject->{itemnumber} = undef if ($voyagerObject->{request_level} eq 'T'); #Title-level holds which are not caught, shouldn't have a specific item attached to it.
  return $kohaObject->{found}; #return value is arbitrary, but logged, so might as well return something useful to log
}
sub isWaitingForPickup($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $kohaObject->{found} = 'W';
  $kohaObject->{waitingdate} = $voyagerObject->{hold_recall_status_date};
  $kohaObject->{priority} = $voyagerObject->{queue_position} -1; #Koha priority 0 is top priority. In voyager 1 is top priority.

  unless ($kohaObject->{priority} == 0) {
    $log->warn($kohaObject->logId()." is waiting for pickup but hold priority 'voyager('".$voyagerObject->{queue_position}."')->koha(".$kohaObject->{priority}.")' is not 0?");
  }

  MMT::Exception::Delete->throw($kohaObject->logId()." has no item even if it is waiting for pickup?!") unless ($kohaObject->{itemnumber});

  return $kohaObject->{found};
}
sub isInTransitForPickup($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $kohaObject->{found} = 'T';

  MMT::Exception::Delete->throw($kohaObject->logId()." has no item even if it is in transit for pickup?!") unless ($kohaObject->{itemnumber});

  return $kohaObject->{found};
}
sub warning($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $log->error($kohaObject->logId()." has an unknown hr_status_desc '$originalValue'.");
}
return 1;