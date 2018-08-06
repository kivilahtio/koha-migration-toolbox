use 5.22.1;

package MMT::Koha::Item;
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

MMT::Koha::Item - Transforms a bunch of Voyager data into a Koha item

=cut

=head2 build

 @param1 Voyager data object
 @param2 Builder

=cut

sub build($self, $o, $b) {
  $self->setKeys($o, $b, [['item_id' => 'itemnumber'], ['bib_id' => 'biblionumber']]);

  $self->set(barcode              => 'barcode',            $o, $b);
  $self->set(add_date             => 'dateaccessioned',    $o, $b);
  $self->set(perm_location        => 'homebranch',         $o, $b);
  $self->set(price                => 'price',              $o, $b);
  $self->setDatelastborrowed                              ($o, $b);
  $self->setStatuses                                      ($o, $b);
  #  \$self->setNotforloan
  #   \$self->setDamaged
  #    \$self->setItemlost
  #     \$self->setItemlost_on
  #      \$self->setWithdrawn
  #       \$self->setWithdrawn_on
  $self->set(call_no              => 'itemcallnumber',     $o, $b);
  $self->set(historical_charges   => 'issues',             $o, $b);
  $self->setItemnotes                                     ($o, $b);
  #  \$self->setItemnotes_nonpublic
  $self->set(temp_location        => 'holdingbranch',      $o, $b);
  $self->set(perm_location        => 'permanent_location', $o, $b);
  $self->set(temp_location        => 'location',           $o, $b);
  $self->set(perm_location        => 'sub_location',       $o, $b);
  $self->set(item_type_id         => 'itype',              $o, $b);
  $self->set(['enumeration',
              'chronology']       ,  'enumchron',          $o, $b);
  $self->setCcode                                         ($o, $b);

  #$self->set(? => datereceived, $o, $b);
  #$self->set(? => booksellerid, $o, $b);
  #$self->set(? => replacementprice, $o, $b);
  #$self->set(? => replacementpricedate, $o, $b);
  #$self->set(? => datelastseen, $o, $b);
  #$self->set(? => stack, $o, $b);
  #$self->set(? => coded_location_qualifier, $o, $b);
  #$self->set(? => renewals, $o, $b);
  #$self->set(? => reserves, $o, $b);
  #$self->set(? => restricted, $o, $b);
  #$self->set(? => paidfor, $o, $b);
  #$self->set(? => timestamp, $o, $b);
  #$self->set(? => onloan, $o, $b);
  #$self->set(? => cn_source, $o, $b);
  #$self->set(? => cn_sort, $o, $b);
  #$self->set(? => materials, $o, $b);
  #$self->set(? => uri, $o, $b);
  #$self->set(? => more_subfields_xml, $o, $b);
  #$self->set(? => copynumber, $o, $b);
  #$self->set(? => stocknumber, $o, $b);
  #$self->set(? => new_status, $o, $b);
  #$self->set(? => genre, $o, $b);
  #$self->set(? => sub_location, $o, $b);
  #$self->set(? => circulation_level, $o, $b);
  #$self->set(? => reserve_level, $o, $b);
}

sub id {
  return sprintf("bc:%s-in:%s", $_[0]->{barcode} || 'NULL', $_[0]->{itemnumber} || 'NULL');
}

sub logId($s) {
  return 'Item: '.$s->id();
}

