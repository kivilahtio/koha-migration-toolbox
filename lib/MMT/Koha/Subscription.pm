package MMT::Koha::Subscription;

use MMT::Pragmas;

#External modules

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::Koha::Subscription - Transforms a bunch of Voyager data into Koha subscriptions

=cut

=head2 build

 @param1 Voyager data object
 @param2 Builder

=cut

sub build($self, $o, $b) {
  $self->setKeys                 ($o, $b, [['bib_id' => 'biblionumber'], ['component_id' => 'subscriptionid']]);

  #$self->setLibrarian           ($o, $b); #| varchar(100) | YES  |     |         |                |
  $self->setStartdate            ($o, $b); #| date         | YES  |     | NULL    |                |
  #$self->setAqbooksellerid      ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setCost                ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setAqbudgetid          ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setWeeklength          ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setMonthlength         ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setNumberlength        ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setPeriodicity         ($o, $b); #| int(11)      | YES  | MUL | NULL    |                |
  #$self->setCountissuesperunit  ($o, $b); #| int(11)      | NO   |     | 1       |                |
  #$self->setNotes               ($o, $b); #| mediumtext   | YES  |     | NULL    |                |
  $self->setStatus               ($o, $b); #| varchar(100) | NO   |     |         |                |
  #$self->setLastvalue1          ($o, $b); #| int(11)      | YES  |     | NULL    |                |
  #$self->setInnerloop1          ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setLastvalue2          ($o, $b); #| int(11)      | YES  |     | NULL    |                |
  #$self->setInnerloop2          ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setLastvalue3          ($o, $b); #| int(11)      | YES  |     | NULL    |                |
  #$self->setInnerloop3          ($o, $b); #| int(11)      | YES  |     | 0       |                |
  #$self->setFirstacquidate      ($o, $b); #| date         | YES  |     | NULL    |                |
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
}

sub id {
  return 'S:'.($_[0]->{biblionumber} || 'NULL').'-s:'.($_[0]->{subscriptionid} || 'NULL');
}

sub logId($s) {
  return 'Subscription: '.$s->id();
}

sub setStartdate($s, $o, $b) {
  $s->{startdate} = $o->{start_date};

  unless ($s->{startdate}) {
    #Voyager seems to have so very few subsription.start_date -values that it is better to default it
    #DB default is NULL.
    #Do nothing...
  }
}
sub setStatus($s, $o, $b) {
  $s->{status} = 1;
}
sub setLocation($s, $o, $b) {
  my $branchcodeLocationCcode = _translateLocationId(@_);
  $s->{location} = $branchcodeLocationCcode->{location};

  unless ($s->{location}) {
    MMT::Exception::Delete->throw($s->logId()."' has no location. Set a default in the TranslationTable rules!");
  }
}
sub setBranchcode($s, $o, $b) {
  my $branchcodeLocationCcode = _translateLocationId(@_);
  $s->{branchcode} = $branchcodeLocationCcode->{branch};

  unless ($s->{branchcode}) {
    MMT::Exception::Delete->throw($s->logId()."' has no branchcode. Set a default in the TranslationTable rules!");
  }
}
sub setSerialsadditems($s, $o, $b) {
  $s->sourceKeyExists($o, 'create_items');
  $s->{serialsadditems} = $o->{create_items};
}
sub setStaffdisplaycount($s, $o, $b) {
  $s->{staffdisplaycount} = 52;
}
sub setOpacdisplaycount($s, $o, $b) {
  $s->{opacdisplaycount} = 52;
}
sub setEnddate($s, $o, $b) {
  $s->{enddate} = $o->{end_date};

  unless ($s->{enddate}) {
    #Voyager seems to have so very few component_pattern.end_date -values that it is better to default it
    #DB default is NULL.
    #Do nothing...
  }
}
sub setClosed($s, $o, $b) {
  $s->{closed} = 1; #Currently only bare minimums are migrated, so enumeration cannot atm. continue in Koha from where voyager left off.
}

sub _translateLocationId($s, $o, $b) {
  my $subscriptionLocations = $b->{SubscriptionLocation}->get($o);
  my $locationId;

  if (not($subscriptionLocations)) {
    $log->warn($log->logId()." has no location?");
    $locationId = '_DEFAULT_';
  }
  #In theory, there could be multiple locations for one subscription/component, but the extract-phase unique key deduplication should take care of that.
  elsif (@$subscriptionLocations > 1) { #Doesn't hurt to be a bit defensive sometimes.
    $log->warn($log->logId()." has multiple subscription locations to choose from? Defaulting to the first one.");
  }

  if ($subscriptionLocations && $subscriptionLocations->[0]) {
    $locationId = $subscriptionLocations->[0]->{location_id};
    unless ($locationId) {
      $log->error($log->logId()." has a location, but the location is missing attribute 'location_id'? Using defaults.");
      $locationId = '_DEFAULT_';
    }
  }

  return $b->{LocationId}->translate(@_, $locationId);
}

return 1;