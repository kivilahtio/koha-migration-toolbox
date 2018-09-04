package MMT::Validator;

use MMT::Pragmas;

#External modules
use File::Basename;

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::Validator - Common package for basic validations

=head2 COMMON INTERFACE

Validators beginning with 'is':
-Share a common interface so they are usable from multiple contexts.
-Die on error
-All accept the following parameters:
 @param1 the variable to be validated and
 @param2 the name of the variable

In addition validation emits specific error messages if
 @param3 the Getopt::OO-instance
is given, in this context the validation believes it is validating command line arguments

Validators beginning with 'check':
-Simply checks and returns a boolean. Doesn't die.

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

sub checkIsAbsolutePath($value) {
  return ($value =~ /^\//);
}
sub checkIsValidFinnishPhoneNumber($value) {
  return $value =~ m/^((90[0-9]{3})?0|\+358\s?)(?!(100|20(0|2(0|[2-3])|9[8-9])|300|600|700|708|75(00[0-3]|(1|2)\d{2}|30[0-2]|32[0-2]|75[0-2]|98[0-2])))(4|50|10[1-9]|20(1|2(1|[4-9])|[3-9])|29|30[1-9]|71|73|75(00[3-9]|30[3-9]|32[3-9]|53[3-9]|83[3-9])|2|3|5|6|8|9|1[3-9])\s?(\d\s?){4,19}\d$/;
}
sub checkIsValidFinnishSSN($value) {
  return $value =~ /^\d{6}[+-A]\d{3}[A-Z0-9]$/;
}

sub probablyAYear($value) {
  return $value =~ /^(?:19|20)\d\d$/;
}

=head2 voyagerMoneyToKohaMoney

 @returns Voyager money exchanged to the current Koha valuation.
 @throws die, if Voyager money is not a valid number.

=cut

sub voyagerMoneyToKohaMoney($cashMoney) {
  die "Fiscal value '$cashMoney' is not a valid number" unless ($cashMoney =~ /^[-+]?\d+\.?\d*$/);
  return sprintf("%.2f", $cashMoney / 100); #Voyager has cents instead of the "real deal". This might be smart after all.
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

return 1;
