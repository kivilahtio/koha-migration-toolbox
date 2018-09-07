package MMT::Koha::Patron;

use MMT::Pragmas;

#External modules
use Email::Valid;

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::Koha::Patron - Transforms a bunch of Voyager data into a Koha borrower

=cut

=head2 new

Create the bare reference. Reference is needed to be returned to the builder, so we can do better post-mortem analysis for each die'd Patron.
build() later.

=cut

sub new {
  my ($class) = @_;
  my $self = bless({}, $class);
  return $self;
}

=head2 build

Flesh out the Koha-borrower -object out of the given
 @param1 Voyager data object
 @param2 Builder

=cut

sub build($self, $o, $b) {
  $self->setBorrowernumber                   ($o, $b);
  $self->setCardnumber                       ($o, $b);
  $self->setBorrowernotes                    ($o, $b); #Set notes up here, so we can start appending notes regarding validation failures.
  #  \$self->setOpacnote
  #   \$self->setContactnote
  $self->set(last_name      => 'surname',     $o, $b);
  $self->set(first_name     => 'firstname',   $o, $b);
  $self->set(institution_id => 'ssn',         $o, $b);
  $self->set(title          => 'title',       $o, $b);
  $self->set(middle_name    => 'othernames',  $o, $b);
  $self->setInitials                         ($o, $b);
  $self->setAddresses                        ($o, $b);
  #  \$self->setStreetnumber
  #   \$self->setStreettype
  #    \$self->setAddress
  #     \$self->setAddress2
  #      \$self->setCity
  #       \$self->setState
  #        \$self->setZipcode
  #         \$self->setCountry
  #          \$self->setB_streetnumber
  #           \$self->setB_streettype
  #            \$self->setB_address
  #             \$self->setB_address2
  #              \$self->setB_city
  #               \$self->setB_state
  #                \$self->setB_zipcode
  #                 \$self->setB_country
  $self->setEmail                            ($o, $b);
  #  \$self->setEmailpro
  $self->setPhones                           ($o, $b);
  #  \$self->setMobile
  #   \$self->setFax
  #    \$self->setPhonepro
  #     \$self->setSmsalertnumber
  $self->set(birth_date => 'dateofbirth',     $o, $b);
  $self->setBranchcode                       ($o, $b);
  $self->setCategorycode                     ($o, $b);
  $self->set(registration_date => 'dateenrolled', $o, $b);
  $self->set(expire_date => 'dateexpiry',     $o, $b);
  $self->setStatuses                         ($o, $b);
  #  \$self->setLost
  #   \$self->setDebarred
  #    \$self->setDebarredcomment
  #$self->setSex                              ($o, $b); #Sex is uninteresting for academic libraries
  $self->set(patron_pin => 'password',        $o, $b);
  $self->setUserid                           ($o, $b);
  $self->setSort1                            ($o, $b);
  $self->setSort2                            ($o, $b);
  $self->setPrivacy                          ($o, $b);
  #  \$self->setPrivacy_guarantor_checkouts
  $self->setLang                             ($o, $b);
  $self->setStatisticExtAttribute            ($o, $b);

  #$self->setAltcontactfirstname
  #$self->setAltcontactsurname
  #$self->setAltcontactaddress1
  #$self->setAltcontactaddress2
  #$self->setAltcontactaddress3
  #$self->setAltcontactstate
  #$self->setAltcontactzipcode
  #$self->setAltcontactcountry
  #$self->setAltcontactphone
  #$self->setB_email
  #$self->setB_phone
  #$self->setGonenoaddress
  #$self->setContactname
  #$self->setContactfirstname
  #$self->setContacttitle
  #$self->setGuarantorid
  #$self->setRelationship
  #$self->setSms_provider_id
  #$self->setCheckprevcheckout
  #$self->setUpdated_on                      #on update CURRENT_TIMESTAMP, automatically updated when migrated to Koha
  #$self->setLastseen
  #$self->setLogin_attempts
  #$self->setOverdrive_auth_token
}

sub id {
  return $_[0]->{borrowernumber};
}

sub logId($s) {
  if ($s->{cardnumber}) {
    return 'Patron: cardnumber='.$s->{cardnumber};
  }
  elsif ($s->{borrowernumber}) {
    return 'Patron: borrowernumber='.$s->{borrowernumber};
  }
  else {
    return 'Patron: '.MMT::Validator::dumpObject($s);
  }
}

