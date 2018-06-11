use 5.22.1;

package MMT::Patron;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';
use English;

#External modules
use YAML::XS;

#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);
use MMT::Date;
use MMT::Validator;
use MMT::Table::PatronCategorycode;

my @borrower_fields = qw /
  cardnumber        surname           firstname       title               othernames        initials           address            address2
  city              state             zipcode         country             email             phone              mobile             fax
  emailpro          phonepro          B_streetnumber  B_streettype        B_address         B_address2         B_city             B_state
  B_zipcode         B_country         B_email         B_phone             dateofbirth       branchcode         categorycode       dateenrolled
  dateexpiry        gonenoaddress     lost            debarred            contactname       contactfirstname   contacttitle       guarantorid
  borrowernotes     relationship      ethnicity       ethnotes            sex               flags              userid             opacnote
  contactnote       sort1             sort2           altcontactfirstname altcontactsurname altcontactaddress1 altcontactaddress2 altcontactaddress3
  altcontactzipcode altcontactcountry altcontactphone smsalertnumber      privacy
/;

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
  $self->setBorrowenumber                    ($o, $b);
  $self->setCardnumber                       ($o, $b);
  $self->setBranchcode                       ($o, $b);
  $self->setSort1                            ($o, $b);
  $self->setSort2                            ($o, $b);
  $self->setFirstname                        ($o, $b);
  $self->setSurname                          ($o, $b);
  $self->setDateenrolled                     ($o, $b);
  $self->setDateexpiry                       ($o, $b);
  $self->setAddresses                        ($o, $b);
  $self->setBranchcode                       ($o, $b);
  $self->setCategorycode                     ($o, $b);
  $self->setBorrowernotes                    ($o, $b);
  $self->setPhones                           ($o, $b);
  $self->setStatisticExtAttribute($o, $b);
  $self->setUserid                           ($o, $b);
  $self->setPassword                         ($o, $b);
}

sub id {
  return $_[0]->{patron_id};
}

=head2 toYaml
Serializes this object as a YAML list element
 @returns String pointer, to the YAML text.
=cut
sub toYaml {
  my $yaml = YAML::XS::Dump([$_[0]]);
  $yaml =~ s/^---.*$//gm;
  return \$yaml;
}

sub logId($s) {
  if ($s->{cardnumber}) {
    return 'Patron: cardnumber='.$s->{cardnumber};
  }
  elsif ($s->{patron_id}) {
    return 'Patron: patron_id='.$s->{patron_id};
  }
  else {
    return 'Patron: '.MMT::Validator::dumpObject($s);
  }
}

#Do not set borrowernumber here. Let Koha set it, link using barcode
sub setBorrowenumber($s, $o, $b) {
  unless ($o->{patron_id}) {
    die "\$DELETE: Patron is missing patron_id, DELETEing:\n".$s->toYaml();
  }
  $s->{patron_id} =      $o->{patron_id};
  $s->{borrowernumber} = $o->{patron_id};
}
sub setCardnumber($s, $o, $b) {
  my $patron_groups_barcodes = $b->groups()->get($s->{patron_id});
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
    $s->{cardnumber} = sprintf "TEMP%d",$s->{patron_id};
  }
}
sub setSort1($s, $o, $b) {
  $s->{sort1} = $o->{patron_id};
}
sub setSort2($s, $o, $b) {
  $s->{sort2} = $o->{institution_id};
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
    $s->{dateenrolled} = MMT::Date::translateDateDDMMMYY($o->{registration_date}, $s, 'registration_date->dateenrolled');
  }
  else {
    $s->{dateenrolled} = MMT::Date::translateDateDDMMMYY($o->{create_date}, $s, 'create_date->dateenrolled');
  }
}
sub setDateexpiry($s, $o, $b) {
  $s->{dateexpiry}   = MMT::Date::translateDateDDMMMYY($o->{expire_date}, $s, 'expire_date->dateexpiry');
}
sub setAddresses($s, $o, $b) {
  my $s->{patron_id} = $o->{patron_id};

  my $patronAddresses = $b->addresses()->get($s->{patron_id});
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
  $s->{branchcode} = $b->branchcodeTranslation()->translate(undef);
}
sub setCategorycode($s, $o, $b) {
  my $patron_groups_barcodes = $b->groups()->get($s->{patron_id});
  if ($patron_groups_barcodes) {
    foreach my $match (@$patron_groups_barcodes) {
      $s->{categorycode} = $match->{patron_group_id};
    }
  }
  else {
    #Try looking from the $patron_groups_barcodes_nulls-Cache first before giving up
    my $patron_groups_barcodes_nulls = $b->groups_nulls->get($s->{patron_id});
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
  $s->{categorycode} = $b->categorycodeTranslator()->translate( $s->{categorycode} );
}
sub setBorrowernotes($s, $o, $b) {
  my @sb;
  my $patron_notes = $b->notes()->get($s->{patron_id});
  if ($patron_notes) {
    foreach my $match(@$patron_notes) {
      push(@sb, ' | ') if (@sb > 0);
      if ($match->{note_type}) {
        if (my $noteType = $b->noteTypeTranslation()->translate($match->{note_type})) {
          push(@sb, $noteType.': ');
        }
      }
      push(@sb, $match->{note});
    }
  }
  $s->{borrowernotes} = join('', @sb);
}
sub setPhones($s, $o, $b) {
  my $patron_phones = $b->phones()->get($s->{patron_id});
  if ($patron_phones) {
    foreach my $match(@$patron_phones) {
      #Does the phone number match allowed Finnish phone numbers?
      unless ($match->{phone_number} =~ m/^((90[0-9]{3})?0|\+358\s?)(?!(100|20(0|2(0|[2-3])|9[8-9])|300|600|700|708|75(00[0-3]|(1|2)\d{2}|30[0-2]|32[0-2]|75[0-2]|98[0-2])))(4|50|10[1-9]|20(1|2(1|[4-9])|[3-9])|29|30[1-9]|71|73|75(00[3-9]|30[3-9]|32[3-9]|53[3-9]|83[3-9])|2|3|5|6|8|9|1[3-9])\s?(\d\s?){4,19}\d$/) {
        $log->warn("Finnish phone number validation failed for number '".$match->{phone_number}."' of '".$s->logId()."'");
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
        }
      }
    }
  }
  else {
    $log->warn("Patron '".$s->logId()."' has no phones.");
  }
}
sub setStatisticExtAttribute($s, $o, $b) {
  my $patron_statCats = $b->statisticalCategories()->get($s->{patron_id});
  if ($patron_statCats) {
    foreach my $match(@$patron_statCats) {
      if (my $statCat = $b->patronStatisticsTranslation->translate($match->{patron_stat_id})) {
        $s->_addExtendedPatronAttribute('statistic', $statCat, 'repeatable');
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