use 5.22.1;

package MMT::Date;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';

#External modules

#Local modules
use MMT::Config;
use Log::Log4perl;
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

=head2 translateDateMMDDYYYY
Translate Voyager date format
  MM.DD.YYYY
to ISO-8601
=cut
sub translateDateMMDDYYYY($datein, $o, $attribute) {
  unless ($datein) {
    $log->warn("Object '".$o->logId()."' is missing date when setting attribute '$attribute'");
    return undef;
  }
  my ($month,$day,$year) = $datein =~ /(\d{2}).(\d{2}).(\d{4})/;
  if ($year > 18) {
    $year = "19$year";
  }
  else {
    $year = "20$year";
  }
  if ($month && $day && $year) {
    return sprintf "%4d-%02d-%02d",$year,$month,$day;
  }
  else {
    $log->logdie("Object '".$o->logId()."' has malformed Voyager date '$datein' for attribute '$attribute'");
  }
}
=head2 translateDateDDMMMYY
Translate Voyager date format
  29-AUG-08
to ISO-8601
=cut
sub translateDateDDMMMYY($datein, $o, $attribute) {
  unless ($datein) {
    $log->warn("Object '".$o->logId()."' is missing date when setting attribute '$attribute'");
    return undef;
  }
  my ($day,$month,$year) = $datein =~ /(\d{2})-(\w{3}).(\d{2})/;
  if ($year > 18) {
    $year = "19$year";
  }
  else {
    $year = "20$year";
  }
  $month = _monToNum($month, $o);
  if ($month && $day && $year) {
    return sprintf "%4d-%02d-%02d",$year,$month,$day;
  }
  else {
    $log->logdie("Object '".$o->logId()."' has malformed Voyager date '$datein' for attribute '$attribute'");
  }
}

return 1;