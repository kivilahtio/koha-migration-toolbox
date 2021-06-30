package MMT::PrettyLib2Koha::Transact;

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

MMT::PrettyLib2Koha::Transact - Transforms PrettyLib Transact to Koha Statistics

=cut

=head2 build

Flesh out the Koha-borrower -object out of the given
 @param1 Voyager data object
 @param2 Builder

=cut

sub build($self, $o, $b) {
  $self->set(Id_Item     => 'itemnumber',     $o, $b);
  $self->set(Id_Customer => 'borrowernumber', $o, $b);
  $self->set(TransDate   => 'datetime',       $o, $b);
  $self->set(Id_Library  => 'branch',         $o, $b);
  $self->setType                             ($o, $b);
  # Migrate history with missing item or borrower, we still generate annual circulation and itemtype/borrower-category statistics.
  #$self->setItemtype                         ($o, $b);
  #$self->setUsercode                         ($o, $b);
}

sub id {
  return 'b:'.($_[0]->{borrowernumber} // 'NULL').'-i:'.($_[0]->{itemnumber} // 'NULL');
}

sub logId($s) {
  return 'Transact: '.$s->id();
}

sub getDeleteListId($s) {
  return 'STAT'.($s->id() || 'UNDEF');
}

sub setItemnumber($s, $o, $b) {
  $s->{itemnumber} = $o->{Id_Item} if $o->{Id_Item};
  MMT::Exception::Delete->throw($s->logId()."' has no itemnumber! Won't migrate loan history of nothing.")
    unless($s->{itemnumber});
}
sub setBorrowernumber($s, $o, $b) {
  $s->{borrowernumber} = $o->{Id_Customer} if $o->{Id_Customer};
  MMT::Exception::Delete->throw($s->logId()."' has no borrowernumber! Won't migrate loan history for nothing.")
    unless($s->{borrowernumber});
}
sub setDatetime($s, $o, $b) {
  $s->{datetime} = $o->{TransDate};
  unless ($s->{datetime}) {
    MMT::Exception::Delete->throw($s->logId()."' has no datetime.");
  }

  $s->{datetime} = MMT::Validator::parseDate($s->{datetime});
}
sub setBranch($s, $o, $b) {
  $s->{branch} = $b->{Branchcodes}->translate(@_, $o->{Id_Library});
  unless ($s->{branch}) {
    MMT::Exception::Delete->throw($s->logId()."' has no place of issuance (Id_Library/branch). Set a default in the TranslationTable rules!");
  }
}
sub setItemtype($s, $o, $b) {
  my $items = $b->{Items}->get($o->{Id_Item});
  unless ($items && $items->[0]) {
    MMT::Exception::Delete->throw($s->logId()."' has no actual Items?");
  }
  # Fetch the Itemtype from Koha, that is much much easier.
}
sub setUsercode($s, $o, $b) {
  my $items = $b->{Customers}->get($o->{Id_Customer});
  unless ($items && $items->[0]) {
    MMT::Exception::Delete->throw($s->logId()."' has no actual Customer?");
  }
  # Fetch the borrower categorycode from Koha, that is much much easier.
}
sub setType($s, $o, $b) {
  my $tt = $o->{TransType};

  if    ($tt == 1) { $s->{type} = 'issue' }
  elsif ($tt == 2) { $s->{type} = 'renew' }
  elsif ($tt == 4) { $s->{type} = 'return' }
  else {
    $log->warn($s->logId()." - Unknown 'TransType' '$tt'.");
    MMT::Exception::Delete::Silently->throw(error => "Unknown 'TransType' '$tt'");
  }
}

return 1;

