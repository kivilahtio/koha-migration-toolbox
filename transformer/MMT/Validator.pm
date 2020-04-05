package MMT::Validator;

use MMT::Pragmas;

#External modules
use File::Basename;
use Data::Printer colored => 1;
use DateTime;

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

use MMT::Exception::SSN;

our $regex_FinnishSSN     = qr/(\d\d)(\d\d)(\d\d)([+-A])(\d{3})([A-Z0-9])/;
our $regex_FinnishSSNBulk = qr/\d\d\d\d\d\d[+-A]\d{3}[A-Z0-9]/;

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

=head2 checkIsValidFinnishSSN

 @param {String} SSN
 @returns {Boolean} True, if validates ok
 @throws MMT::Exception::SSN if validation failed.

=cut

sub checkIsValidFinnishSSN($value) {
  MMT::Exception::SSN->throw(error => "Given ssn '$value' is not well formed") unless ($value =~ /^$regex_FinnishSSN$/);
  MMT::Exception::SSN->throw(error => "Given ssn '$value' has a bad day-component") unless (1 <= $1 && $1 <= 31);
  MMT::Exception::SSN->throw(error => "Given ssn '$value' has a bad month-component") unless (1 <= $2 && $2 <= 12); # This is not DateTime but this is fast and good enough.
  MMT::Exception::SSN->throw(error => "Given ssn '$value' has a bad year-component") unless (0 <= $3 && $3 <= 99);
  my $expectedChecksum = _getSsnChecksum($1, $2, $3, $5);
  MMT::Exception::SSN->throw(error => "Given ssn '$value' has a bad checksum-component. Expected '$expectedChecksum'") unless $6 eq $expectedChecksum;
  return 1;
}

=head2 filterSSNs

 @param {String} some text
 @returns {(String, ARRAY of String)} (the same text without SSNs, the SSNs if found)

=cut

sub filterSSNs($kohaObject, $text) {
  my @ssns;
  (my $newText = $text) =~ s/($regex_FinnishSSNBulk)/push(@ssns, $1); 'SSN-FILTERED';/gsme;
  $log->debug($kohaObject->logId()." - Filtered '".scalar(@ssns)."' ssns [@ssns]. New text '$newText'") if (@ssns);
  return ($newText, \@ssns);
}

sub probablyAYear($value) {
  return $value =~ /^(?:19|20)\d\d$/;
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

sub dumpObject($o) {
  return Data::Printer::np($o);
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

=head2 parseDate

 @param1 {String}, a Date in some format
 @returns {String}, the date as ISO8601

=cut

sub parseDate($dateStr) {
  my @dc;
  if ($dateStr =~ /^\s*
                      (\d{4})-(\d{2})-(\d{2}) #ISO-8601 Date
                      (?:
                        [T ]
                        (\d{1,2}):(\d{1,2}):(\d{1,2}) #HMS
                      )?$
                      /x) {
    @dc = ($1,$2,$3,$4,$5,$6)
  }
  elsif ($dateStr =~ /^\s*
                      (\d{1,2})\.(\d{1,2})\.(\d{4}) #DMY
                      (?:
                        [T ]
                        (\d{1,2}):(\d{1,2}):(\d{1,2}) #HMS
                      )?$
                      /x) {
    @dc = ($3,
           (length($2) == 1 ? "0$2" : "$2"),
           (length($1) == 1 ? "0$1" : "$1"),
           (length($4) == 1 ? "0$4" : "$4"),
           (length($5) == 1 ? "0$5" : "$5"),
           (length($6) == 1 ? "0$6" : "$6"));
  }
  else {
    $log->error("Unknown date format '$dateStr'!");
    return $dateStr;
  }
  # Make sure the Date which looks like a date is actually a valid calendar day. DateTime used by Koha crashes Koha if there are invalid calendar dates.
  my $dt;
  eval {
    $dt = DateTime->new(year => $dc[0],
                        month => $dc[1],
                        day => $dc[2],
                        hour => $dc[3] || 0,
                        minute => $dc[4] || 0,
                        second => $dc[5] || 0,)
  };
  if ($@) {
    $log->error("Parsed date string '$dateStr' as '@dc', but this is not a valid calendar date!");
  }
  return $dt->iso8601();
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

# From Hetula
my @ssnValidCheckKeys = (0..9,qw(A B C D E F H J K L M N P R S T U V W X Y));
sub _getSsnChecksum {
  my ($day, $month, $year, $checkNumber) = @_;

  my $checkNumberSum = sprintf("%02d%02d%02d%03d", $day, $month, $year, $checkNumber);
  my $checkNumberIndex = $checkNumberSum % 31;
  return $ssnValidCheckKeys[$checkNumberIndex];
}

return 1;
