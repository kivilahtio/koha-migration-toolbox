package MMT::PrettyCirc2Koha::Periodical;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::Validator;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::PrettyCirc2Koha::Periodical

=cut

=head2 build

 @param1 PrettyCirc data object
 @param2 Builder

=cut

sub build($self, $o, $b) {
  $self->setBiblionumber       ($o, $b); #line_item.bib_id,
  $self->setSubscriptionid     ($o, $b); #component.subscription_id,
  $self->setSerialid        ($o, $b);
  $self->setItemnumber         ($o, $b);
  $self->setEnumerations       ($o, $b); #s.enumchron, s.lvl1, s.lvl2, s.lvl3, s.lvl4, s.lvl5, s.lvl6, s.alt_lvl1, s.alt_lvl2, s.chron1, s.chron2, s.chron3, s.chron4, s.alt_chron,
  #  \$self->setSerialseq       ($o, $b);
  #   \$self->setSerialseq_x     ($o, $b);
  #    \$self->setSerialseq_y     ($o, $b);
  #     \$self->setSerialseq_z     ($o, $b);
  $self->setStatus             ($o, $b); #s.receipt_date
  $self->setPlanneddate        ($o, $b); #s.expected_date
  $self->setNotes              ($o, $b);
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

sub setSerialid($s, $o, $b) {
  $s->{serialid} = $o->{Id};
}

sub setBiblionumber($s, $o, $b) {
  my $items = $b->{Items}->get($o->{Id_Item});
  unless ($items && @$items) {
    $log->error("Periodical '".$o->{Id}."' - Doesn't have an attached Item? Cannot link to a biblio.");
    return;
  }
  my $biblionumber = $items->[0]->{Id_Title};
  unless ($biblionumber) {
    $log->error("Periodical '".$o->{Id}."' - Attached item is missing the biblionumber?");
    return;
  }
  $s->{biblionumber} = $biblionumber;
}

sub setSubscriptionid($s, $o, $b) {
  $s->{subscriptionid} = $o->{Id_Item};  # In PrettyCirc the Item is the subscription.
}

sub setItemnumber($s, $o, $b) { #This is used to populate the koha.serialitems -link
  $s->sourceKeyExists($o, 'Id_Item');
  $s->{itemnumber} = $o->{Id_Item} || undef; #item_id can also be 0 or '', just normalize it to undef
}

#In Koha, the planneddate is the date the serial is expected to arrive to the library.
sub setPlanneddate($s, $o, $b) {
  if ($o->{PeriodDate}) {
    $s->{planneddate} = MMT::Validator::parseDate($o->{PeriodDate});
  }
  elsif ($o->{PeriodYear} && $o->{PeriodYear} =~ /^\d\d\d\d/) {
    $s->{planneddate} = $o->{PeriodYear}.'-01-01';
  }
  else {
    $s->{planneddate} = '2001-01-01';
  }
}
sub setNotes($s, $o, $b) {
  $s->{notes} = $o->{Notes};
}
#In Koha the publisheddate is the date the serial is actually printed. Voyager has no such distinction, so reuse expected_date.
sub setPublisheddate($s, $o, $b) {
  $s->{publisheddate} = $s->{planneddate};
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
  $s->{status} = ARRIVED;
}

sub setEnumerations($s, $o, $b) {
  $s->{serialseq} = join(' : ', grep {$_} ($o->{PeriodYear}, $o->{PeriodVol}, $o->{PeriodNumber}));
  ($s->{serialseq_x}, $s->{serialseq_y}, $s->{serialseq_z}) = split(' : ', $s->{serialseq});
}

return 1;
