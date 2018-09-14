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
sub isPickableOrInTransit($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {

  MMT::Exception::Delete->throw($kohaObject->logId()." is a call slip request, and already has an attached hold_recall|hold in Voyager. Preventing hold duplication by terminating this entry.")
    if (_hasHold($kohaObject, $voyagerObject));
  MMT::Exception::Delete->throw($kohaObject->logId()." is a call slip request, and is already checked out. Making a hold from this call slip request is no longer needed.")
    if (not(_hasHold($kohaObject, $voyagerObject)) && _hasCirc($kohaObject, $voyagerObject));

  #Now what is left are call_slip requests that are being transported to the pickup location
  MMT::TranslationTable::HoldStatuses::isInTransitForPickup(@_);

  #These call slip transfers are dealt with in the Transfers extraction-phase. Not mixing different asset pipelines.
}

sub whatDoWeDo($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  MMT::Exception::Delete->throw($kohaObject->logId()." has hr_status_desc '$originalValue'. What do we do with it?");
}

sub _hasHold($kohaObject, $voyagerObject) {
  $kohaObject->sourceKeyExists($voyagerObject, 'linked_hold_or_circ');
  if ($voyagerObject->{linked_hold_or_circ} && $voyagerObject->{linked_hold_or_circ} =~ /^H\w*\W+(\d+)/i) {
    my $hold_recall_id = $1;
    return $hold_recall_id;
  }
  return undef;
}

sub _hasCirc($kohaObject, $voyagerObject) {
  $kohaObject->sourceKeyExists($voyagerObject, 'linked_hold_or_circ');
  if ($voyagerObject->{linked_hold_or_circ} && $voyagerObject->{linked_hold_or_circ} =~ /^C\w*\W+(\d+)/i) {
    my $circ_transaction_id = $1;
    return $circ_transaction_id;
  }
  return undef;
}

return 1;