#Do not set borrowernumber here. Let Koha set it, link using barcode
sub setBorrowernumber($s, $o, $b) {
  unless ($o->{patron_id}) {
    MMT::Exception::Delete->throw("Patron is missing patron_id ".MMT::Validator::dumpObject($o));
  }
  $s->{borrowernumber} = $o->{patron_id};
}
sub setCardnumber($s, $o, $b) {
  my $patronGroupsBarcodes = $b->{Barcodes}->get($s->{borrowernumber});
  if ($patronGroupsBarcodes) {

    if (scalar(@$patronGroupsBarcodes) > 1) {
      my @bcStatuses = map {$_->{patron_barcode}.'->'.$_->{barcode_status_desc}.'@'.$_->{barcode_status_date}} @$patronGroupsBarcodes;
      $log->warn($s->logId()." has multiple barcodes: '@bcStatuses'");
    }

    my $groupBarcode = $s->_getActiveOrLatestBarcodeRow($patronGroupsBarcodes);
    if (exists $groupBarcode->{patron_barcode}) {
      $s->{cardnumber} = $groupBarcode->{patron_barcode};
    }
    else {
      $log->logdie("Patron '".$s->logId()."' has a group/barcode/status -row, but it is missing the 'patron_barcode'-attribute. Is the extractor working as expected?");
    }
  }
  else {
    $log->warn("Patron '".$s->logId()."' has no cardnumber. Creating a temporary one.");
  }
  unless ($s->{cardnumber}) {
    $s->{cardnumber} = $s->createTemporaryBarcode();
  }
}
sub setBorrowernotes($s, $o, $b) {
  my @sb;
  my $patron_notes = $b->{notes}->get($s->{borrowernumber});
  if ($patron_notes) {
    foreach my $patronNote (@$patron_notes) {
      push(@sb, ' | ') if (@sb > 0);
      if ($patronNote->{note_type}) {
        if (my $noteType = $b->{NoteType}->translate(@_, $patronNote->{note_type})) {
          push(@sb, $noteType.': ');
        }
      }
      push(@sb, $patronNote->{note});
    }
  }
  $s->{borrowernotes} = join('', @sb);
}
sub setSort1($s, $o, $b) {
  $s->{sort1} = $o->{patron_id};
}
sub setSort2($s, $o, $b) {
  $s->{sort2} = ''; #ByWater scripts put $o->{institution_id} here, which has SSN in Finland;
}
sub setFirstname($s, $o, $b) {
  $s->{firstname}     = $o->{first_name};
  $s->{firstname}    .= ' '.$o->{middle_name} if ($o->{middle_name});
}
sub setSurname($s, $o, $b) {
  $s->{surname}       = $o->{last_name};
}
sub setOthernames($s, $o, $b) { #This is actually the reservation alias in Koha-Suomi Koha.
  $s->{othernames} = $s->{surname}.', '.$o->{first_name};
}
sub setTitle($s, $o, $b) {
  $s->{title} = $o->{title};
}
sub setInitials($s, $o, $b) {
  my @parts;
  push(@parts, $s->{firstname}) if $s->{firstname};
  push(@parts, $s->{othernames}) if $s->{othernames};
  push(@parts, $s->{surname}) if $s->{surname};
  $s->{initials} = join('.', map {uc substr($_, 0, 1)} @parts);
}
sub setDateenrolled($s, $o, $b) {
  if ($o->{registration_date}) { #registration_date might not always exists
    $s->{dateenrolled} = $o->{registration_date};
  }
  else {
    $s->{dateenrolled} = $o->{create_date};
  }
}
sub setDateexpiry($s, $o, $b) {
  $s->{dateexpiry}   = $o->{expire_date};
  unless ($s->{dateexpiry}) {
    my $notification = "Missing expiration date, expiring now";
    $log->warn($s->logId()." - $notification");
    $s->{borrowernotes} = ($s->{borrowernotes}) ? $s->{borrowernotes}.' | '.$notification : $notification;
  }
}
sub setAddresses($s, $o, $b) {
  my $patronAddresses = $b->{addresses}->get($s->{borrowernumber});
  if ($patronAddresses) {
    foreach my $match (@$patronAddresses) {
      if ($match->{address_desc} eq 'Permanent') {
        if ($match->{address_line3} ne ''
          || $match->{address_line4} ne ''
          || $match->{address_line5} ne '') {
          $s->{address}  = $match->{address_line1}.' '.$match->{address_line2};
          $s->{address2} = $match->{address_line3}.' '.$match->{address_line4}.' '.$match->{address_line5};
        }
        else {
          $s->{address}  = $match->{address_line1};
          $s->{address2} = $match->{address_line2};
        }
        $s->{city}    = $match->{city};
        $s->{state}   = $match->{state_province};
        $s->{zipcode} = $match->{zip_postal};
        $s->{country} = $match->{country};
      }
      elsif ($match->{address_desc} eq 'Temporary') {
        if ($match->{address_line3} ne ''
          || $match->{address_line4} ne ''
          || $match->{address_line5} ne '') {
          $s->{B_address}  = $match->{address_line1}.' '.$match->{address_line2};
          $s->{B_address2} = $match->{address_line3}.' '.$match->{address_line4}.' '.$match->{address_line5};
        }
        else {
          $s->{B_address}  = $match->{address_line1};
          $s->{B_address2} = $match->{address_line2};
        }
        $s->{B_city}    = $match->{city};
        $s->{B_state}   = $match->{state_province};
        $s->{B_zipcode} = $match->{zip_postal};
        $s->{B_country} = $match->{country};
      }
      elsif ($match->{address_desc} eq 'EMail') {
        #Email is dealt with in setEmail()
      }
      else {
        $log->error("Unknown Patron address_desc='".$match->{address_desc}."', address_type='".$match->{address_type}."'");
      }
    }
  }
  else {
    $log->warn("Patron '".$s->logId()."' has no address.");
  }
}
sub setEmail($s, $o, $b) {
  my $patronAddresses = $b->{addresses}->get($s->{borrowernumber});
  if ($patronAddresses) {
    for my $address (@$patronAddresses) {
       if ($address->{address_desc} eq 'EMail') { #Yes. It is written 'EMail'
        $log->logdie("Patron addresses row is missing column 'address_line1'. Extractor should always supply it.") unless (exists $address->{address_line1});
        my $emailCandidate = $address->{address_line1};
        unless ($emailCandidate) {
          $log->warn($s->logId()." has an address-row with type 'EMail', but the email address is empty?");
          next;
        }
        if (Email::Valid->address($emailCandidate)) {
          $s->{email} = $emailCandidate;
        }
        else {
          my $msg = "Kirjastojärjestelmävaihdon yhteydessä havaittu epäselvä sähköpostiosoite '$emailCandidate' poistettu asiakastiedoistanne. Olkaa yhteydessä kirjastoonne.";
          $s->{opacnote} = ($s->{opacnote}) ? $s->{opacnote}.' | '.$msg : $msg;
          $log->warn($s->logId()." has a bad email address '$emailCandidate'.");
        }
        last;
      }
    }
  }

  $log->warn($s->logId()." has no email.") unless $s->{email};
}
sub setBranchcode($s, $o, $b) {
  my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{home_location});
  $s->{branchcode} = $branchcodeLocation->{branch};
  return if $s->{branchcode};

  $s->{branchcode} = $b->{Branchcodes}->translate(@_, '_DEFAULT_'); #Waiting for https://tiketti.koha-suomi.fi:83/issues/3265
}
sub setCategorycode($s, $o, $b) {
  my $patronGroupsBarcodes = $b->{Barcodes}->get($s->{borrowernumber});
  if ($patronGroupsBarcodes) {
    my $groupBarcode = $s->_getActiveOrLatestBarcodeRow($patronGroupsBarcodes);
    if (exists $groupBarcode->{patron_group_id}) {
      $s->{categorycode} = $groupBarcode->{patron_group_id};
    }
    else {
      $log->fatal("Patron '".$s->logId()."' has a group/barcode/status -row, but it is missing the 'patron_group_id'-attribute. Is the extractor working as expected?");
    }
  }

  if (! $s->{categorycode}) {
    ##TODO How to get categorycode then?
    $log->warn("Patron '".$s->logId()."' has no categorycode?");
    $s->{categorycode} = 'UNKNOWN';
  }
  $s->{categorycode} = $b->{PatronCategorycode}->translate(@_, $s->{categorycode});
}
sub setPhones($s, $o, $b) {
  my $patron_phones = $b->{phones}->get($s->{borrowernumber});
  if ($patron_phones) {
    foreach my $match(@$patron_phones) {
      unless (MMT::Validator::checkIsValidFinnishPhoneNumber($match->{phone_number})) {
        my $notification = "Finnish phone number validation failed for number '".$match->{phone_number}."'";
        $log->warn($s->logId()." - $notification");
        $s->{borrowernotes} = ($s->{borrowernotes}) ? $s->{borrowernotes}.' | '.$notification : $notification;
        return undef;
      }
      given ($match->{phone_desc}) {
        when ('Primary') {
          $s->{phone} = $match->{phone_number};
        }
        when ('Other') {
          $s->{phonepro} = $match->{phone_number};
        }
        when ('Fax') {
          $s->{fax} = $match->{phone_number};
        }
        when ('Mobile') {
          $s->{mobile} = $match->{phone_number};
          $s->{smsalertnumber} = $match->{phone_number};
        }
      }
    }
  }
  else {
    $log->warn("Patron '".$s->logId()."' has no phones.");
  }
}
my $re_ssnToDob = qr/^(\d\d)(\d\d)(\d\d)([-+A])/;
sub setDateofbirth($s, $o, $b) {
  $s->{dateofbirth} = $o->{birth_date};
  if (not($s->{dateofbirth}) && $s->{ssn}) { #Try to get dob from ssn
    unless ($s->{ssn} =~ $re_ssnToDob) {
      $log->error($s->logId()." making the date of birth from ssn failed, because the ssn '".$s->{ssn}."' is unparseable");
      return undef;
    }
    my $year = ($4 eq 'A') ? "20$3" : "19$3";
    $s->{dateofbirth} = "$year-$2-$1";
  }
  if (not($s->{dateofbirth}) && $s->{ssn}) {
    $log->warn("Patron '".$s->logId()."' has no dateofbirth and it couldn't be salvaged from the ssn.");
  }
}
sub setStatisticExtAttribute($s, $o, $b) {
  my $patron_statCats = $b->{statisticalCategories}->get($s->{borrowernumber});
  if ($patron_statCats) {
    foreach my $match(@$patron_statCats) {
      if (my $statCat = $b->{PatronStatistics}->translate(@_, $match->{patron_stat_id})) {
        $s->_addExtendedPatronAttribute('STAT_CAT', $statCat, 'repeatable');
      }
    }
  }
  else {
    $log->warn("Patron '".$s->logId()."' has no statistical category.");
  }
}
sub setUserid($s, $o, $b) {
  $s->{userid} = $s->{cardnumber};
}
sub setPassword($s, $o, $b) {
  $s->{password} = $o->{patron_pin};
  unless ($s->{password}) {
    $log->debug($s->logId()."' has no password. Account will be active in Koha, but cannot login.");
    my $msg = "Kirjastojärjestelmävaihdoksessa havaittu että tililtänne puuttuu salasana. Tilinne on vielä aktiivinen, mutta mitään tunnistautumista vaativa ei voi tehdä.";
    $s->{opacnote} = ($s->{opacnote}) ? $s->{opacnote}.' | '.$msg : $msg;
  }
}
sub setSsn($s, $o, $b) {
  $s->{ssn} = $o->{institution_id}; #For some reason ssn is here
  if ($s->{ssn}) {
    unless (MMT::Validator::checkIsValidFinnishSSN($s->{ssn})) {
      my $notification = "SSN is not a valid Finnish SSN";
      $log->warn("Patron '".$s->logId()."' $notification");

      $s->{borrowernotes} = ($s->{borrowernotes}) ? $s->{borrowernotes}.' | '.$notification : $notification;
    }
  }
  else {
    $log->info("Patron '".$s->logId()."' has no ssn");
  }
}
sub setSex($s, $o, $b) {
  $s->{sex} = 'O';
  if ($o->{institution_id} && $o->{institution_id} =~ /^\d\d\d\d\d\d.\d\d(\d)/) { #This can be a loose match. Atleast we get some interesting results with bad data.
    if ($1 % 2 == 0) { $s->{sex} = 'M' }
    else             { $s->{sex} = 'F' }
  }
}
sub setPrivacy($s, $o, $b) {
  $s->{privacy} = 1;
  # 2 - never save privacy information. Koha tries to save as little info as possible
  # 1 - Default
  # 0 - Gather and keep data about me! 
}
sub setLang($s, $o, $b) {
  $s->{lang} = 'fi';
}
sub setStatuses($s, $o, $b) {
  my $patronGroupsBarcodes = $b->{Barcodes}->get($s->{borrowernumber});
  if ($patronGroupsBarcodes) {
    my $groupBarcode = $s->_getActiveOrLatestBarcodeRow($patronGroupsBarcodes);
    given ($groupBarcode->{barcode_status_desc}) {
      when('Active')  {  } #This is ok, no special statuses
      when('Lost')    { $s->{lost} = 1 } #Patron is lost
      when('Stolen')  { $s->{lost} = 1 } #Patron has been kidnapped!
      when('Expired') {
        #This specifically means that the library card has expired, not the patron's library account. It is possible for the Patron to have no active library card.
        unless ($s->{dateexpiry} eq $groupBarcode->{barcode_status_date}) {
          $log->warn($s->logId()." has an expired library card, but the Patron account expiration date '".$s->{dateexpiry}."' is different from when the status has been given '".$groupBarcode->{barcode_status_date}."'?");
        }
        #There is no special expired-field in Koha, simply the dateexpiry-column is past the expiration date.
      }
      when('Other')   {
        $s->_addManualDebarment($groupBarcode->{barcode_status_date}, "Barcode status in Voyager '".$groupBarcode->{barcode_status_desc}."'");
        $log->debug($s->logId()." has a debarment.");
      }
    }
    if (exists $groupBarcode->{barcode_status_desc}) {
      $s->{categorycode} = $groupBarcode->{patron_group_id};
    }
    else {
      $log->fatal("Patron '".$s->logId()."' has a group/barcode/status -row, but it is missing the 'patron_group_id'-attribute. Is the extractor working as expected?");
    }
  }

  if (! $s->{categorycode}) {
    ##TODO How to get categorycode then?
    $log->warn("Patron '".$s->logId()."' has no categorycode?");
    $s->{categorycode} = 'UNKNOWN';
  }
  $s->{categorycode} = $b->{PatronCategorycode}->translate(@_, $s->{categorycode});
}

