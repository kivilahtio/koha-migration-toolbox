package MMT::PrettyLib2Koha::Supplier;

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

MMT::PrettyLib2Koha::Supplier - Suppliers to aqbooksellers

=cut

=head2 build

 @param1 PrettyLib data object
 @param2 Builder

=cut

sub build($self, $o, $b) {

  ## Primary table aqbooksellers

  $self->set(Id => 'id', $o, $b);
  $self->set(Name => 'name', $o, $b);
  $self->setAddress($o, $b);
  # $self->set(Id_Supplier => 'address1', $o, $b);
  #  $self->set(Id_Supplier => 'address2', $o, $b);
  #   $self->set(Id_Supplier => 'address3', $o, $b);
  #    $self->set(Id_Supplier => 'address4', $o, $b);
  $self->set(Phone => 'phone', $o, $b);
  $self->set(Fax => 'fax', $o, $b);
  # $self->set(Id_Supplier => 'booksellerfax', $o, $b);
  $self->set(Email => 'bookselleremail', $o, $b);
  $self->set(WWW => 'booksellerurl', $o, $b);
  # $self->set(Id_Supplier => 'url', $o, $b);
  $self->set(Note => 'notes', $o, $b);

  $self->setActive($o, $b);
  $self->setCurrency($o, $b);

  #$self->set(Id_Supplier => 'accountnumber', $o, $b);
  #$self->set(Id_Supplier => 'othersupplier', $o, $b);
  #$self->set(Id_Supplier => 'postal', $o, $b);
  #$self->set(Id_Supplier => 'listprice', $o, $b);
  #$self->set(Id_Supplier => 'invoiceprice', $o, $b);
  #$self->set(Id_Supplier => 'gstreg', $o, $b);
  #$self->set(Id_Supplier => 'listincgst', $o, $b);
  #$self->set(Id_Supplier => 'invoiceincgst', $o, $b);
  #$self->set(Id_Supplier => 'tax_rate', $o, $b);
  #$self->set(Id_Supplier => 'discount', $o, $b);
  #$self->set(Id_Supplier => 'deliverytime', $o, $b);


  ## Join table aqcontacts

  #$self->setId($o, $b); # Auto increment
  $self->set(Id           => 'aqcontacts_booksellerid', $o, $b);
  $self->set(Contact      => 'aqcontacts_name', $o, $b);
  #$self->set(Id_Phone     => 'aqcontacts_position', $o, $b);
  $self->set(ContactPhone => 'aqcontacts_phone', $o, $b);
  #$self->set(Id_Phone => 'altphone', $o, $b);
  $self->set(Fax          => 'aqcontacts_fax', $o, $b);
  $self->set(Email        => 'aqcontacts_email', $o, $b);
  #$self->set(Id_Phone => 'notes', $o, $b);
  $self->setOrderacquisition($o, $b);
  $self->setClaimacquisition($o, $b);
  $self->setClaimissues($o, $b);
  $self->setAcqprimary($o, $b);
  $self->setSerialsprimary($o, $b);

}

sub id {
  return ($_[0]->{id} || 'NULL');
}

sub logId($s) {
  return 'Supplier: '.$s->id();
}

sub getDeleteListId($s) {
  return 'SUPP'.($s->id() || 'UNDEF');
}

sub setId($s, $o, $b) {
  MMT::Exception::Delete->throw("No Id! Won't migrate Supplier with no Id.") unless $o->{Id};
  $s->{id} = $o->{Id};
}
sub setName($s, $o, $b) {
  $s->{name} = $o->{Name};
}
sub setAddress($s, $o, $b) {

  $s->{address1} = $o->{PostAddress};
  $s->{address2} = $o->{PostCode};
  $s->{address3} = $o->{Country};
}
sub setPhone($s, $o, $b) {
  $s->{phone} = $o->{Phone};
}
sub setFax($s, $o, $b) {
  $s->{fax} = $o->{Fax};
  $s->{booksellerfax} = $o->{Fax};
}
sub setBookselleremail($s, $o, $b) {
  $s->{bookselleremail} = $o->{Email};
}
sub setBooksellerurl($s, $o, $b) {
  $s->{booksellerurl} = $o->{WWW};
  $s->{url} = $o->{WWW};
}
sub setNotes($s, $o, $b) {
  $s->{notes} = $o->{Note};
}
sub setActive($s, $o, $b) {
  $s->{active} = 1;
}
sub setCurrency($s, $o, $b) {
  $s->{currency} = 'EUR';
}


sub setAqcontacts_booksellerid($s,$o,$b) {
  $s->{aqcontacts}->{booksellerid} = $o->{Id};
}
sub setAqcontacts_name($s,$o,$b) {
  $s->{aqcontacts}->{name} = $o->{Contact};
}
sub setAqcontacts_phone($s,$o,$b) {
  $s->{aqcontacts}->{phone} = $o->{ContactPhone};
}
sub setAqcontacts_fax($s,$o,$b) {
  $s->{aqcontacts}->{fax} = $o->{Fax};
}
sub setAqcontacts_email($s,$o,$b) {
  $s->{aqcontacts}->{email} = $o->{Email};
}
sub setOrderacquisition($s,$o,$b) {
  $s->{aqcontacts}->{orderacquisition} = 1;
}
sub setClaimacquisition($s,$o,$b) {
  $s->{aqcontacts}->{claimacquisition} = 1;
}
sub setClaimissues($s,$o,$b) {
  $s->{aqcontacts}->{claimissues} = 1;
}
sub setAcqprimary($s,$o,$b) {
  $s->{aqcontacts}->{acqprimary} = 1;
}
sub setSerialsprimary($s,$o,$b) {
  $s->{aqcontacts}->{serialsprimary} = 1;
}

return 1;
