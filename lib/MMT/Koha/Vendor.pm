package MMT::Koha::Vendor;

use MMT::Pragmas;

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

=head1 NAME

MMT::Koha::Vendor - Transforms a bunch of Voyager data into Koha vendors

=cut

=head2 build

 @param1 Voyager data object
 @param2 Builder

=cut

sub build($self, $o, $b) {
  $self->setKeys($o, $b, [['vendor_id' => 'id']]);
  $self->set(default_currency => 'currency', $o, $b);
  $self->set(vendor_name => 'name', $o, $b);
  $self->setAccountnumber($o, $b);
}

sub id {
  return 'v:'.($_[0]->{id} || 'NULL');
}

sub logId($s) {
  return 'Vendor: '.$s->id();
}

sub setCurrency($s, $o, $b) {
    $s->{currency} = $o->{default_currency} || undef;
}

sub setName($s, $o, $b) {
    $s->{name} = $o->{vendor_name} || undef;
}

sub setAccountnumber($s, $o, $b) {
    if ($b->{accounts}->get($o->{vendor_id})) {
        my $accountNumber = $b->{accounts}->get($o->{vendor_id})->[0]->{account_number};
        my $accountName = $b->{accounts}->get($o->{vendor_id})->[0]->{account_name};
        $s->{accountnumber} = "$accountNumber ($accountName)";
    }
}

return 1;
