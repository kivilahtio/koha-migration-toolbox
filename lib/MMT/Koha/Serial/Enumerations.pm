use Modern::Perl '2016';

package MMT::Koha::Serial::Enumerations;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';
use English;

#External modules

#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::Koha::Serial::Enumerations - Different algorithms for extracting the serial enumeration to Koha

=cut

my @enumChronColsOrderIfChronFirst = qw(chron1 chron2 chron3 chron4 alt_chron lvl1 lvl2 lvl3 lvl4 lvl5 lvl6 alt_lvl1 alt_lvl2);
my @enumChronColsOrderIfEnumFirst  = qw(lvl1 lvl2 lvl3 lvl4 lvl5 lvl6 alt_lvl1 alt_lvl2 chron1 chron2 chron3 chron4 alt_chron);
sub chronOrEnumOrdered($s, $o, $b) {
  $s->sourceKeyExists($o, $_) for @enumChronColsOrderIfChronFirst;
  #No filtering this time, just pass everything through as is and lets worry about it later.
  #$s->{serialseq} = $o->{enumchron} =~ s/\s*,\s*/ : /gsm; #Turn , to : for Koha? This is configurable in numbering patterns.

  #Hack something to populate serialseq_[xyz]
  #If chron1 is a year, use chron1 : chron2 : chron3.others
  #else lvl1 : lvl2 : lvl3.others
  my $xyzI = 0; #Iterate serialseq_[xyz]
  my @xyz;
  my $colOrder;
  $colOrder = \@enumChronColsOrderIfChronFirst if (MMT::Validator::probablyAYear($o->{chron1}));
  $colOrder = \@enumChronColsOrderIfEnumFirst unless $colOrder;

  for my $k (@$colOrder) {
    if ($o->{$k}) {
      $xyz[$xyzI] = ($xyz[$xyzI]) ? $xyz[$xyzI].' '.$o->{$k} : $o->{$k};
      if ($xyzI < 2) { $xyzI++ }
    }
  }

  if (@xyz < 2) {
    parseEnumchron(@_);
  }
  else {
    $s->{serialseq_x} = $xyz[0] if $xyz[0];
    $s->{serialseq_y} = $xyz[1] if $xyz[1];
    $s->{serialseq_z} = $xyz[2] if $xyz[2];
  }
  $s->{serialseq}   = $o->{enumchron};

  my @vals = map {$o->{$_} // ''} @enumChronColsOrderIfEnumFirst;
  $log->debug(sprintf("%-5s, %-20s - %-20s - %6s, %6s, %6s, %6s, %6s, %6s, %10s, %10s, %10s, %10s, %10s, %10s, %10s", $s->{subscriptionid}, join(':', @xyz), $o->{enumchron}, @vals));
}

sub parseEnumchron($s, $o, $b) {
  $s->sourceKeyExists($o, 'enumchron');

  my @digits = $o->{enumchron} =~ /(\d+)/gsm;

  $s->{serialseq_x} = $digits[0] if $digits[0];
  $s->{serialseq_y} = $digits[1] if $digits[1];
  $s->{serialseq_z} = join(' ', splice(@digits, 2, scalar(@digits))) if $digits[2];
}

sub enumThenChron($s, $o, $b) {
  $s->sourceKeyExists($o, $_) for @enumChronColsOrderIfChronFirst;

  my $xyzI = 0; #Iterate serialseq_[xyz]
  my @xyz;
  for my $k (@enumChronColsOrderIfEnumFirst) {
    if (defined($o->{$k}) && $o->{$k} =~ /^\d+$/ && $o->{$k} >= 0) { #Is digit and not negative
      $xyz[$xyzI] = ($xyz[$xyzI]) ? $xyz[$xyzI].' '.$o->{$k} : $o->{$k};
      if ($xyzI < 2) { $xyzI++ }
    }
  }

  if (@xyz < 2) {
    parseEnumchron(@_);
  }
  else {
    $s->{serialseq_x} = $xyz[0] if $xyz[0];
    $s->{serialseq_y} = $xyz[1] if $xyz[1];
    $s->{serialseq_z} = $xyz[2] if $xyz[2];
  }
  $s->{serialseq}   = $o->{enumchron};

  my @vals = map {$o->{$_} // ''} @enumChronColsOrderIfEnumFirst;
  $log->debug(sprintf("%-5s, %-20s - %-20s - %6s, %6s, %6s, %6s, %6s, %6s, %10s, %10s, %10s, %10s, %10s, %10s, %10s", $s->{subscriptionid}, join(':', @xyz), $o->{enumchron}, @vals));
}

return 1;
