use Modern::Perl '2016';

package MMT::Koha::Serial;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';
use English;

#External modules

#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);
use MMT::Date;
use MMT::Validator;

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::Koha::Serial - Transforms a bunch of Voyager data into Koha serials

=cut

=head2 build

 @param1 Voyager data object
 @param2 Builder

=cut

my @keys = (['component_id' => 'subscriptionid'], ['issue_id' => 'serialid'], ['bib_id' => 'biblionumber']);
sub build($self, $o, $b) {
  $self->setKeys               ($o, $b, \@keys);
  #  \$self->setBiblionumber    ($o, $b); #line_item.bib_id,
  #   \$self->setSubscriptionid  ($o, $b); #component.subscription_id,
  #    \$self->setSerialid        ($o, $b); #s.serial_id
  $self->setEnumerations       ($o, $b); #s.enumchron, s.lvl1, s.lvl2, s.lvl3, s.lvl4, s.lvl5, s.lvl6, s.alt_lvl1, s.alt_lvl2, s.chron1, s.chron2, s.chron3, s.chron4, s.alt_chron,
  #  \$self->setSerialseq       ($o, $b);
  #   \$self->setSerialseq_x     ($o, $b);
  #    \$self->setSerialseq_y     ($o, $b);
  #     \$self->setSerialseq_z     ($o, $b);
  $self->setStatus             ($o, $b); #s.receipt_date
  $self->setPlanneddate        ($o, $b); #s.expected_date
  #$self->setNotes             ($o, $b);
  $self->setPublisheddate      ($o, $b);
  #$self->setPublisheddatetext ($o, $b);
  #$self->setClaimdate         ($o, $b);
  #$self->setClaims_count      ($o, $b);
  #$self->setRoutingnotes      ($o, $b);
}

sub id {
  return 'S:'.($_[0]->{subscriptionid} || 'NULL').'-s:'.($_[0]->{serialid} || 'NULL');
}

sub logId($s) {
  return 'Serial: '.$s->id();
}

sub setPlanneddate($s, $o, $b) {
  $s->{planneddate} = MMT::Date::translateDateDDMMMYY($o->{receipt_date} || $o->{expected_date}, $s, 'receipt_date||expected_date->planneddate');

  unless ($s->{planneddate}) {
    MMT::Exception::Delete->throw($s->logId()."' has no receipt_date||expected_date/planneddate.");
  }
}
sub setPublisheddate($s, $o, $b) {
  $s->{publisheddate} = MMT::Date::translateDateDDMMMYY($o->{expected_date}, $s, 'expected_date->publisheddate');
  unless ($s->{publisheddate}) {
    MMT::Exception::Delete->throw($s->logId()."' has no expected_date/publisheddate.");
  }
}
use constant { #Koha C4::Serial line 44:
    EXPECTED               => 1,
    ARRIVED                => 2,
    LATE                   => 3,
    MISSING                => 4,
    MISSING_NEVER_RECIEVED => 41,
    MISSING_SOLD_OUT       => 42,
    MISSING_DAMAGED        => 43,
    MISSING_LOST           => 44,
    NOT_ISSUED             => 5,
    DELETED                => 6,
    CLAIMED                => 7,
    STOPPED                => 8,
};
sub setStatus($s, $o, $b) {
  $s->sourceKeyExists($o, 'receipt_date');

  if ($o->{receipt_date}) {
    $s->{status} = ARRIVED;
  }
  else {
    $s->{status} = EXPECTED;
  }
}
my @enumChronColsOrderIfChronFirst = qw(chron1 chron2 chron3 chron4 alt_chron lvl1 lvl2 lvl3 lvl4 lvl5 lvl6 alt_lvl1 alt_lvl2);
my @enumChronColsOrderIfEnumFirst  = qw(lvl1 lvl2 lvl3 lvl4 lvl5 lvl6 alt_lvl1 alt_lvl2 chron1 chron2 chron3 chron4 alt_chron);
sub setEnumerations($s, $o, $b) {
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
      $xyzI++ if $xyzI < 3;
    }
  }

  $s->{serialseq_x} = $xyz[0] if $xyz[0];
  $s->{serialseq_y} = $xyz[1] if $xyz[1];
  $s->{serialseq_z} = $xyz[2] if $xyz[2];
  $s->{serialseq}   = join(":", @xyz);
}

return 1;
