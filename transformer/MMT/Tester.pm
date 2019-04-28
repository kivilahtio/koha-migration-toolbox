package MMT::Tester;

use MMT::Pragmas;

#External modules
use YAML::XS;

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::Tester - Tests that the Transformed Voyager objects match what is expected to be received in Koha

=head2 DESCRIPTION

Instantiate with a .yaml-file of Koha Object tests from the tests/-directory and send MMT::KohaObject-instances to this Tester-module.

=cut

=head2 new

 @param1 file, test suite file path to the test suite to load, eg. tests/patrons.yaml

=cut

sub new($class, $testSuiteFile) {
  $log->trace("Constructor(@_)") if $log->is_trace();
  my $self = bless({}, $class);
  $self->_loadTestSuite($testSuiteFile);
  return $self;
}

=head2 test

Find the test suite matching the Issue's primary key (cardnumber-barcode) and confirm that the transformed ISsue is what is expected
 @param1 MMT::Voyager2Koha::Issue
 @returns Boolean, true on success, false on failure

=cut

sub test($s, $o) {
  my $test = $s->{tests}->{$o->id()};
  return 1 unless $test;

  my @failed;
  while (my ($k, $re) = each(%$test)) {
    unless (exists $o->{$k}) {
      push(@failed, '(k):'.$k.' is missing');
      next;
    }
    if ($re =~ /undef|null/i) {
      push(@failed, '(k):'.$k.' (v):'.$o->{$k}.' (re):'.$re) if (defined($o->{$k}));
    }
    push(@failed, '(k):'.$k.' (v):'.$o->{$k}.' (re):'.$re) unless ($o->{$k} =~ /$re/);
  }
  if (@failed) {
    $log->warn("Tests failed for '".$o->logId()."' :\n".join("\n", @failed));
  }
  else {
    return 1;
  }
  return 0; #Failing by default, if not explicitly succeeding, is more safe.
}

sub _loadTestSuite($s, $testSuiteFile) {
  $s->{tests} = YAML::XS::LoadFile($testSuiteFile);
}

return 1;