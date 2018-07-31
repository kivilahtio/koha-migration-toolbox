use 5.22.1;

package MMT::Koha::Patron;
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
use MMT::TranslationTable::PatronCategorycode;

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
  $self->setSurname                          ($o, $b);
  $self->setFirstname                        ($o, $b);
  $self->setSsn                              ($o, $b);
  #$self->setTitle                           ($o, $b);
  #$self->setOthernames                      ($o, $b);
  #$self->setInitials                        ($o, $b);
  $self->setAddresses                        ($o, $b);
  #  \$self->setStreetnumber                  ($o, $b);
  #   \$self->setStreettype                    ($o, $b);
  #    \$self->setAddress                       ($o, $b);
  #     \$self->setAddress2                      ($o, $b);
  #      \$self->setCity                          ($o, $b);
  #       \$self->setState                         ($o, $b);
  #        \$self->setZipcode                       ($o, $b);
  #         \$self->setCountry                       ($o, $b);
  #$self->setAltcontactfirstname($o, $b);
  #$self->setAltcontactsurname($o, $b);
  #$self->setAltcontactaddress1($o, $b);
  #$self->setAltcontactaddress2($o, $b);
  #$self->setAltcontactaddress3($o, $b);
  #$self->setAltcontactstate($o, $b);
  #$self->setAltcontactzipcode($o, $b);
  #$self->setAltcontactcountry($o, $b);
  #$self->setAltcontactphone($o, $b);
  #$self->setB_streetnumber($o, $b);
  #$self->setB_streettype($o, $b);
  #$self->setB_address($o, $b);
  #$self->setB_address2($o, $b);
  #$self->setB_city($o, $b);
  #$self->setB_state($o, $b);
  #$self->setB_zipcode($o, $b);
  #$self->setB_country($o, $b);
  #$self->setB_email($o, $b);
  #$self->setB_phone($o, $b);
  #$self->setEmail                           ($o, $b);
  #  \$self->setEmailpro                      ($o, $b);
  $self->setPhones                           ($o, $b);
  #  \$self->setMobile                        ($o, $b);
  #   \$self->setFax                           ($o, $b);
  #    \$self->setPhonepro                      ($o, $b);
  #     \$self->setSmsalertnumber                ($o, $b);
  $self->setDateofbirth($o, $b);
  $self->setBranchcode($o, $b);
  $self->setCategorycode($o, $b);
  $self->setDateenrolled($o, $b);
  $self->setDateexpiry($o, $b);
  #$self->setGonenoaddress($o, $b);
  #$self->setLost($o, $b);
  #$self->setDebarred($o, $b);
  #$self->setDebarredcomment($o, $b);
  #$self->setContactname($o, $b);
  #$self->setContactfirstname($o, $b);
  #$self->setContacttitle($o, $b);
  #$self->setGuarantorid($o, $b);
  #$self->setRelationship($o, $b);
  #$self->setSex($o, $b);
  $self->setPassword($o, $b);
  $self->setUserid($o, $b);
  #$self->setOpacnote($o, $b);
  #$self->setContactnote($o, $b);
  $self->setSort1($o, $b);
  $self->setSort2($o, $b);
  #$self->setSms_provider_id($o, $b);
  $self->setPrivacy                          ($o, $b);
  #  \$self->setPrivacy_guarantor_checkouts   ($o, $b);
  #$self->setCheckprevcheckout($o, $b);
  #$self->setUpdated_on($o, $b);
  #$self->setLastseen($o, $b);
  $self->setLang                             ($o, $b);
  #$self->setLogin_attempts($o, $b);
  #$self->setOverdrive_auth_token($o, $b);
  $self->setStatisticExtAttribute            ($o, $b);
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
  my $patron_groups_barcodes = $b->{groups}->get($s->{borrowernumber});
  if ($patron_groups_barcodes) {
    foreach my $match (@$patron_groups_barcodes) {

      $s->{cardnumber} = $match->{patron_barcode};

      if ($match->{barcode_status} eq '') {
        $match->{barcode_status} = 0;
      }
      if ($match->{barcode_status} != 1) {
        $s->{lost} = 1;
      }
    }
  }
  else {
    $log->warn("Patron '".$s->logId()."' has no cardnumber.");
  }
  unless ($s->{cardnumber}) {
    $s->{cardnumber} = $s->createTemporaryBarcode();
  }
}
sub setBorrowernotes($s, $o, $b) {
  my @sb;
  my $patron_notes = $b->{notes}->get($s->{borrowernumber});
  if ($patron_notes) {
    foreach my $match(@$patron_notes) {
      push(@sb, ' | ') if (@sb > 0);
      if ($match->{note_type}) {
        if (my $noteType = $b->{NoteType}->translate(@_, $match->{note_type})) {
          push(@sb, $noteType.': ');
        }
      }
      push(@sb, $match->{note});
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
  $s->{firstname}    .= $o->{middle_name} ne '' ? ' '.$o->{middle_name} : '';
}
sub setSurname($s, $o, $b) {
  $s->{surname}       = $o->{last_name};
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
      if ($match->{address_type} == 1) {
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
      elsif ($match->{address_type} == 2) {
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
      elsif ($match->{address_type} == 3) {
        $s->{email} = $match->{address_line1};
      }
    }
  }
  else {
    $log->warn("Patron '".$s->logId()."' has no address.");
  }
}
sub setBranchcode($s, $o, $b) {
  $s->{branchcode} = $b->{Branchcodes}->translate(@_, '_DEFAULT_');
}
sub setCategorycode($s, $o, $b) {
  my $patron_groups_barcodes = $b->{groups}->get($s->{borrowernumber});
  if ($patron_groups_barcodes) {
    foreach my $match (@$patron_groups_barcodes) {
      $s->{categorycode} = $match->{patron_group_id};
    }
  }
  else {
    #Try looking from the $patron_groups_barcodes_nulls-Cache first before giving up
    my $patron_groups_barcodes_nulls = $b->{groups_nulls}->get($s->{borrowernumber});
    if ($patron_groups_barcodes_nulls) {
      foreach my $match (@$patron_groups_barcodes_nulls) {
        if ($match->{barcode_status} eq '') {
          $match->{barcode_status} = 0;
        }
        next if ($match->{barcode_status} != 1);
        $s->{categorycode} = $match->{patron_group_id};
      }
    }
    else {
      $log->warn("Patron '".$s->logId()."' has no categorycode.");
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
    $s->{ssn} =~ $re_ssnToDob;
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
    $s->{password} = substr($s->{cardnumber}, -4);
    $log->info("Patron '".$s->logId()."' has no password, using last 4 digits of the cardnumber");
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
sub setPrivacy($s, $o, $b) {
  $s->{privacy} = 1;
  # 2 - never save privacy information. Koha tries to save as little info as possible
  # 1 - Default
  # 0 - Gather and keep data about me! 
}
sub setLang($s, $o, $b) {
  $s->{lang} = 'fi';
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

return 1;