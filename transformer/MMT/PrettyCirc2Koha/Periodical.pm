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
use MMT::Exception::Delete::Silently;

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
  if ($b->{deleteList}->get('BIBL'.$self->{biblionumber})) {
    MMT::Exception::Delete::Silently->throw($self->logId()." - Biblio already deleted");
  }

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

sub getDeleteListId($s) {
  return 'SERI'.$s->{serialid};
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
  # In PrettyCirc the Item is the subscription. Avoid setting the same itemnumber for all periodicals, this causes serialitems-table to be populated with insane amounts of duplicate itemnumber, because
  # In PrettyCirc the Item is the subscription, not like in Koha.
  #$s->sourceKeyExists($o, 'Id_Item');
  #$s->{itemnumber} = $o->{Id_Item} || undef; #item_id can also be 0 or '', just normalize it to undef
  $s->{itemnumber} = undef;
}

# In Koha, the planneddate is the date the serial is expected to arrive to the library.
# In PrettyCirc WaitDate and PeriodDate are used inconsistently and there seems to be no rule for what they signify.
# Using a simple heuristic, pick the date which is closer to the PeriodYear.
sub setPlanneddate($s, $o, $b) {
  my $dateCandidates = {};

  for my $dateType (('WaitDate','PeriodDate')) {
    next unless $o->{$dateType};
    my ($dateErr, $date) = MMT::Validator::parseDate($o->{$dateType});
    if ($dateErr) {
      $log->error("Periodical '".$s->id()."' unable to parse '$dateType'='$date'");
      next;
    }

    if ($o->{PeriodYear} && $o->{PeriodYear} =~ /^\s*(\d\d\d\d)/) {
      my $periodYear = $1;
      $date =~ /^(\d\d\d\d)/;
      my $datesApart = $periodYear - $1;
      if ($datesApart == 0) {
        $s->{planneddate} = $date;
        $log->trace("Periodical '".$s->id()."' found exact planneddate match from field '$dateType'.");
        return $s;
      }
    }
  }

  my $date = $o->{WaitDate} || $o->{PeriodDate};
  if (not($date)) {
    $s->{planneddate} = "1999-12-31";
    return $s;
  }

  my $dateErr;
  ($dateErr, $date) = MMT::Validator::parseDate($date);
  if ($dateErr) {
    $s->{planneddate} = "1999-12-31"; # Already warn about poor date in the year diff checker.
    return $s;
  }

  if ($o->{PeriodYear} && $o->{PeriodYear} =~ /^\s*(\d\d\d\d)/) {
    my $periodYear = $1;
    $date =~ s/^\d\d\d\d/$periodYear/;
    $s->{planneddate} = $date;
  }
  else {
    $s->{planneddate} = $date;
  }
  return $s;
}
sub setNotes($s, $o, $b) {
  my @notes;
  push(@notes, $o->{Notes}) if $o->{Notes};
  push(@notes, $o->{Extra1}) if $o->{Extra1};
  push(@notes, $o->{Extra2}) if $o->{Extra2};
  $s->{notes} = join(' | ', @notes);
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
  $s->{serialseq} = _calculateEnumerations($o);
  ($s->{serialseq_x}, $s->{serialseq_y}, $s->{serialseq_z}) = split(' : ', $s->{serialseq});
}
sub _calculateEnumerations($o) {
  return join(' : ', grep {$_} ($o->{PeriodYear}, $o->{PeriodVol}, $o->{PeriodNumber}));
}

# Gets the candidate branchcode and location for this Periodical.
# Collects indicators of possible location and branch information from the serial number/issue.
# Returns a HASH of LISTs of possible candidates.
sub calculateLocationsMFA($o, $b) {
  my $loc = {
    locations => [],
    branches => ['DEFAULT'],
  };
  for my $extra (($o->{Extra1}, $o->{Extra2})) {
    $loc->{branches}->[0] = 'VAV' if ($extra =~ /Vantaa/i);
    my @locations = $extra =~ /[AFK]/gsm;
    $log->trace("Found \@locations='@locations', branch='".$loc->{branch}."'") if $log->is_trace();
    push(@{$loc->{locations}}, @locations);
  }
  $loc->{locations}->[0] = 'DEFAULT' unless (scalar(@{$loc->{locations}}));
  return $loc;
}
sub calculateLocationsDefault($o, $b) {
  return {
    locations => ['DEFAULT'],
    branches => ['DEFAULT'],
  };
}

return 1;
