package MMT::Koha::Holding;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::Builder;
use MMT::MARC::Record;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::Koha::Holding - Transform holdings

=cut

=head2 build

 @param1 Voyager xml record
 @param2 Builder

=cut

sub build($s, $xmlPtr, $b) {
  $s->{r} = MMT::MARC::Record->newFromXml($xmlPtr);
  $s->{id} = $s->{r}->docId();

  #Dispatch using the configured transformation module.
  unless ($b->{holdingsTransformationModule}) {
    my $package = 'MMT::Koha::Holding::'.MMT::Config::holdingsTransformationModule;
    MMT::Builder::__dynaload($package);
    $b->{holdingsTransformationModule} = $package->can('transform');
    die "Couldn't find the transform()-subroutine from package '$package', using configuration: holdingsTransformationModule='".MMT::Config::holdingsTransformationModule."'." unless ($b->{holdingsTransformationModule});
  }
  $b->{holdingsTransformationModule}->($s, $s->{r}, $b);

  return $s;
}

sub logId($s) {
  return "Holding '".$s->id()."'";
}

sub id($s) {
  return $s->{id};
}

sub serialize($s) {
  my $r = $s->{r};
  return $r->serialize();
}

return 1;
