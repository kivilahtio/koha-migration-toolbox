package MMT::PrettyLib2Koha::Item;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::Validator;
use MMT::Validator::Money;
use MMT::Validator::Barcode;
use MMT::PrettyLib2Koha::Biblio;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::PrettyLib2Koha::Item - Transforms a bunch of PrettyLib data into a Koha item

=cut

=head2 build

 @param1 PrettyLib data object
 @param2 Builder

=cut

sub build($self, $o, $b) {
  $self->setKeys($o, $b, [['Id' => 'itemnumber'], ['Id_Title' => 'biblionumber']]);

  $self->set(BarCode              => 'barcode',            $o, $b);
  $self->set(SaveDate             => 'dateaccessioned',    $o, $b);
  $self->set(Id_Library           => 'homebranch',         $o, $b);
  $self->set(Price                => 'price',              $o, $b);
  $self->set(Id                   => 'datelastborrowed',   $o, $b);
  $self->setDatelastseen                                  ($o, $b);
  $self->setStatuses                                      ($o, $b);
  #  \$self->setNotforloan
  #   \$self->setDamaged
  #    \$self->setItemlost
  #     \$self->setItemlost_on
  #      \$self->setWithdrawn
  #       \$self->setWithdrawn_on
  $self->set(Id_Shelf             => 'itemcallnumber',     $o, $b);
  $self->set(Id                   => 'issues',             $o, $b);
  $self->set(Note                 => 'itemnotes',          $o, $b);
  #  \$self->setItemnotes_nonpublic
  $self->setItype(                                         $o, $b);
  $self->set(Id_Library           => 'holdingbranch',      $o, $b);
  $self->set(Id_Location          => 'permanent_location', $o, $b);
  #  \$self->setCcode                                         ($o, $b);
  $self->set(Id_Location          => 'location',           $o, $b);
  #$self->set(Id_Location          => 'sub_location',       $o, $b);
  #$self->set(???                  => 'enumchron',          $o, $b);
  #$self->set(? => datereceived, $o, $b);
  $self->set(Id_Supplier          => 'booksellerid',       $o, $b);
  $self->set(Price                => 'replacementprice',   $o, $b);
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
sub _id {
  return $_[0]->{itemnumber};
}

sub logId($s) {
  return 'Item: '.$s->id();
}

sub setBarcode($s, $o, $b) {
  my ($bc, $ok);

  MMT::Exception::Delete->throw($s->logId()." - No BarCode-key?")
    unless exists($o->{BarCode});
  MMT::Exception::Delete->throw($s->logId()." - No AcqNum-key?")
    unless exists($o->{AcqNum});

  if (MMT::Config::pl_barcodeFromAcqNumber()) {
    my $acqNum = $o->{AcqNum};
    $acqNum =~ s/\s//gsm if $acqNum; #Trim all whitespace
    $bc = $acqNum if $acqNum;
    $bc = $o->{BarCode} unless $acqNum;
  }
  else {
    $bc = $o->{BarCode} if $o->{BarCode};
  }

  ($bc, $ok) = MMT::Validator::Barcode::validate(@_, $bc);
  $s->{barcode} = $bc;

  my $error;
  if (not($ok) || not($s->{barcode})) {
    $error = (not($s->{barcode})) ?        'No barcode' :
             (not($ok)) ?                  'Validation error' :
                                           'Unspecified error';
  }
  elsif (length($s->{barcode}) < MMT::Config::barcodeMinLength()) {
    $error = 'Barcode too short';
  }
  elsif (length($s->{barcode}) > 20) { #koha.items.barcode max length is 20 characters
    $error = 'Barcode too long. Max length 20 characters';
  }
  if ($error) {
    my $msg = $s->logId()."' has invalid barcode='".($s->{barcode} // 'undef')."'. $error.";
    if (MMT::Config::emptyBarcodePolicy() eq 'ERROR') {
      MMT::Exception::Delete->throw($msg);
    }
    elsif (MMT::Config::emptyBarcodePolicy() eq 'IGNORE') {
      $log->error($msg) if ($s->{barcode});
      $s->{barcode} = undef;
      #Ignore
    }
    elsif (MMT::Config::emptyBarcodePolicy() eq 'CREATE') {
      my $newBc = $s->createBarcode();
      $log->error("$msg Created barcode '$newBc'.");
      $s->{barcode} = $newBc;
    }
  }
}
sub setDateaccessioned($s, $o, $b) {
  $s->{dateaccessioned} = MMT::Validator::parseDate($o->{SaveDate});

  unless ($s->{dateaccessioned}) {
    $log->warn($s->logId()."' has no dateaccessioned.");
  }
}
sub setPrice($s, $o, $b) {
  $s->{price} = ($o->{Price}) ? MMT::Validator::Money::replacementPrice(@_, $o->{Price}) : undef;
  #$log->warn($s->logId()."' has no price.") unless $s->{price}; #Too much complaining about the missing price. Hides all other issues.
}
sub setReplacementprice($s, $o, $b) {
  # Use the Item's price as a basis
  $s->{replacementprice} = $s->{price};
  unless ($s->{replacementprice}) {
    #If the Item doesn't have a price, look for the parent biblio
    my $titles = $b->{Title}->get($o->{Id_Title});
    $s->{replacementprice} = $titles->[0]->{Price} if @$titles;
  }
  #finally use the default replacement price.
  $s->{replacementprice} = MMT::Config::defaultReplacementPrice() unless $s->{replacementprice};
}
sub setDatelastborrowed($s, $o, $b) {
  my $loans = $b->{LoanByItem}->get($o->{Id}); # The Loan-rows are ordered from oldest to newest
  if ($loans) {
    $s->{datelastborrowed} = MMT::Validator::parseDate($loans->[-1]->{LoanDate});
  }
  #It is ok for the Item to not have datelastborrowed
}
sub setDatelastseen($s, $o, $b) {
  if ($s->{datelastborrowed}) {
    $s->{datelastseen} = $s->{datelastborrowed};
  }
  #It is ok for the Item to not have datelastborrowed
}
sub setItemcallnumber($s, $o, $b) {
  my $shelves = $b->{Shelf}->get($o->{Id_Shelf});
  if ($shelves) {
    my $plShelfFilter = MMT::Config::pl_shelf_filter();
    if ($plShelfFilter && not($shelves->[0]->{Class} =~ /$plShelfFilter/)) {
      $s->{itemcallnumber} = $shelves->[0]->{Class};
    }
    else {
      $log->debug($s->logId()." itemcallnumber '".$shelves->[0]->{Class}."' filtered. Id_Shelf=".$o->{Id_Shelf});
    }
  }

  unless ($s->{itemcallnumber}) {
    $log->warn($s->logId()." has no itemcallnumber! Id_Shelf=".$o->{Id_Shelf});
  }
}
sub setIssues($s, $o, $b) {
  my $loans = $b->{LoanByItem}->get($o->{Id}); # The Loan-rows are ordered from oldest to newest
  if ($loans) {
    $s->{issues} = scalar(@$loans);
  }
  else {
    $s->{issues} = 0;
  }
}
sub setItemnotes($s, $o, $b) {
  $s->{itemnotes_nonpublic} = $o->{Note} || '';
}
sub setHomebranch($s, $o, $b) {
  my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{Id_Location});
  $s->{homebranch} = $branchcodeLocation->{branch} if ($branchcodeLocation && $branchcodeLocation->{branch});

  $s->{homebranch} = $b->{Branchcodes}->translate(@_, $o->{Id_Library}) unless ($s->{homebranch});

  unless ($s->{homebranch}) {
    MMT::Exception::Delete->throw($s->logId()."' has no homebranch! Id_Library=".$o->{Id_Library}.". Define a default in the LocationId translation table!");
  }
}
sub setHoldingbranch($s, $o, $b) {
  $s->{holdingbranch} = $s->{homebranch};
}
sub setPermanent_location($s, $o, $b) {
  if (ref($s) eq 'MMT::PrettyLib2Koha::Item') {
    my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{Id_Location});
    $s->{permanent_location} = $branchcodeLocation->{location};
    $s->{ccode} = $branchcodeLocation->{collectionCode} if $branchcodeLocation->{collectionCode};
    $s->{sub_location} = $branchcodeLocation->{sub_location} if $branchcodeLocation->{sub_location};
  }
  elsif (ref($s) eq 'MMT::PrettyCirc2Koha::Item') {
    # In PrettyCirc the location might be in the CircleStorage (Holdings) -table's Notes-column
    if (my $holdings = $b->{CircleStorage}->get($o->{Id_Title})) {
      my $h = $holdings->[0];
      my $branchcodeLocation = $b->{LocationId}->translate(@_, $h->{Notes});
      if ($branchcodeLocation->{location} eq 'KONVERSIO') {
        $log->warn("PrettyCirc subscription location '".$h->{Notes}."' is not found in the PrettyLib locations lists.")
      }
      $s->{permanent_location} = 'CIRC-'.($branchcodeLocation->{location} || '');
      $s->{ccode} = $branchcodeLocation->{collectionCode} if $branchcodeLocation->{collectionCode};
      $s->{sub_location} = $branchcodeLocation->{sub_location} if $branchcodeLocation->{sub_location};
    }
  }
  else {
    MMT::Exception::Delete->throw($s->logId().' - Unknown Item class, cannot decide if it is coming from PrettyLib or PrettyCirc');    
  }

  unless ($s->{permanent_location}) {
    MMT::Exception::Delete->throw($s->logId().' - Missing Id_Location|permanent_location! Set a translation table default!');
  }
}
sub setLocation($s, $o, $b) {
  $s->{location} = $s->{permanent_location};
}
#sub setSub_location($s, $o, $b) {
#  my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{Id_Location});
#  $s->{sub_location} = $branchcodeLocation->{sub_location} if $branchcodeLocation->{sub_location};
#}
sub setItype($s, $o, $b) {
  $s->{itype} = MMT::PrettyLib2Koha::Biblio::getItemType(@_);

  unless ($s->{itype}) {
    MMT::Exception::Delete->throw($s->logId()."' has no default itype!");
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
  return unless ($kohaStatCat && $kohaStatCat ne '');

  if ($s->{ccode}) {
    $log->warn($s->logId()." has collection code '".$s->{ccode}."' (from the LocationId translation table) and an incoming statistical category '$statCat->$kohaStatCat', but in Koha we can only have one collection code. Ignoring the incoming '$statCat->$kohaStatCat'.");
    return;
  }
  else {
    $s->{ccode} = $kohaStatCat;
  }
}
sub setBooksellerid($s, $o, $b) {
  my $suppliers = $b->{Suppliers}->get( $o->{Id_Supplier} );
  unless ($suppliers) {
    return;
  }
  my $supplier = $suppliers->[0];

  $s->{booksellerid} = ($supplier->{Name} || 'NO-NAME').' ('.($supplier->{Code} || 'NO-CODE').')';
  $s->{booksellerid} = MMT::PrettyLib2Koha::Biblio::_ss( $s->{booksellerid} );
  $s->{booksellerid} =~ s/\s{2,}/ /gsm;
}

my %statusMap = (
  '' => 'KONVERSIO',
  0  => 'Keskeneräinen',
  1  => 'Ehdotus',
  2  => 'Lähettämätön tilaus',
  3  => 'Tilaus',
  4  => 'Tilaus',
  5  => 'Saapunut',
  6  => 'Poimittu',
  7  => 'Luetteloimaton',
  8  => 'Kadonnut',
  9  => 'Huollossa',
  10 => 'Luetteloitu',
  11 => 'Huoltoon tulossa',
  12 => 'Kuljetettavana',
  13 => 'Myytävä',
  14 => 'Poistettu',
  15 => 'Tilaus peruttu',
  16 => 'Tiedustelu',
);
sub setStatuses($s, $o, $b) {
  my $S = $o->{Status};

  if ($S eq '') {
    $s->{itemnotes} .= " | Unexpected status '$statusMap{$S}'";
  }

  #0;Keskeneräinen
  #1;Ehdotus
  elsif ($S == 0 || $S == 1) {
    $s->{itemnotes} .= " | Unexpected status '$statusMap{$S}'";
  }

  #2;Lähettämätön tilaus
  #3;Tilaus
  #4;Tilaus
  #5;Saapunut
  elsif ($S == 2 || $S == 3 || $S == 4 || $S == 5) {
    $s->{notforloan} = -1;
  }

  #6;Poimittu
  #7;Luetteloimaton
  elsif ($S == 6 || $S == 7) {
    $s->{itemnotes} .= " | Unexpected status '$statusMap{$S}'";
  }

  #8;Kadonnut
  elsif ($S == 8) {
    $s->{itemlost} = 1;
  }

  #9;Huollossa
  #11;Huoltoon tulossa
  elsif ($S == 9 || $S == 11) {
    $s->{damaged} = 1;
  }
  #10;Luetteloitu
  elsif ($S == 10) {
    # This is expected
  }

  #12;Kuljetettavana
  #13;Myytävä
  #14;Poistettu
  #15;Tilaus peruttu
  #16;Tiedustelu
  elsif ($S == 12 || $S == 13 || $S == 14 || $S == 15 || $S == 16) {
    $s->{itemnotes} .= " | Unexpected status '$statusMap{$S}'";
  }

  else {
    $log->error($s->logId." - Unhandled status '$statusMap{$S}'");
  }
}

return 1;
