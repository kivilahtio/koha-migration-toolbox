package MMT::PrettyLib2Koha::Reserve;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::Validator;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;
use MMT::Exception::Delete::Silently;

=head1 NAME

MMT::PrettyLib2Koha::Reserve - Transforms PrettyLib Reservations to Koha Reserves

=cut

=head2 build

Flesh out the Koha-borrower -object out of the given
 @param1 Voyager data object
 @param2 Builder

=cut

sub build($self, $o, $b) {
  #$self->setReserve_id    ($o, $b); #AUTO_INCREMENT
  $self->setKeys($o, $b, [['Id_Customer' => 'borrowernumber'],['Id_Title' => 'biblionumber']]);
  $self->setItem                             ($o, $b);
  $self->setReserveDate                      ($o, $b);
  $self->setBranchcode                       ($o, $b);
  $self->setExpirationDate                   ($o, $b);
  $self->setPriority                         ($o, $b);
  $self->setLowestPriority                   ($o, $b);
}

sub id {
  return 'p:'.($_[0]->{borrowernumber} // 'NULL').'-b:'.($_[0]->{biblionumber} // 'NULL').'-i:'.($_[0]->{itemnumber} // 'NULL');
}

sub logId($s) {
  return 'Reserve: '.$s->id();
}

sub getDeleteListId($s) {
  return 'HOLD'.($s->id() || 'UNDEF');
}

sub setBiblionumber($s, $o, $b) {
  $s->{biblionumber} = $o->{Id_Title} if $o->{Id_Title};
}
sub setReserveDate($s, $o, $b) {
  $s->{reservedate} = $o->{ReservDate};

  unless ($s->{reservedate}) {
    MMT::Exception::Delete->throw($s->logId()."' has no ReservDate/reservedate.");
  }

  $s->{reservedate} = MMT::Validator::parseDate($s->{reservedate});
}
sub setBranchcode($s, $o, $b) {
  $s->{branchcode} = $b->{Branchcodes}->translate(@_, $o->{Id_Library});
}
sub setItem($s, $o, $b) {
  $s->{itemnumber} = $o->{Id_Item} if $o->{Id_Item};
}
sub setExpirationDate($s, $o, $b) {
  $s->{expirationdate} = $o->{DueDate};

  unless ($s->{expirationdate}) {
    MMT::Exception::Delete->throw($s->logId()."' has no DueDate/expirationdate.");
  }

  $s->{expirationdate} = MMT::Validator::parseDate($s->{expirationdate});
}
sub setPriority($s, $o, $b) {
  # Queue (position) aka hold priority:
  # Queue > 0 means position in queue
  # Queue == 0 means hold waiting
  # Queue == -1 means hold has been expired

  if ($o->{Queue} > 0) {
    $s->{priority} = $o->{Queue};
  }
  elsif ($o->{Queue} == 0) {
    $s->{found} = 'W'; # set hold waiting for pickup
  }
  elsif ($o->{Queue} < 0) {
    # hold has been expired, let it be automatically cancelled by Koha
    MMT::Exception::Delete::Silently->throw($s->logId()."' expired already.");
  }
  else {
    MMT::Exception::Delete->throw($s->logId()."' no queue position.");
  }
}
sub setLowestPriority($s, $o, $b) {
  $s->{lowestPriority} = 0; # default
}

return 1;
