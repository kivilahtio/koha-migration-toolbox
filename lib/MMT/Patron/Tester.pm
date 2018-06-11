use 5.22.1;

package MMT::Patron::Tester;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';

#External modules
use YAML::XS;

#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::Patron::Tester - Tests that the Transformed Voyager Patrons match what is expected to be received in Koha

=head2 DESCRIPTION

=cut

sub new {
  $log->trace("Constructor(@_)") if $log->is_trace();
  my ($class, $p) = @_;
  my $self = bless({}, $class);
  $self->_loadTestSuite();
  return $self;
}

=head2 test
Find the test suite matching the Patron's primary key (patron_id) and confirm that the transformed Patron is what is expected
 @param1 MMT::Patron
 @returns Boolean, true on success, false on failure
=cut
sub test($s, $o) {
  my $test = $s->{tests}->{$o->id()};
  return 1 unless $test;

  my @failed;
  while (my ($k, $re) = each(%$test)) {
    push(@failed, '(k):'.$k.' (v):'.$o->{$k}.' (re):'.$re) unless ($o->{$k} =~ /$re/);
  }
  if (@failed) {
    $log->warn("Tests failed for '".$o->logId()."'. @failed");
  }
  else {
    return 1;
  }
  return 0;
}

sub _loadTestSuite($s) {
  $s->{tests} = YAML::XS::LoadFile(MMT::Config::testDir().'/patrons.yaml');
}

return 1;