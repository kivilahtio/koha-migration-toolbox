package MMT::PrettyCirc2Koha::Subscription;

use MMT::Pragmas;

#External modules
use DateTime;
use DateTime::Format::MySQL;

#Local modules
use MMT::PrettyCirc2Koha::Periodical;
use MMT::Validator;
use MMT::Validator::Money;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::PrettyCirc2Koha::Subscription - Transforms a bunch of PrettyCirc data into Koha subscriptions

=cut


# Build the subscriptions here based on the individual serials analyzed for each Biblio.
our %subscriptions;

sub analyzePeriodicals($b) {
  while (defined(my $textPtr = $b->{next}->())) {
    my $o;
    eval {
      my @colNames = $b->{csv}->column_names();
      $o = {};
      $b->{csv}->bind_columns(\@{$o}{@colNames});
      $b->{csv}->parse($$textPtr);
    };
    if ($@) {
      $log->error("Unparseable .csv-row!\n$@\nThe unparseable row follows\n$$textPtr");
      next;
    }
    analyzePeriodical($o, $b);
  }
}

sub createFillerSubscriptions($b) {
  while (my ($itemnumber, $s) = each(%subscriptions)) {
    build($s, {}, $b);
    $log->debug("Writing ".$s->{itemnumber}) if $log->is_debug();
    $b->writeToDisk( $s->serialize() );
  }
}

=head2 analyzePeriodical

=cut

sub analyzePeriodical($o, $b) {
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

  #Sanitate dates
  $o->{PeriodDate} = MMT::Validator::parseDate($o->{PeriodDate}) if $o->{PeriodDate};

  $subscriptions{$o->{Id_Item}} = bless({biblionumber => $biblionumber, itemnumber => $o->{Id_Item}, subscriptionid => $o->{Id_Item}}, 'MMT::PrettyCirc2Koha::Subscription') unless $subscriptions{$o->{Id_Item}};
  my $s = $subscriptions{$o->{Id_Item}};

  # look for the lowest start date
  $s->{startdate} = '2100-01-01' unless $s->{startdate}; #Seed this value high, so pretty much any real value will be less than this starting date
  if ($o->{PeriodDate} && $o->{PeriodDate} lt $s->{startdate}) {
    $s->{startdate} = $o->{PeriodDate};
  }
  elsif ($o->{PeriodYear} && $o->{PeriodYear} =~ /^\d\d\d\d/ && $o->{PeriodYear} lt $s->{startdate}) {
    $s->{startdate} = $o->{PeriodYear}.'-01-01';
  }

  # look for the biggest end date
  $s->{enddate} = '1000-01-01' unless $s->{enddate};
  if ($o->{PeriodDate} && $o->{PeriodDate} gt $s->{enddate}) {
    $s->{enddate} = $o->{PeriodDate};
  }
  elsif ($o->{PeriodYear} && $o->{PeriodYear} =~ /^\d\d\d\d/ && $o->{PeriodYear} gt $s->{enddate}) {
    $s->{enddate} = $o->{PeriodYear}.'-12-31';
  }

  # Build subscriptionhistory
  my $serialseq = MMT::PrettyCirc2Koha::Periodical::_calculateEnumerations($o);
  $s->{subscriptionhistory} = [] unless $s->{subscriptionhistory};
  push(@{$s->{subscriptionhistory}}, $serialseq);
}

=head2 build

 @param1 PrettyCirc data object
 @param2 Builder

=cut

sub build($self, $o, $b) {
  #$self->setKeys                 ($o, $b, [['bib_id' => 'biblionumber'], ['component_id' => 'subscriptionid']]);

  #$self->setLibrarian           ($o, $b); #| varchar(100) | YES  |     |         |                |
  $self->setStartdate            ($o, $b); #| date         | YES  |     | NULL    |                |
  $self->setAqbooksellerid       ($o, $b); #| int(11)      | YES  |     | 0       |                |
  $self->setCost                 ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setAqbudgetid          ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setWeeklength          ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setMonthlength         ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setNumberlength        ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setPeriodicity         ($o, $b); #| int(11)      | YES  | MUL | NULL    |                |
  #$self->setCountissuesperunit  ($o, $b); #| int(11)      | NO   |     | 1       |                |
  $self->setNotes               ($o, $b); #| mediumtext   | YES  |     | NULL    |                |
  $self->setStatus               ($o, $b); #| varchar(100) | NO   |     |         |                |
  #$self->setLastvalue1          ($o, $b); #| int(11)      | YES  |     | NULL    |                |
  #$self->setInnerloop1          ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setLastvalue2          ($o, $b); #| int(11)      | YES  |     | NULL    |                |
  #$self->setInnerloop2          ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setLastvalue3          ($o, $b); #| int(11)      | YES  |     | NULL    |                |
  #$self->setInnerloop3          ($o, $b); #| int(11)      | YES  |     | 0       |                |
  $self->setFirstacquidate       ($o, $b); #| date         | YES  |     | NULL    |                |
  #$self->setManualhistory       ($o, $b); #| tinyint(1)   | NO   |     | 0       |                |
  #$self->setIrregularity        ($o, $b); #| text         | YES  |     | NULL    |                |
  #$self->setSkip_serialseq      ($o, $b); #| tinyint(1)   | NO   |     | 0       |                |
  #$self->setLetter              ($o, $b); #| varchar(20)  | YES  |     | NULL    |                |
  #$self->setNumberpattern       ($o, $b); #| int(11)      | YES  | MUL | NULL    |                |
  #$self->setLocale              ($o, $b); #| varchar(80)  | YES  |     | NULL    |                |
  #$self->setDistributedto       ($o, $b); #| text         | YES  |     | NULL    |                |
  #$self->setInternalnotes       ($o, $b); #| longtext     | YES  |     | NULL    |                |
  #$self->setCallnumber          ($o, $b); #| text         | YES  |     | NULL    |                |
  $self->setLocation             ($o, $b); #| varchar(80)  | YES  |     |         |                |
  $self->setBranchcode           ($o, $b); #| varchar(10)  | NO   |     |         |                |
  #$self->setLastbranch          ($o, $b); #| varchar(10)  | YES  |     | NULL    |                |
  $self->setSerialsadditems      ($o, $b); #| tinyint(1)   | NO   |     | 0       |                |
  $self->setStaffdisplaycount    ($o, $b); #| varchar(10)  | YES  |     | NULL    |                |
  $self->setOpacdisplaycount     ($o, $b); #| varchar(10)  | YES  |     | NULL    |                |
  #$self->setGraceperiod         ($o, $b); #| int(11)      | NO   |     | 0       |                |
  $self->setEnddate              ($o, $b); #| date         | YES  |     | NULL    |                |
  $self->setClosed               ($o, $b); #| int(1)       | NO   |     | 0       |                |
  #$self->setReneweddate         ($o, $b); #| date         | YES  |     | NULL    |                |
  #$self->setItemtype            ($o, $b); #| varchar(10)  | YES  |     | NULL    |                |
  #$self->setPreviousitemtype    ($o, $b); #| varchar(10)  | YES  |     | NULL    |                |

  $self->setSubscriptionhistory  ($o, $b);
}

