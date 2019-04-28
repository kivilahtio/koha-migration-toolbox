package MMT::Voyager2Koha::Branchtransfer;

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

MMT::Voyager2Koha::Branchtransfer - Transforms a bunch of Voyager data into Koha branchtransfers

=cut

=head2 build

Flesh out the Koha-branchtransfer -object out of the given
 @param1 Voyager data object
 @param2 Builder

=cut

sub build($self, $o, $b) {
  #$self->branchtransfer_id($o, $b); #AUTO_INCREMENT
  $self->setKeys($o, $b, [['item_id' => 'itemnumber']]);

  $self->setDatesent       ($o, $b);
  $self->setTobranch       ($o, $b);
  $self->setFrombranch     ($o, $b);
  #$self->setDatearrived
  #$self->setComments       ($o, $b);
}

sub id {
  return 'item:'.$_[0]->{itemnumber};
}

sub logId($s) {
  return 'Branchtransfer: '.$s->id();
}

sub setDatesent($s, $o, $b) {
  $s->sourceKeyExists($o, 'item_status_date'); $s->sourceKeyExists($o, 'discharge_date');

  unless ($o->{item_status_date}) {
    MMT::Exception::Delete->throw($s->logId()."' has no item_status_date/datesent.");
  }
  $s->{datesent} = $o->{item_status_date}; #The transfer was initiated when the status was set

  if (not($o->{call_slip_id}) && substr($o->{item_status_date}, 0, 12) ne substr($o->{discharge_date}, 0, 12)) {
    my $warning = "The date of checkin '".(defined($o->{discharge_date}) ? $o->{discharge_date} : 'undef')."' is different from the date '".$o->{item_status_date}."' when the transfer was initiated. Why?";
    $log->warn($s->logId().' '.$warning);
    $s->concatenate($warning => 'comments');
  }
}
sub setTobranch($s, $o, $b) {
  $s->sourceKeyExists($o, 'to_location');
  unless ($o->{to_location}) {
    MMT::Exception::Delete->throw($s->logId()."' has no to_location/tobranch!");
  }

  my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{to_location});
  $s->{tobranch} = $branchcodeLocation->{branch};

  unless ($s->{tobranch}) {
    MMT::Exception::Delete->throw($s->logId()."' has no to_location/tobranch. Set a default in the location_id.yaml -TranslationTable rules!");
  }
}
sub setFrombranch($s, $o, $b) {
  $s->sourceKeyExists($o, 'discharge_location');
  unless ($o->{discharge_location}) {
    my $error = "No discharge_location/frombranch! Using perm_location/homebranch.";
    $log->error($s->logId()." has $error");
    $s->concatenate($error => 'comments');
    $s->{frombranch} = $s->{tobranch};
    return;
  }

  my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{discharge_location});
  $s->{frombranch} = $branchcodeLocation->{branch};

  unless ($s->{frombranch}) {
    MMT::Exception::Delete->throw($s->logId()."' has no discharge_location/frombranch. Set a default in the location_id.yaml -TranslationTable rules!");
  }
}

return 1;