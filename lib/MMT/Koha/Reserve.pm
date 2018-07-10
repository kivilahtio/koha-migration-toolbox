use 5.22.1;

package MMT::Koha::Reserve;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';
use English;

#External modules

#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);
use MMT::Date;
use MMT::Validator;

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
  $self->setBorrowernumber               ($o, $b);
  $self->setBiblionumber                 ($o, $b);
  $self->setItemnumber                   ($o, $b);
  $self->setReservedate                  ($o, $b);
  $self->setBranchcode                   ($o, $b);
  #$self->setNotificationdate            ($o, $b);
  #$self->setReminderdate                ($o, $b);
  #$self->setCancellationdate            ($o, $b);
  #$self->setReservenotes                ($o, $b);
  $self->setPriority                     ($o, $b);
  $self->setStatuses                     ($o, $b);
  #  \$self->setFound                     ($o, $b);
  #   \$self->setWaitingdate               ($o, $b);
  #$self->setTimestamp                   ($o, $b); #ON_UPDATE
  $self->setExpirationdate               ($o, $b);
  #$self->setPickupexpired               ($o, $b);
  $self->setLowestPriority               ($o, $b);
  #$self->setSuspend                     ($o, $b);
  #$self->setSuspend_until               ($o, $b);
  #$self->setItemtype                    ($o, $b);
}

sub id {
  return 'p:'.$_[0]->{borrowernumber}.'-i:'.$_[0]->{itemnumber};
}

sub logId($s) {
  return 'Reserve: '.$s->id();
}

sub setBorrowernumber($s, $o, $b) {
  unless ($o->{patron_id}) {
    MMT::Exception::Delete->throw("Reserve is missing patron_id ".MMT::Validator::dumpObject($o));
  }
  $s->{borrowernumber} = $o->{patron_id};
}
sub setBiblionumber($s, $o, $b) {
  unless ($o->{bib_id}) {
    MMT::Exception::Delete->throw("Reserve is missing bib_id ".MMT::Validator::dumpObject($o));
  }
  $s->{biblionumber} = $o->{bib_id};
}
sub setItemnumber($s, $o, $b) {
  unless ($o->{item_id}) {
    MMT::Exception::Delete->throw("Reserve is missing item_id ".MMT::Validator::dumpObject($o));
  }
  $s->{itemnumber} = $o->{item_id};
}
sub setReservedate($s, $o, $b) {
  $s->{reservedate} = MMT::Date::translateDateDDMMMYY($o->{create_date}, $s, 'create_date->reservedate');

  unless ($s->{reservedate}) {
    MMT::Exception::Delete->throw($s->logId()."' has no create_date/reservedate.");
  }
}
sub setBranchcode($s, $o, $b) {
  $s->sourceKeyExists($o, 'pickup_location');
  my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{pickup_location});
  $s->{branchcode} = $branchcodeLocation->[0];

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
  $s->sourceKeyExists($o, 'queue_position');
  $s->sourceKeyExists($o, 'hold_recall_status_date');
  $b->{HoldStatuses}->translate(@_, $o->{queue_position});
}
sub setExpirationdate($s, $o, $b) {
  $s->{expirationdate} = MMT::Date::translateDateDDMMMYY($o->{expire_date}, $s, 'expire_date->expirationdate');

  unless ($s->{expirationdate}) {
    $log->warn($s->logId()."' has no expire_date/expirationdate.");
  }
}
sub setLowestPriority($s, $o, $b) {
  $s->{lowestPriority} = 0;
}

return 1;