sub setBarcode($s, $o, $b) {
  $s->{barcode} = $o->{barcode};

  unless ($s->{barcode}) {
    $log->warn($s->logId()."' has no barcode.");
    $s->{barcode} = $s->createTemporaryBarcode();
  }
}
sub setDateaccessioned($s, $o, $b) {
  $s->{dateaccessioned} = $o->{add_date};

  unless ($s->{dateaccessioned}) {
    $log->warn($s->logId()."' has no dateaccessioned.");
  }
}
sub setPrice($s, $o, $b) {
  $s->{price} = (defined($o->{price})) ? MMT::Validator::voyagerMoneyToKohaMoney($o->{price}) : undef;
  #$log->warn($s->logId()."' has no price.") unless $s->{price}; #Too much complaining about the missing price. Hides all other issues.
}
sub setDatelastborrowed($s, $o, $b) {
  my $lastBorrowDates = $b->{LastBorrowDate}->get($o);
  if ($lastBorrowDates) {
    $s->{datelastborrowed} = $lastBorrowDates->[0]->{last_borrow_date};
  }
  #It is ok for the Item to not have datelastborrowed
}
sub setItemcallnumber($s, $o, $b) {
  $s->{itemcallnumber} = $o->{call_no};

  unless ($s->{itemcallnumber}) {
    $log->warn($s->logId()." has no itemcallnumber! call_no=".$o->{call_no});
  }
}
sub setIssues($s, $o, $b) {
  $s->{issues} = $o->{historical_charges} || 0;
}
sub setItemnotes($s, $o, $b) {
  my $itemNotes = $b->{ItemNotes}->get($o->{item_id});
  #Translation table mutates $s directly
  if ($itemNotes) {
    $b->{ItemNoteTypes}->translate(@_, $_->{item_note_type}, $_) for (@$itemNotes);
  }
}
sub setHomebranch($s, $o, $b) {
  my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{perm_location});
  $s->{homebranch} = $branchcodeLocation->{branch};
  $s->{ccode} = $branchcodeLocation->{collectionCode} if $branchcodeLocation->{collectionCode};

  unless ($s->{homebranch}) {
    MMT::Exception::Delete->throw($s->logId()."' has no homebranch! perm_location=".$o->{perm_location}.". Define a default in the Branchcodes translation table!");
  }
}
sub setHoldingbranch($s, $o, $b) {
  if ($o->{temp_location}) {
    my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{temp_location});
    $s->{holdingbranch} = $branchcodeLocation->{branch};
    $s->{ccode} = $branchcodeLocation->{collectionCode} if $branchcodeLocation->{collectionCode};
  }
  else {
    $s->{holdingbranch} = $s->{homebranch};
  }
}
sub setPermanent_location($s, $o, $b) {
  my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{perm_location});
  $s->{permanent_location} = $branchcodeLocation->{location};
  $s->{ccode} = $branchcodeLocation->{collectionCode} if $branchcodeLocation->{collectionCode};

  unless ($s->{permanent_location}) {
    MMT::Exception::Delete->throw($s->logId()."' has no permanent_location! perm_location=".$o->{perm_location});
  }
}
sub setLocation($s, $o, $b) {
  if ($o->{temp_location}) {
    my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{temp_location});
    $s->{location} = $branchcodeLocation->{location};
    $s->{ccode} = $branchcodeLocation->{collectionCode} if $branchcodeLocation->{collectionCode};
  }
  else {
    $s->{location} = $s->{permanent_location};
  }
}
sub setSub_location($s, $o, $b) {
  my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{perm_location});
  $s->{sub_location} = $branchcodeLocation->{sub_location} if $branchcodeLocation->{sub_location};
}
sub setItype($s, $o, $b) {
  $s->{itype} = $b->{ItemTypes}->translate(@_, $o->{item_type_id});

  unless ($s->{itype}) {
    MMT::Exception::Delete->throw($s->logId()."' has no itype! item_type_id=".$o->{item_type_id});
  }
}
sub setEnumchron($s, $o, $b) {
  if ($o->{enumeration} && $o->{chronology}) {
    $s->{enumchron} = $o->{enumeration}.' - '.$o->{chronology};
  }
  elsif ($o->{enumeration}) {
    $s->{enumchron} = $o->{enumeration};
  }
  elsif ($o->{chronology}) {
    $s->{enumchron} = $o->{chronology};
  }
}
sub setCcode($s, $o, $b) {
  my $itemStatisticalCategories = $b->{ItemStats}->get($o->{item_id});
  return unless $itemStatisticalCategories;

  if (scalar(@$itemStatisticalCategories) > 1) {
    $log->warn($s->logId()." has '".scalar(@$itemStatisticalCategories)."' statistical categories, but in Koha we can only put one collection code. Using the newest value.");
  }

  my $itemStatisticalCategory = $itemStatisticalCategories->[-1]; #Pick the last (should be sorted so it is the newest) stat cat.
  unless ($itemStatisticalCategory->{item_stat_id} && $itemStatisticalCategory->{item_stat_code}) {
    $log->error($s->logId()." has a misconfigured item statistical category in Voyager? item_stat_id='".$itemStatisticalCategory->{item_stat_id}."' doesn't have a matching item_stat_code");
    return undef;
  }

  my $statCat = $itemStatisticalCategory->{item_stat_code};
  unless ($statCat) {
    $log->warn($s->logId()." has a statistical category with no attribute 'item_stat_code'?");
    return;
  }

  my $kohaStatCat = $b->{ItemStatistics}->translate(@_, $statCat);
  return unless ($kohaStatCat && $kohaStatCat != '');

  if ($s->{ccode}) {
    $log->warn($s->logId()." has collection code '".$s->{ccode}."' (from the LocationId translation table) and an incoming statistical category '$statCat->$kohaStatCat', but in Koha we can only have one collection code. Ignoring the incoming '$statCat->$kohaStatCat'.");
    return;
  }
  else {
    $s->{ccode} = $kohaStatCat;
  }
}

sub setStatuses($s, $o, $b) {
  my $itemStatuses = $b->{ItemStatuses}->get($o->{item_id});
  return unless $itemStatuses;

  for my $affliction (@$itemStatuses) {
    my $desc = $affliction->{item_status_desc};
    $log->trace($s->logId().' has affliction "'.$desc.'"');
    my $ks = $b->{ItemStatus}->translate(@_, $desc);
    next unless $ks;
    my ($kohaStatus, $kohaStatusValue) = split('\W+', $ks);

    given ($kohaStatus) {
      when('itemlost')   { $s->{$_} = $kohaStatusValue;
                           $s->{itemlost_on} = $affliction->{item_status_date};
                           $log->error($s->logId()." has affliction '$desc -> $_' but no 'item_status_date'?") unless ($affliction->{item_status_date}) }

      when('notforloan') { $s->{$_} = $kohaStatusValue }

      when('damaged')    { $s->{$_} = $kohaStatusValue }

      when('withdrawn')  { $s->{$_} = $kohaStatusValue;
                           $s->{withdrawn_on} = $affliction->{item_status_date};
                           $log->error($s->logId()." has affliction '$desc -> $_' but no 'item_status_date'?") unless ($affliction->{item_status_date}) }

      default { $log->error("Unhandled status '$kohaStatus' with value '$kohaStatusValue'"); }
    }
  }
}

return 1;
