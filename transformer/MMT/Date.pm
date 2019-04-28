package MMT::Date;

use MMT::Pragmas;

#External modules

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::Date - Date transformations

=cut

sub _monToNum($mon, $o) {
  given($mon) {
    return 1  when("JAN");
    return 2  when("FEB");
    return 3  when("MAR");
    return 4  when("APR");
    return 5  when("MAY");
    return 6  when("JUN");
    return 7  when("JUL");
    return 8  when("AUG");
    return 9  when("SEP");
    return 10 when("OCT");
    return 11 when("NOV");
    return 12 when("DEC");
    default {
      $log->error("Translating month '$mon' to number for object '".$o->logId()."' failed, because '$mon is an unknown US-English representation of a month.'");
      return 1;
    }
  }
}

=head1 translate*

All translate*() subroutines share the same signature:

 @param1 String,  date to convert
 @param2 HASHRef, Voyager object
 @param3 String,  some description about the attribute for which the data translation is being done.
                  Used for debugging and error messages.
 @param4 Integer, Number of years to adjust the turnover point from the 20th century to the 21st century.
                  Voyager dates only store the decade+year information without the millenium+century information.
                  So figuring out which century is needed, is context sensitive.
                  Since we live in the 21st century, we presume that all decades+years (00-18) before our current
                  year (18 atm) are on the 21st century.
                  All decade+years larger than the current turnover point,
                    by default the current year,
                  probably belong to the past century.
                  This parameter shifts the turnover point by the amount given, for ex.
                    3 would increase it from the current year, for ex. 2018, to 2021.
                    -5 would decrement it to 2013

=cut

my $nowYear = (localtime())[5];
sub _translate($parser, $datein, $o, $attribute, $yearOffsetThreshold=0) {
  unless ($datein) {
    $log->warn("Object '".$o->logId()."' is missing date when setting attribute '$attribute'");
    return undef;
  }
  my ($year,$month,$day) = $parser->($datein, $o);
  if (length $year < 3) {
    if ($year > $nowYear+$yearOffsetThreshold) {
      $year = "19$year";
    }
    else {
      $year = "20$year";
    }
  }
  if ($year && $month && $day) {
    return sprintf "%4d-%02d-%02d",$year,$month,$day;
  }
  else {
    $log->logdie("Object '".$o->logId()."' has malformed Voyager date '$datein' for attribute '$attribute'");
  }
}

=head2 translateDateMMDDYYYY

Translate Voyager date format
  MM.DD.YYYY
to ISO-8601

See translate*()

=cut

sub _translateMMDDYYYYParser($datein, $o) {
  $datein =~ /(\d{2}).(\d{2}).(\d{4})/;
  return ($3, $1, $2);
};
sub translateDateMMDDYYYY($datein, $o, $attribute, $yearOffsetThreshold=0) {
  return _translate(\&_translateMMDDYYYYParser, @_);
}

=head2 translateDateDDMMMYY

Translate Voyager date format
  29-AUG-08
to ISO-8601

See translate*()

=cut

sub _translateDDMMMYYParser($datein, $o) {
  $datein =~ /(\d{2})-(\w{3}).(\d{2})/;
  return ($3, _monToNum($2, $o), $1);
};
sub translateDateDDMMMYY($datein, $o, $attribute, $yearOffsetThreshold=0) {
  return _translate(\&_translateDDMMMYYParser, @_);
}

my $re_isIso = qr/^\d\d\d\d-\d\d-\d\d$/;
sub isIso8601($date) {
  return $date =~ $re_isIso;
}

return 1;