sub id {
  return $_[0]->{itemnumber};
}

sub logId($s) {
  return 'Subscription: '.$s->id();
}

sub setAqbooksellerid($s, $o, $b) {
  my $supplierId = $s->_getCircleNewOrder($b, 'Id_Supplier');
  $s->{aqbooksellerid} = $supplierId if $supplierId;
}
sub setCost($s, $o, $b) {
  my $cost = $s->_getCircleNewOrder($b, 'EstPrice');
  $s->{cost} = MMT::Validator::Money::money_PrettyLib($s, $o, $b, $cost) if $cost;
}
sub setNotes($s, $o, $b) {
  my $n = $s->_getCircleNewOrder($b, 'Notes');
  $s->{notes} = $n if $n;
}
sub setStartdate($s, $o, $b) {
  unless ($s->{startdate}) {
    #Voyager seems to have so very few subsription.start_date -values that it is better to default it
    $log->warn($s->logId()." is missing 'startdate'");
    $s->{startdate} = '2000-01-01'; #Koha must have a koha.subscription.startdate
  }
}
sub setStatus($s, $o, $b) {
  $s->{status} = 1;
}
sub setFirstacquidate($s, $o, $b) {
  $s->{firstacquidate} = $s->{startdate};
}
sub setLocation($s, $o, $b) {
  my $item = $b->{Items}->get($s->{itemnumber})->[0];
  my $branchcodeLocation = $b->{LocationId}->translate(@_, $item->{Id_Location});
  $s->{location} = $branchcodeLocation->{location};
}
sub setBranchcode($s, $o, $b) {
  my $item = $b->{Items}->get($s->{itemnumber})->[0];
  $s->{branchcode} = $b->{Branchcodes}->translate(@_, $item->{Id_Library});

  unless ($s->{branchcode}) {
    MMT::Exception::Delete->throw($s->logId()."' has no branchcode. Set a default in the TranslationTable rules!");
  }
}
sub setSerialsadditems($s, $o, $b) {
  $s->{serialsadditems} = 0;
}
sub setStaffdisplaycount($s, $o, $b) {
  #$s->{staffdisplaycount} = 300; # Use the serials module and syspref defaults
}
sub setOpacdisplaycount($s, $o, $b) {
  #$s->{opacdisplaycount} = 300; # Use the serials module and syspref defaults
}
my $endDate = DateTime->now()->ymd('-');
my $endDateContinues = DateTime->now()->set_month(12)->set_day(31)->ymd('-');
my $closedSubscriptionCutoffDate = DateTime->now()->subtract(months => 6);
sub setEnddate($s, $o, $b) {
  my $circleOrderNew_enddate = $s->_getCircleNewOrder($b, 'EndDate');
  if ($circleOrderNew_enddate) {
    $s->{enddate} = MMT::Validator::parseDate($circleOrderNew_enddate);
  }
  else {
    unless ($s->{enddate}) {
      $s->{enddate} = $endDate;
      $s->{closed} = 1;
    }
  }
}
sub setClosed($s, $o, $b) {
  return if $s->{closed};

  my $ed = DateTime::Format::MySQL->parse_date($s->{enddate});
  if (DateTime->compare($ed, $closedSubscriptionCutoffDate) > 0) { # current enddate is newer than the closed cutoff date
    $s->{closed} = 0;
  }
  else {
    $s->{closed} = 1;
  }
}

=head2 setSubscriptionhistory

To properly operate the subscriptions in Koha, they MUST have matching subscriptiohistory-rows

=cut

sub setSubscriptionhistory($s, $o, $b) {
  MMT::Exception::Delete->throw($s->logId()." has no subscriptiohistory-key?") unless (exists($s->{subscriptionhistory}));
  $s->{subscriptionhistory} = join('; ', sort @{$s->{subscriptionhistory}});
}



sub _getCircleNewOrder($s, $b, $attribute) {
  my $c = $b->{CircleNewOrder}->get($s->{itemnumber});
  if ($c && $c->[0]) {
    return $c->[0]->{$attribute} if $attribute;
    return $c->[0];
  }
  return undef;
}

return 1;
