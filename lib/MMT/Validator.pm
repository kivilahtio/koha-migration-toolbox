use 5.22.1;

package MMT::Validator;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';

#External modules
use Data::Dumper;
use File::Basename;

#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::Validator - Common package for basic validations

=head2 COMMON INTERFACE

All validators beginning with 'is' share a common interface so they are usable from multiple contexts.
All accept the following parameters:
 @param1 the variable to be validated and
 @param2 the name of the variable

In addition validation emits specific error messages if
 @param3 the Getopt::OO-instance
is given, in this context the validation believes it is validating command line arguments

=cut

sub isArray($array, $variable, $opts) {
  if (!ref $array eq 'ARRAY') {
    _parameterValidationFailed("Variable '$array' is not an ARRAY", $variable, $opts);
  }
  if (!scalar(@$array)) {
    _parameterValidationFailed("Variable '$array' is an empty ARRAY", $variable, $opts);
  }
}

=head2 isReadableFile
 @param1 $filePath
 @param2 $variable, the name of the variable that failed validation
 @param3 $opts, OPTIONAL the Getopt::OO-object managing cli parameter parsing
=cut
sub isFileReadable($filepath, $variable, $opts) {
  isFileExists(@_);
  if (!-r $filepath) {
    _parameterValidationFailed("File '$filepath' is not readable by the current user '"._getEffectiveUsername()."'", $variable, $opts);
  }
}
sub isFileExists($filepath, $variable, $opts) {
  if (!-e $filepath) {
    _parameterValidationFailed("File '$filepath' does not exist (or is not visible) for the current user '"._getEffectiveUsername()."'", $variable, $opts);
  }
}
sub isString($value, $variable, $opts) {
  if (!defined($value)) {
    _parameterValidationFailed("Value is not defined", $variable, $opts);
  }
}

sub delimiterAllowed($delim, $fileToDelimit) {
  my $suffix = filetype($fileToDelimit);
  if ($suffix eq 'csv') {
    given ($delim) {
      when (",") {} #ok
      when ("\t") {} #ok
      when ("|") {} #ok
      default {
        die "Unsupported delimiter '$delim' for filetype '$suffix' regarding file '$fileToDelimit'";
      }
    }
  }
  else {
    die "Unknown suffix '$suffix' for file '$fileToDelimit'";
  }
}

$Data::Dumper::Indent = 0;
$Data::Dumper::Terse = 1;
$Data::Dumper::Maxdepth = 2;
$Data::Dumper::Sortkeys = 1;
sub dumpObject($o) {
  return Data::Dumper::Dumper($o);
}

=head2 filetype
 @returns String, filetype, eg. .csv of the given file
 @die if filetype is unsupported.
=cut
sub filetype($file) {
  $file =~ /(?<=\.)(.+?)$/;
  given ($1) {
    when ("csv") {} #ok
    default {
      die "Unsupported filetype '$1' regarding file '$file'";
    }
  }
  return $1;
}

sub _parameterValidationFailed($message, $variable, $opts) {
  if ($opts) {
    #CLI params validation context
    print $opts->Help();
    die "Parameter '$variable' failed validation: $message";
  }
  else {
    die "Variable '$variable' failed validation: $message";
  }
}

sub _getEffectiveUsername {
  return $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
}