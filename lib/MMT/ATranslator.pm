use 5.22.1;

package MMT::ATranslator;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';

#External modules
use YAML::XS;

#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);
use MMT::Validator;

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::ATranslator - Abstract class, translates object attributes (source data column values) into Koha specific versions.

=head2 DESCRIPTION

Used to translate configurable parameters, such as item types or branchcodes or borrower categorycodes, etc.

=cut

=head2 new
 @param1 HASHRef of constructor params: {
  file => 'translations/borrowers.categorycode.yaml' #file containing the translation rules
 }
=cut
sub new {
  $log->trace("Constructor(@_)") if $log->is_trace();
  $log->logdie(__PACKAGE__." is an abstract class") if ($_[0] eq __PACKAGE__);
  my ($class, $p) = _validate(@_);
  my $self = bless({}, $class);
  $self->{_params} = $p;
  $self->_loadMappings();
  return $self;
}
sub _validate($class, $p) {
  my $var; #Simply reduce duplication at a cost of slight awkwardness
  $var = 'file';      MMT::Validator::isFileReadable($p->{$var}, $var, undef);
  return @_;
}

=head2 _loadMappings
Load the translation instructions from the configuration file
=cut
sub _loadMappings($s) {
  $s->{_mappings} = YAML::XS::LoadFile($s->{_params}->{file});
  $log->trace(ref($s)." loaded mappings:".MMT::Validator::dumpObject($s->{_mappings}));
}

=head2 translate
 @param1 value to translate
 @returns the translated value
 @dies $DELETE if the Object in processing should be removed from migration
=cut
my $re_isSubroutineCall = qr{^(.+)\((.*)\)$};
sub translate($s, $val) {
  my $kohaVal = $s->{_mappings}->{$val};
  #Check if using the fallback catch-all -value
  if (not(defined($kohaVal))) {
    $kohaVal = $s->{_mappings}->{'_DEFAULT_'};
  }
  if (not(defined($kohaVal))) {
    $log->error(ref($s)." is trying to translate value '$val', but no translation rule exists");
    return undef;
  }

  if ($kohaVal eq '$DELETE') {
    MMT::Exception::Delete->throw("Marked for deletion in '".$s->{file}."'");
  }
  elsif ($kohaVal =~ $re_isSubroutineCall) {
    my $method = $1;
    my @params = ($val, split(/ ?, ?/, $2));
    $log->trace("Invoking ".ref($s)."->$method(@params)") if $log->is_trace();
    my $rv = $s->$1(@params);
    $log->trace("Returning ".ref($s)."->$method(@params) with '$rv'") if $log->is_trace();
  }
  else {
    $log->trace("Returning ".ref($s)." value '$val' translated to '$kohaVal'") if $log->is_trace();
  }
  return $kohaVal;
}

return 1;