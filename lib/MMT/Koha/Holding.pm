package MMT::Koha::Holding;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::Builder;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::Koha::Holding - Transform holdings

=head1 Holdings transformation modules

The grunt work is done by the holdings transformation modules, meant to be implemented for each library that migrates holdings-record, if needed.

The desired holdings transformation module is configured in config/main.yml -> holdingsTransformationModule

See MMT::Koha::Holding::HAMK for example implementation

The transformation module:
- MUST set the id of this MMT::Koha::Holding-object in-place
  $holding->{id} = $holding_id;
- Receives a MARC21 Holdings Record XML reference which can be transformed using whichever MARC-implementation most performant for the transformation need.
- MUST mutate the given MARC21 Holdings XML reference with the new changes, instead of returning anything, to prevent unnecessary movement of big chunks of xml in-memory.

=cut

=head2 build

Builds the MFHD-Record using the configured transformation module

 @param1 Voyager xml record reference
 @param2 Builder

=cut

sub build($s, $xmlPtr, $b) {
  #Dispatch using the configured transformation module.
  unless ($b->{holdingsTransformationModule}) {
    my $package = 'MMT::Koha::Holding::'.MMT::Config::holdingsTransformationModule;
    MMT::Builder::__dynaload($package);
    $b->{holdingsTransformationModule} = $package->can('transform');
    die "Couldn't find the transform()-subroutine from package '$package', using configuration: holdingsTransformationModule='".MMT::Config::holdingsTransformationModule."'." unless ($b->{holdingsTransformationModule});
  }
  eval {
    $b->{holdingsTransformationModule}->($s, $xmlPtr, $b);
    $s->{r} = $$xmlPtr;
  };
  if ($@) {
    MMT::Exception::Delete->throw(error => "Building a holdings-record failed:\n$@\nTrying with the following record:\n$$xmlPtr\n");
  }

  return $s;
}

sub logId($s) {
  return "Holding '".$s->id()."'";
}

sub id($s) {
  return $s->{id};
}

sub serialize($s) {
  return $s->{r};
}

return 1;
