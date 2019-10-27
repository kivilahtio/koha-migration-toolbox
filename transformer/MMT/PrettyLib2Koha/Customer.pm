package MMT::PrettyLib2Koha::Customer;
our $className = 'Customer';

use MMT::Pragmas;

#External modules
use Email::Valid;
use File::Basename;
use DateTime;

#Local modules
use MMT::Anonymize;
use MMT::Validator::Phone;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::PrettyLib2Koha::Customer - Transforms PrettyLib Customers to Koha Borrowers

=cut

my $SSN_EXPORT_FH;

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
  unless ($SSN_EXPORT_FH) {
    my $outputFilePrefix = File::Basename::basename($b->{outputFile});
    my $file = MMT::Config::kohaImportDir."/$outputFilePrefix.ssn.csv";
    open($SSN_EXPORT_FH, ">:encoding(UTF-8)", $file) or die("Couldn't open the ssn export file '$file' for writing: $!");
    $SSN_EXPORT_FH->autoflush(1);
  }

  #Trim leading/trailing whitespaces for all inputs
  $o->{$_} =~ s/(?:^\s+|\s+$)//gsm for keys %$o;

  $self->setKeys($o, $b, [['Id' => 'borrowernumber']]);
  $self->setCardnumber                       ($o, $b);
  $self->setBorrowernotes                    ($o, $b); #Set notes up here, so we can start appending notes regarding validation failures.
  #  \$self->setOpacnote
  #   \$self->setContactnote
  $self->set(Name           => 'surname',     $o, $b);
  $self->set(Name           => 'firstname',   $o, $b);
  $self->setTitle                            ($o, $b);
  $self->setOthernames                       ($o, $b);
  $self->setInitials                         ($o, $b);
  $self->setContactInfo                      ($o, $b);
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
  # \$self->setPhones
  #  \$self->setMobile
  #   \$self->setFax
  #    \$self->setPhonepro
  #     \$self->setSmsalertnumber
  $self->set(Email          => 'email',       $o, $b);
  #  \$self->setEmailpro
  $self->setDateofbirth                      ($o, $b);
  $self->setBranchcode                       ($o, $b);
  $self->setCategorycode                     ($o, $b);
  $self->setDateenrolled                     ($o, $b);
  $self->setDateexpiry                       ($o, $b);
  $self->setStatuses                         ($o, $b);
  #  \$self->setLost
  #   \$self->setDebarred
  #    \$self->setDebarredcomment
  #$self->setSex                              ($o, $b); #Sex is uninteresting for academic libraries
  $self->set(PIN            => 'password',    $o, $b);
  $self->setUserid                           ($o, $b);
  $self->setSort1                            ($o, $b);
  $self->setSort2                            ($o, $b);
  $self->setPrivacy                          ($o, $b);
  #  \$self->setPrivacy_guarantor_checkouts
  $self->setLang                             ($o, $b);

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

  #$self->set(institution_id => 'ssn',         $o, $b);

  $self->anonymize() if MMT::Config::anonymize();
}

sub id {
  return $_[0]->_id();
}
sub _id {
  return $_[0]->{borrowernumber};
}

sub logId($s) {
  if ($s->{cardnumber} && $s->{cardnumber} !~ /^TEMP/) {
    return $className.': cardnumber='.$s->{cardnumber};
  }
  elsif ($s->{borrowernumber}) {
    return $className.': borrowernumber='.$s->{borrowernumber};
  }
  else {
    return $className.': '.MMT::Validator::dumpObject($s);
  }
}

