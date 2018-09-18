package MMT::Koha::Reserve;

use MMT::Pragmas;

#External modules

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::Koha::Reserve - Transforms a bunch of Voyager data into Koha reserves

=cut

=head2 build

Flesh out the Koha-borrower -object out of the given
 @param1 Voyager data object
 @param2 Builder

=cut

sub build($self, $o, $b) {
  #$self->setReserve_id                  ($o, $b); #AUTO_INCREMENT
  $self->setKeys($o, $b, [['patron_id' => 'borrowernumber'], ['bib_id' => 'biblionumber']]);

  $self->setItemnumber(                           $o, $b);
  $self->set(create_date     => 'reservedate',    $o, $b);
  $self->set(pickup_location => 'branchcode',     $o, $b);
  $self->set(queue_position  => 'priority',       $o, $b);
  $self->setStatuses                             ($o, $b);
  #  \$self->setFound
  #   \$self->setWaitingdate
  $self->set(expire_date     => 'expirationdate', $o, $b);
  $self->setLowestPriority                       ($o, $b);

  #$self->setTimestamp                   ($o, $b); #ON_UPDATE
  #$self->setPickupexpired               ($o, $b);
  #$self->setNotificationdate            ($o, $b);
  #$self->setReminderdate                ($o, $b);
  #$self->setCancellationdate            ($o, $b);
  #$self->setReservenotes                ($o, $b);
  #$self->setSuspend                     ($o, $b);
  #$self->setSuspend_until               ($o, $b);
  #$self->setItemtype                    ($o, $b);
}

sub id {
  return 'p:'.$_[0]->{borrowernumber}.
         (defined($_[0]->{itemnumber})   ? '-i:'.$_[0]->{itemnumber} : '').
         (defined($_[0]->{biblionumber}) ? '-b:'.$_[0]->{biblionumber} : '');
}

sub logId($s) {
  return 'Reserve: '.$s->id();
}

sub setItemnumber($s, $o, $b) {
  $s->sourceKeyExists($o, 'item_id');
  $s->sourceKeyExists($o, 'request_level');
  $s->{itemnumber} = $o->{item_id};
  MMT::Exception::Delete->throw($s->logId()."' has no item_id|itemnumber even if it is an Item-level hold!") if (not($s->{itemnumber}) && $o->{request_level} eq 'C');
  MMT::Exception::Delete->throw($s->logId()."' - Title-level -hold target biblio has no (suitable?) items! Should we migrate or remove them?") if (not($s->{itemnumber}));
}
sub setReservedate($s, $o, $b) {
  $s->{reservedate} = $o->{create_date};

  unless ($s->{reservedate}) {
    MMT::Exception::Delete->throw($s->logId()."' has no create_date/reservedate.");
  }
}
sub setBranchcode($s, $o, $b) {
  $s->sourceKeyExists($o, 'pickup_location');
  my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{pickup_location});
  $s->{branchcode} = $branchcodeLocation->{branch};

  unless ($s->{branchcode}) {
    MMT::Exception::Delete->throw($s->logId()."' has no place of issuance (pickup_location/branchcode). Set a default in the TranslationTable rules!");
  }
}
sub setPriority($s, $o, $b) {
  $s->{priority} = $o->{queue_position};

  unless (defined $s->{priority}) { #queue_position can be 0
    $log->warn($s->logId()."' has no queue_position|priority. Using 1000");
    $s->{priority} = 1000;
  }
}
sub setStatuses($s, $o, $b) {
  $s->sourceKeyExists($o, 'hr_status_desc');
  $s->sourceKeyExists($o, 'queue_position');
  $s->sourceKeyExists($o, 'request_level');
  $s->sourceKeyExists($o, 'hold_recall_type');
  $s->sourceKeyExists($o, 'hold_recall_status_date');
  $s->sourceKeyExists($o, 'linked_hold_or_circ');

  if ($o->{hold_recall_type} ne 'CS') {
    $b->{HoldStatuses}->translate(@_, $o->{hr_status_desc});
  }
  else {
    $b->{CallSlipStatuses}->translate(@_, $o->{hr_status_desc});
  }

  $log->warn($s->logId()." has an unknown 'hold_recall_type'='".($o->{hold_recall_type}//'undef')."'") unless ($o->{hold_recall_type} && ($o->{hold_recall_type} eq 'H' || $o->{hold_recall_type} eq 'R' || $o->{hold_recall_type} eq 'CS'));
}
sub setExpirationdate($s, $o, $b) {
  $s->{expirationdate} = $o->{expire_date};

  if ($o->{hold_recall_type} ne 'CS' && not($s->{expirationdate})) {
    $log->warn($s->logId()."' is not a call slip request and has no expire_date/expirationdate?");
  }
  $s->{expirationdate} = undef unless ($s->{expirationdate}); #Make sure this is undef and not just falsy.
}
sub setLowestPriority($s, $o, $b) {
  $s->{lowestPriority} = 0;
}

return 1;