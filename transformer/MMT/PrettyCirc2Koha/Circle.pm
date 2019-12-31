package MMT::PrettyCirc2Koha::Circle;

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

=head1 NAME

MMT::PrettyCirc2Koha::CircleList

=cut

=head2 build

 @param1 PrettyCirc data object
 @param2 Builder

=cut

=head2 Koha target schema

[koha]> DESC subscriptionroutinglist;
+----------------+---------+------+-----+---------+----------------+
| Field          | Type    | Null | Key | Default | Extra          |
+----------------+---------+------+-----+---------+----------------+
| routingid      | int(11) | NO   | PRI | NULL    | auto_increment |
| borrowernumber | int(11) | NO   | MUL | NULL    |                |
| ranking        | int(11) | YES  |     | NULL    |                |
| subscriptionid | int(11) | NO   | MUL | NULL    |                |
+----------------+---------+------+-----+---------+----------------+

=cut

sub build($self, $o, $b) {
  #$self->routingId              ($0, $b);  # auto_increment
  $self->setBorrowernumber       ($o, $b);
  $self->setSubscriptionid       ($o, $b);
  $self->setRanking              ($o, $b);
}

sub id {
  return 'S:'.($_[0]->{subscriptionid} || 'NULL').'-b:'.($_[0]->{borrowernumber} || 'NULL').'-r:'.($_[0]->{ranking} || 'NULL');
}

sub logId($s) {
  return 'Circle: '.$s->id();
}

sub setBorrowernumber($s, $o, $b) {
  $s->{borrowernumber} = $o->{Id_Customer};
}

sub setRanking($s, $o, $b) {
  $s->{ranking} = $o->{Row};
}

sub setSubscriptionid($s, $o, $b) {
  $s->{subscriptionid} = $o->{Id_Item};
}

return 1;