sub _addExtendedPatronAttribute($s, $attributeName, $val, $isRepeatable) {
  my $existingValue = $s->{ExtendedPatronAttributes}->{$attributeName};
  if (not(defined($existingValue))) {
    $s->{ExtendedPatronAttributes}->{$attributeName} = [$val];
  }
  elsif (defined($existingValue) && not($isRepeatable)) {
    $log->warn("ExtendedPatronAttribute '$attributeName' is overwritten for '".$s->logId()."', old value '$existingValue', new value '$val'");
    $s->{ExtendedPatronAttributes}->{$attributeName}->[0] = $val;
  }
  elsif (defined($existingValue) && $isRepeatable) {
    push(@$existingValue, $val);
  }
}

=head2 _addManualDebarment

This prevents the Patron from using his/her library accoutn in Koha.

=cut

sub _addManualDebarment($s, $date, $message) {
  $s->{debarments} = [] unless ($s->{debarments});
  push(@{$s->{debarments}}, {created => $date, comment => $message});
}

sub _getActiveOrLatestBarcodeRow($s, $patronGroupsBarcodes) {
  for my $pgb (@$patronGroupsBarcodes) {
    $log->logdie("Repository 'Barcodes' has DB a row '".MMT::Validator::dumpObject($pgb)."' with no column 'barcode_status_desc'. Is the extractor selecting the correct columns?") unless (exists $pgb->{barcode_status_desc});

    if ($pgb->{barcode_status_desc} eq 'Active') {
      unless ($pgb->{patron_barcode}) {
        $log->error($s->logId()." has an 'Active' library card, but the barcode doesn't exist?");
      }
      else {
        return $pgb;
      }
    }
  }
  return $patronGroupsBarcodes->[0]; #Extractor should ORDER BY so the newest entry is first.
}

return 1;