sub setCardnumber($s, $o, $b) {
  my $cardnumber = $o->{BarCode} if $o->{BarCode};

  if (not($cardnumber) || length($cardnumber) < 5) {
    my $error = (not($cardnumber)) ?        'No cardnumber' :
                (length($cardnumber) < 5) ? "Cardnumber '$cardnumber' too short" :
                                            'Unspecified error';

    if (MMT::Config::emptyBarcodePolicy() eq 'ERROR') {
      my $bc = $s->createBarcode();
      $log->error($s->logId()." - $error. Created cardnumber '$bc'.");
      $s->{cardnumber} = $bc;
    }
    elsif (MMT::Config::emptyBarcodePolicy() eq 'IGNORE') {
      $s->{cardnumber} = undef;
      #Ignore
    }
    elsif (MMT::Config::emptyBarcodePolicy() eq 'CREATE') {
      $s->{cardnumber} = $s->createBarcode();
    }
  }
  else {
    $s->{cardnumber} = $cardnumber;
  }
}
sub setBorrowernotes($s, $o, $b) {
  if ($o->{Note}) {
    my ($Note, $ssns) = MMT::Validator::filterSSNs($s, $o->{Note});
    $s->_exportSsn($_) for @$ssns;
    $s->concatenate($Note => 'borrowernotes');
  }
}
sub setFirstname($s, $o, $b) {

  my @names = split(/\s+/, $o->{Name});
  $s->{firstname} = join(' ', @names[1..($#names)]); #Slice the tail of @names
}
sub setSurname($s, $o, $b) {
  my @names = split(/\s+/, $o->{Name});
  $s->{surname} = $names[0];
}
sub setOthernames($s, $o, $b) { #This is actually the reservation alias in Koha-Suomi Koha.
  $s->{othernames} = $s->{surname}.', '.$s->{firstname};
}
sub setTitle($s, $o, $b) {
  #$s->{title} = $o->{title};
}
sub setInitials($s, $o, $b) {
  my @parts;
  push(@parts, split(/\s+|[,.-]+/, $s->{firstname})) if $s->{firstname};
  push(@parts, split(/\s+|[,.-]+/, $s->{surname})) if $s->{surname};
  $s->{initials} = join('.', map {uc substr($_, 0, 1)} @parts);
}
sub setDateenrolled($s, $o, $b) {
  $s->{dateenrolled} = $o->{SaveDate};
  unless ($s->{dateenrolled}) {
    $log->warn($s->logId()." - Is missing dateenrolled");
  }
}
sub setDateexpiry($s, $o, $b) {
  $s->{dateexpiry} = undef; #PrettyLib doesn't have the concept of expiration date for a Customer account
  unless ($s->{dateexpiry}) {
    if (MMT::Config::patronAddExpiryYears > 0) {
      my $expiry_date_if_not_none = DateTime->now()->add(
							 years => MMT::Config::patronAddExpiryYears,
							 days => int(rand(350)) # Don't expire all the same day
							)->ymd();
      $s->{dateexpiry} = $expiry_date_if_not_none;
      $log->info($s->logId()." - setting expiration to '$expiry_date_if_not_none'");
    } else {
      my $notification = "Missing expiration date, expiring now";
      $log->warn($s->logId()." - $notification");
      $s->concatenate($notification => 'borrowernotes');
    }
  }
}
sub setContactInfo($s, $o, $b) {
  my ($ok);
  my @priority = ($o->{bHomeAddress} eq 'true') ? ('HomeAddress', 'PostAddress') : ('PostAddress', 'HomeAddress'); # Gather via this priority table so this can be easily changed based on how PrettyLib has been used.
  my %addresses; $addresses{$_} = {} for @priority; #Gather all different types of PrettyLib-addresses here

  if ($o->{PostAddress}) {
    $addresses{PostAddress}{phone}   = $o->{Phone};
    $addresses{PostAddress}{address} = $o->{PostAddress};
    $addresses{PostAddress}{zipcode} = _extractZipcode(@_, 'PostCode') if $o->{PostCode};
    $addresses{PostAddress}{city}    = _extractCity(@_,    'PostCode') if $o->{PostCode};
  }

  if ($o->{HomeAddress}) {
    $addresses{HomeAddress}{phone}   = $o->{HomePhone};
    $addresses{HomeAddress}{address} = $o->{HomeAddress};
    $addresses{HomeAddress}{zipcode} = _extractZipcode(@_, 'HomeCode') if $o->{HomeCode};
    $addresses{HomeAddress}{city}    = _extractCity(@_,    'HomeCode') if $o->{HomeCode};
  }

  $s->{address}   = $addresses{$priority[0]}{address} // '';
  $s->{address2}  = join(', ', grep {$_} ($o->{Organization}, $o->{Department})) // '';
  $s->{zipcode}   = $addresses{$priority[0]}{zipcode} // '';
  $s->{city}      = $addresses{$priority[0]}{city} // '';
  ($s->{phone}, $ok)   = MMT::Validator::Phone::validate($s, $o, $b, $addresses{$priority[0]}{phone}) if $addresses{$priority[0]}{phone} && MMT::Validator::Phone::validate($s, $o, $b, $addresses{$priority[0]}{phone});
  $s->{B_address} = $addresses{$priority[1]}{address} if $addresses{$priority[1]}{address};
  $s->{B_zipcode} = $addresses{$priority[1]}{zipcode} if $addresses{$priority[1]}{zipcode};
  $s->{B_city}    = $addresses{$priority[1]}{city} if $addresses{$priority[1]}{city};
  ($s->{B_phone}, $ok) = MMT::Validator::Phone::validate($s, $o, $b, $addresses{$priority[1]}{phone}) if $addresses{$priority[1]}{phone};

  $s->{smsalertnumber} = ($s->{phone}   && MMT::Validator::Phone::phoneIsMobile($s->{phone}))   ? $s->{phone} :
                         ($s->{B_phone} && MMT::Validator::Phone::phoneIsMobile($s->{B_phone})) ? $s->{B_phone} :
                                                                                                  '';

  unless ($o->{PostAddress} || $o->{HomeAddress}) {
    $log->warn($s->logId()." - Has no address.");
  }
}
sub setEmail($s, $o, $b) {
  if ($o->{Email}) {
    if (Email::Valid->address($o->{Email})) {
      $s->{email} = $o->{Email};
    }
    else {
      my $msg = "Kirjastojärjestelmävaihdon yhteydessä havaittu epäselvä sähköpostiosoite '".$o->{Email}."' poistettu asiakastiedoistanne. Olkaa yhteydessä kirjastoonne.";
      $s->concatenate($msg => 'opacnote');
      $log->warn($s->logId()." - Has a bad email address '".$o->{Email}."'.");
    }
  }
  else {
    $log->warn($s->logId()." - Has no email.");
  }
}
sub setBranchcode($s, $o, $b) {
  if (MMT::Config::patronHomeLibrary) {
    $s->{branchcode} = MMT::Config::patronHomeLibrary;
  }
  else {
    $s->{branchcode} = $b->{Branchcodes}->translate(@_, $o->{Id_Library});
  }
  $log->fatal($s->logId().' - Missing branchcode!') unless ($s->{branchcode});
}
sub setCategorycode($s, $o, $b) {
  $s->{categorycode} = $b->{PatronCategorycode}->translate(@_, $o->{Id_Group});
}

my @dobParsers = (
  qr/\b(?<DAY>\d{1,2})\.(?<MON>\d{1,2})\.(?<YEAR>\d{2})\b/x,       # 10.5.86
  qr/\b(?<DAY>\d{1,2})\.(?<MON>\d{1,2})\.(?<YEAR>\d{4})\b/x,       # 4.12.1965
  qr/\b(?<DAY>\d{2})    (?<MON>\d{2})    (?<YEAR>\d{2})    (?<DIV>[-+A])    \d{3}\w\b/x, # a SSN 311298-111A
  qr/\b(?<DAY>\d{1,2})  (?<MON>\d{2})    (?<YEAR>\d{2})\b/x,             # 051255 or 51255
  qr/\b(?<DAY>\d{1,2})  (?<MON>\d{2})    (?<YEAR>\d{4})\b/x,             # 05121955 or 5121955
);
sub setDateofbirth($s, $o, $b) {
  my $dob = $o->{Birth}; #Copy the value to avoid mutating the original value during transformation which might fail
  unless ($dob) {
    $log->warn($s->logId().' - Missing date of birth');
    return undef;
  }
  $dob =~ s/\s//gsm; #Trim all whitespace

  my ($y,$m,$d);
  for my $parser (@dobParsers) {
    last if (($d,$m,$y) = $dob =~ $parser);
  }
  unless ($y && $m && $d) {
    $log->warn($s->logId()." - Unable to parse the date of birth from '$dob'");
    return undef;
  }

  $d = "0$d"  if length($d) == 1;
  $m = "0$m"  if length($m) == 1;
  if ($4) { #a SSN divisor is present
    $y = ($4 eq '+') ? "18$y" :
         ($4 eq '-') ? "19$y" :
         ($4 eq 'A') ? "20$y" :
         ($log->warn($s->logId()." - date of birth is inferred from SSN, but the divider component '$4' is atypical. Defaulting to the 20th century.")) ? "19$y" : "19$y"; #Now this might be considered a bit hacky :D
  }
  else {
    $y = "19$y" if length($y) == 2;
  }

  $s->{dateofbirth} = "$y-$m-$d"; #ISO8601
}
sub setUserid($s, $o, $b) {
  $s->{userid} = ($o->{Code}) ?  $o->{Code} :
                 ($s->{cardnumber} && $s->{cardnumber} !~ /^TEMP/) ? $s->{cardnumber} :
                 ($s->{email}) ? $s->{email} :
                                 $s->{borrowernumber};
}
sub setPassword($s, $o, $b) {
  #Having a PIN is in no way mandatory in PrettyLib, so let's not complain about that.
  #Just cleanly disable accounts without a password
  $s->{password} = $o->{PIN} || '!';
}
sub setSsn($s, $o, $b) {
  $s->{ssn} = $o->{institution_id}; #For some reason ssn is here
  if ($s->{ssn}) {
    if (eval { MMT::Validator::checkIsValidFinnishSSN($s->{ssn}) }) {
      if (MMT::Config::useHetula()) {
        $s->_exportSsn($s->{ssn});
        $s->{ssn} = 'via Hetula'; #This ssn is valid, and is transported to Hetula.
      }
      else {
        #We let the ssn pass on unhindered to Koha
      }
    }
    else {
      #HAMK-3339 - Leave non-valid ssns in Koha.
      my $notification = "SSN is not a valid Finnish SSN";
      $log->warn($s->logId()." - $notification - $@");

      $s->concatenate($notification => 'borrowernotes');
    }
  }
  else {
    $log->info($s->logId()."' has no ssn");
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
  # 2 - never save privacy information. Koha tries to save as little info as possible
  # 1 - Default
  # 0 - Gather and keep data about me! 
  if (not(defined($o->{LoanHistory}))) { # PrettyCirc Customers don't have a LoanHistory-column
    $s->{privacy} = 1;
  }
  elsif ($o->{LoanHistory} eq 'True') {
    $s->{privacy} = 1;
  }
  else {
    $s->{privacy} = 2;
  }
}
sub setLang($s, $o, $b) {
  $s->{lang} = 'fi';
}
sub setStatuses($s, $o, $b) {
  if ($o->{BlockDate}) {
    $s->_addManualDebarment($o->{BlockDate}, 'Tili estetty PrettyLib:ssä. Ota yhteyttä kirjastoosi.');
  }
}
sub setSort1($s, $o, $b) {
  my $groups = $b->{Groups}->get($o->{Id_Group});
  if ($groups) {
    $s->{sort1} = $groups->[0]->{Name};
  }
}
sub setSort2($s, $o, $b) {
  $s->{sort2} = $o->{Id};
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

sub _addPopUpNote($s, $b, $message, $branchcode=undef, $message_date=undef) {
  $log->logdie("Trying to add a popup note, but the message is missing") unless ($message);
  $branchcode = $b->{Branchcodes}->translate($s, {}, $b, '_DEFAULT_') unless ($branchcode);
  $log->logdie("Trying to add a popup note, but no branchcode given and a _DEFAULT_ branch is missing in Branchcodes translation table") unless ($branchcode);
  $message_date = $b->now() unless ($message_date);

  unless ($s->{popup_message}) { # Add a new note
    $s->{popup_message} = {
      message => $message,
      branchcode => $branchcode,
      message_date => $message_date,
    };
  }
  else { # merge with an existing one
    $s->{popup_message}->{message}     .= ' | '.$message;
    $s->{popup_message}->{branchcode}   = $branchcode unless ($s->{popup_message}->{branchcode});
    $s->{popup_message}->{message_date} = $message_date unless ($s->{popup_message}->{message_date});
  }
}

=head2 _exportSsn

Writes the given ssn and patron_id to the export file

=cut

sub _exportSsn($s, $ssn) {
  print $SSN_EXPORT_FH join(',', $s->id(), $s->{cardnumber}, $ssn)."\n";
}

sub _extractZipcode($s, $o, $b, $codeField) {
  # Try various heuristics
  if ($o->{$codeField} =~ m/
      (?:\D|\b)  #Zipcode might have bad delimiters, so extract it only if it is not a part of a bigger digit continuum
      (\d{5})    #This is the zipcode
      (?:\D|\b)  #Zipcode might be typoed, so extract it only if it is not a part of a bigger digit continuum
      /x) {
    return $1;
  }
  elsif ($o->{$codeField} =~ m/ # This special case is found with MFA
      ^
      (\d{3,5})  # leading zeroes have been lost in these cases
      (?:\D|\b)
      /x) {
    my $zipcode = $1;
    while (length($zipcode) < 5) { $zipcode = '0'.$zipcode; }
    return $zipcode;
  }
  else {
    $log->warn($s->logId()." - 'zipcode' cannot be extracted from '$codeField'-field '".$o->{$codeField}."'");
    return '';
  }
}
sub _extractCity($s, $o, $b, $cityField) {
  if ($o->{$cityField} =~ m/
      (?:\D|\b)  #City might have bad delimiters, so extract it only if it is not a part of a bigger word
      (\w{3,})   #This is the city, I presume
      (?:\D|\b)  #City might be typoed, so extract it only if it is not a part of a bigger word
      /x) {
    return $1;
  }
  else {
    $log->warn($s->logId()." - 'city' cannot be extracted from '$cityField'-field '".$o->{$cityField}."'");
    return '';
  }
}

=head2 anonymize

Anonymize the Customer-object

=cut

sub anonymize($s) {
  my @scramble = qw(userid cardnumber firstname surname othernames borrowernotes opacnote address address2 city zipcode email B_address B_city B_zipcode);
  for (@scramble) {
    $s->{$_} = MMT::Anonymize::scramble($s->{$_}) if $s->{$_};
  }

  $s->{phone}       = MMT::Anonymize::phone($s->{phone})   if $s->{phone};
  $s->{B_phone}     = MMT::Anonymize::phone($s->{B_phone}) if $s->{B_phone};
  $s->{dateofbirth} = $s->{dateofbirth}                    if $s->{dateofbirth};
  $s->{ssn}         = MMT::Anonymize::ssn($s->{ssn})       if $s->{ssn};
  $s->{password}    = MMT::Anonymize::scramble($s->{password}) if $s->{password} && $s->{password} ne '!';

#  $s->{firstname}     = $faker{faker}->person_first_name() if $s->{firstname};
#  $s->{surname}       = $faker{faker}->person_last_name()  if $s->{surname};
#  $s->{dateofbirth}   = $s->{dateofbirth}                  if $s->{dateofbirth};
#  $s->{borrowernotes} = MMT::Anonymize::scramble($s->{borrowernotes}) if $s->{borrowernotes};
#  $s->{opacnote}      = MMT::Anonymize::scramble($s->{opacnote}) if $s->{opacnote};
}

return 1;
