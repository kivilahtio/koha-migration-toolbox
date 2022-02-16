package Bulk::PatronImporter;

#Pragmas
use Modern::Perl;
use experimental 'smartmatch', 'signatures';
binmode( STDOUT, ":encoding(UTF-8)" );
binmode( STDIN,  ":encoding(UTF-8)" );
use utf8;
use Carp;
#$|=1; #Are hot filehandles necessary?

# External modules
use Time::HiRes;
use Log::Log4perl qw(:easy);

# Koha modules used
use C4::Context;
use Koha::AuthUtils;
use Koha::Patron;
use Koha::Patrons;

#Local modules
use Bulk::AutoConfigurer;
use Bulk::ConversionTable::BorrowernumberConversionTable;

sub new($class, $params) {
  my %params = %$params; #Shallow copy to prevent unintended side-effects
  my $self = bless({}, $class);
  $self->{_params} = \%params;
  $self->{dbh} = C4::Context->dbh();
  $self->{now} = DateTime->now()->ymd();
  return $self;
}

sub p($s, $param) {
  die "No such parameter '$param'!" unless (defined($s->{_params}->{$param}));
  return $s->{_params}->{$param};
}

my $getBorrowerSth;
sub GetBorrower {
  my ($borrowernumber) = @_;
  my $dbh = C4::Context->dbh();
  unless($getBorrowerSth) {
    $getBorrowerSth = $dbh->prepare("SELECT * FROM borrowers WHERE borrowernumber = ?");
  }
  $getBorrowerSth->execute($borrowernumber) or die $getBorrowerSth->errstr();
  return $getBorrowerSth->fetchrow_hashref();
}

=head2 AddMember

Hypothesis that DBIx::Class is sloooow. It doesn't seem that way now compared to this one.

 @returns LIST of
               - DBI prepared statement
               - All the column names in the borrowers-table. This is used to populate the INSERT statements later.

=cut

my $addBorrowerSth;
sub AddMember($s, $b) {
  unless ($addBorrowerSth) {
    my $borrowerColumns = "
borrowernumber,
cardnumber,
surname,
firstname,
title,
othernames,
initials,
streetnumber,
streettype,
address,
address2,
city,
state,
zipcode,
country,
email,
phone,
mobile,
fax,
emailpro,
phonepro,
B_streetnumber,
B_streettype,
B_address,
B_address2,
B_city,
B_state,
B_zipcode,
B_country,
B_email,
B_phone,
dateofbirth,
branchcode,
categorycode,
dateenrolled,
dateexpiry,
date_renewed,
gonenoaddress,
lost,
debarred,
debarredcomment,
contactname,
contactfirstname,
contacttitle,
borrowernotes,
relationship,
sex,
password,
flags,
userid,
opacnote,
contactnote,
sort1,
sort2,
altcontactfirstname,
altcontactsurname,
altcontactaddress1,
altcontactaddress2,
altcontactaddress3,
altcontactstate,
altcontactzipcode,
altcontactcountry,
altcontactphone,
smsalertnumber,
sms_provider_id,
privacy,
privacy_guarantor_fines,
privacy_guarantor_checkouts,".
#checkprevcheckout,
#$b->{updated_on},
"
lastseen,
lang,
login_attempts,
overdrive_auth_token,
anonymized,
autorenew_checkouts
";
    my $colCount = () = ($borrowerColumns =~ m/,/gsm);
    my $placeholders = ('?,' x $colCount) . '?';

    $addBorrowerSth = $s->{dbh}->prepare(
        "INSERT INTO borrowers\n".
        "    ($borrowerColumns)\n".
        "VALUES\n".
        "    ($placeholders)\n"
    ) or die "Preparing the koha.borrowers insertion statement failed: ".$s->{dbh}->errstr();
  }

  $b->{'password'} = ($b->{'password'}) 
                       ? (substr($b->{'password'}, 0, 3) eq '$2a')
                         ? $b->{'password'} # password is already hashed with bcrypt
                         : Koha::AuthUtils::hash_password($b->{'password'}, $s->bcryptSettings(2)) #The bcrypt iterations has been dropped from 8 to 2 to significantly speed up the migration.
                       : '!';

my @params = (
($main::args{preserveIds}) ? $b->{borrowernumber} : undef,
$b->{cardnumber},
$b->{surname},
$b->{firstname},
$b->{title},
$b->{othernames},
$b->{initials},
$b->{streetnumber},
$b->{streettype},
$b->{address},
$b->{address2},
$b->{city},
$b->{state},
$b->{zipcode},
$b->{country},
$b->{email},
$b->{phone},
$b->{mobile},
$b->{fax},
$b->{emailpro},
$b->{phonepro},
$b->{B_streetnumber},
$b->{B_streettype},
$b->{B_address},
$b->{B_address2},
$b->{B_city},
$b->{B_state},
$b->{B_zipcode},
$b->{B_country},
$b->{B_email},
$b->{B_phone},
$b->{dateofbirth},
$b->{branchcode} // '',
$b->{categorycode} // '',
$b->{dateenrolled},
$b->{dateexpiry},
$b->{date_renewed},
$b->{gonenoaddress},
$b->{lost},
$b->{debarred},
$b->{debarredcomment},
$b->{contactname},
$b->{contactfirstname},
$b->{contacttitle},
$b->{borrowernotes},
$b->{relationship},
$b->{sex},
$b->{password},
$b->{flags},
$b->{userid},
$b->{opacnote},
$b->{contactnote},
$b->{sort1},
$b->{sort2},
$b->{altcontactfirstname},
$b->{altcontactsurname},
$b->{altcontactaddress1},
$b->{altcontactaddress2},
$b->{altcontactaddress3},
$b->{altcontactstate},
$b->{altcontactzipcode},
$b->{altcontactcountry},
$b->{altcontactphone},
$b->{smsalertnumber},
$b->{sms_provider_id},
$b->{privacy} // 1,
$b->{privacy_guarantor_fines} // 0,
$b->{privacy_guarantor_checkouts} // 0,
#$b->{checkprevcheckout},
#$b->{updated_on},
$b->{lastseen},
$b->{lang},
$b->{login_attempts} // 0,
$b->{overdrive_auth_token},
$b->{anonymized} // 0,
$b->{autorenew_checkouts} // 1,
);
  eval {
    $addBorrowerSth->execute(@params) or die $addBorrowerSth->errstr();
  };
  if ($@) {
    if (Bulk::AutoConfigurer::borrower($b, $@)) {
      $addBorrowerSth->execute(@params) or die("Adding borrower failed: ".$addBorrowerSth->errstr());
    }
    else {
      die $@;
    }
  }

  my $borrowernumber = $s->{dbh}->last_insert_id(undef, undef, 'borrowers', undef);
  unless ($borrowernumber) {
    die "last_insert_id() not available after adding a borrower?: ".$s->{dbh}->errstr();
  }

  $s->checkPreserveId($b->{borrowernumber}, $borrowernumber);
  $b->{borrowernumber} = $borrowernumber;
}

=head2 addBorrowerAttribute

C4::Members::Attributes doesn't have an accessor to simply add a single entry.

=cut

my %attributesInDatabase;
sub addBorrowerAttribute($s, $patron, $attribute, $value, $isRepeatable) {
  unless ($s->{sth_addBorrowerAttribute}) {
    $s->{sth_addBorrowerAttribute} = $s->{dbh}->prepare(
      "INSERT INTO borrower_attributes (borrowernumber, code, attribute) VALUES (?, ?, ?)"
    );
  }
  unless ($attributesInDatabase{$attribute}) { # Autoload the borrower_attribute_types with caching.
    my $attr_type = C4::Members::AttributeTypes->fetch($attribute);
    unless ($attr_type) {
      $attr_type = C4::Members::AttributeTypes->new($attribute, "AUTO-$attribute");
      $attr_type->{repeatable} = ($isRepeatable) ? 1 : 0;
      $attr_type->{unique_id} = 0;
      $attr_type->store();
    }
    $attributesInDatabase{$attribute} = $attr_type;
  }
  $s->{sth_addBorrowerAttribute}->execute($patron->{borrowernumber}, $attribute, $value) or die("Adding borrower_attribute 'SSN' failed for borrowernumber='".$patron->{borrowernumber}."': ".$s->{sth_addBorrowerAttribute}->errstr());
}

sub addDefaultAdmin($s, $defaultAdmin, $defaultAdminApiKey) {
  print("Adding default admin");
  my ($username, $password) = split(':', $defaultAdmin);
  my ($api_key, $secret) = split(':', $defaultAdminApiKey);

  my $branchcode = Koha::Libraries->search->next->branchcode;

  my $categorycode = Koha::Patron::Categories->search->next->categorycode;

  my $patron = Koha::Patron->new( {
    surname => 'Kalifi',
    userid => $username,
    cardnumber => $username,
    branchcode => $branchcode,
    categorycode => $categorycode,
    flags => 1,
  })->store;

  $patron->set_password( { password => $password } );

  if (defined $api_key && defined $secret) {
    my $hashed_secret = Koha::AuthUtils::hash_password($secret);      
    $s->{sth_addDefaultAdmin} =
      $s->{dbh}->prepare("INSERT INTO api_keys (client_id, secret, patron_id) VALUES (?,?,?)") or die("Preparing the addDefaultAdmin() api key query failed)".$s->{dbh}->errstr());
    $s->{sth_addDefaultAdmin}->execute($api_key, $hashed_secret, $patron->borrowernumber);
  }

  addAnonymizedPatron();
}

sub addAnonymizedPatron {
  print("Adding anonymized Patron");

  my $branchcode = Koha::Libraries->search->next->branchcode;

  my $categorycode = Koha::Patron::Categories->search->next->categorycode;

  my $patron = Koha::Patron->new( {
    surname => 'Anonymized',
    userid => 'anonymized',
    cardnumber => 'anonymized',
    branchcode => $branchcode,
    categorycode => $categorycode,
    flags => 0,
    dateexpiry => '2032-12-31',
  })->store;

  $patron->set_password( { password => '!' } ); # disable login
  $patron = Koha::Patrons->find({cardnumber => 'anonymized'}); # get new borrowernumber

  C4::Context->set_preference('AnonymousPatron', $patron->borrowernumber);
}

sub fineImport($s, $borrowernumber, $desc, $accounttype, $amount, $date) {
  $s->{fineStatement} = $s->{dbh}->prepare( #Used for Libra3
    'INSERT INTO  accountlines
        (borrowernumber, accountno, date, amount, description, accounttype, amountoutstanding, notify_id, manager_id)
    VALUES (?,           ?,         ?,    ?,      ?,           ?,           ?,                 ?,         ?)'
  ) unless $s->{fineStatement};

  #Make sure the borrowerexists!
  my $testingBorrower = C4::Members::GetMember(borrowernumber => $borrowernumber);
  unless (defined $testingBorrower) {
    warn "Patron $borrowernumber doesn't exist in Koha!\n";
    return;
  }

  my $accountno  = C4::Accounts::getnextacctno( $borrowernumber );
  my $amountleft = $amount;
  my $notifyid = 0;
  my $manager_id = C4::Context->userenv ? C4::Context->userenv->{'number'} : 1;

  $s->{fineStatement}->execute($borrowernumber, $accountno, $date, $amount, $desc, $accounttype, $amountleft, $notifyid, $manager_id);

  if ($s->{fineStatement}->errstr) {
    println $s->{fineStatement}->errstr;
  }
}

sub AddDebarment($s, $params) {
  my $borrowernumber = $params->{'borrowernumber'};
  my $expiration     = $params->{'expiration'} || undef;
  my $type           = $params->{'type'} || 'MANUAL';
  my $comment        = $params->{'comment'} || undef;
  my $created        = $params->{'created'} || undef;

  return unless ( $borrowernumber && $type );

  my $manager_id;
  $manager_id = C4::Context->userenv->{'number'} if C4::Context->userenv;

  $s->{sth_addDebarment} = $s->{dbh}->prepare("
    INSERT INTO borrower_debarments ( borrowernumber, expiration, type, comment, manager_id, created )
    VALUES ( ?, ?, ?, ?, ?, ? )
  ") unless $s->{sth_addDebarment};

  $s->{sth_addDebarment}->execute($borrowernumber, $expiration, $type, $comment, $manager_id, $created);

  Koha::Patron::Debarments::UpdateBorrowerDebarmentFlags($borrowernumber);
}

=head2 setDefaultMessagingPreferences

Koha has
    misc/maintenance/borrowers-force-messaging-defaults
but it cannot be given a group of borrowers to force.

Modifying that would be very difficult since getting changes upstream takes much time.

Script is rather simple anyway so reimplement needed bits here.

=cut

sub setDefaultMessagingPreferences($s) {
  INFO "Slurping a borrowernumberConversionTable for new borrowernumbers";
  open (my $FH, '<:encoding(UTF-8)', $s->p('borrowernumberConversionTableFile')) or die("Cannot open borrowernumber conversion table '".$s->p('borrowernumberConversionTableFile')."' for reading: $!");
  my %bns; #conversion tables might get multiple runs appended to them, so deduplicate numbers on the fly
  while (<$FH>) {
    if (/^(\d+)\D(\d+)/) { #Pick old and new borrowernumbers
      my ($oldBn, $newBn) = ($1, $2);
      $bns{$newBn} = 1;
    }
    else {
      WARN "Couldn't parse borrowernumberConversionTable entry '$_'";
    }
  }
  my @bns = keys %bns;
  INFO "Setting default messaging preferences for ".scalar(@bns)." new Patrons";
  my $i = 0;
  for my $bn (@bns) {
    INFO "Processed $i Items" if (++$i % 1000 == 0);
    my $b = GetBorrower($bn);
    unless ($b) {
      WARN "No such Patron '$bn' in the DB";
      next;
    }
    C4::Members::Messaging::SetMessagingPreferencesFromDefaults($b);
  }
}

=head2 sort1ToAuthorizedValue

Convert borrowers.sort1 to a list of Bsort1 authorised_values

=cut

sub sort1ToAuthorizedValue($s) {
  $s->{dbh} = C4::Context->dbh();
  $s->{sth_sort1} = $s->{dbh}->prepare("insert ignore into authorised_values (category, authorised_value, lib, lib_opac) select distinct 'Bsort1', sort1, sort1, sort1 from borrowers where sort1!='';");
  $s->{sth_sort1}->execute();
}

=head2 uploadSSNKeys

Upload ssn keys to koha.borrower_attributes

=cut

sub uploadSSNKeys($s) {
  require Hetula::Client;
  INFO "Opening BorrowernumberConversionTable '".$s->p('borrowernumberConversionTableFile')."' for reading";
  my $borrowernumberConversionTable = Bulk::ConversionTable::BorrowernumberConversionTable->new($s->p('borrowernumberConversionTableFile'), 'read');

  INFO "Adding SSNs to Hetula, this will take a while";
  my $hc = Hetula::Client->new({credentials => $s->p('uploadSSNKeysHetulaCredentialsFile')});
  $hc->login();
  $hc->ssnsBatchAddFromFile($s->p('uploadSSNKeysFile'), $s->p('uploadSSNKeysFile').'.hetula', 500);

  INFO "SSNs added. Importing ssn keys to Koha.";
  $s->{dbh} = C4::Context->dbh(); #DBH times out while waiting for Hetula most certainly
  open(my $SSN_FH, '<:encoding(UTF-8)', $s->p('uploadSSNKeysFile').'.hetula') or die("Opening Hetula ssn reports file '".$s->p('uploadSSNKeysFile').".hetula' failed: $!");
  while (my $ssnReportCsvRow = <$SSN_FH>) {
    chomp($ssnReportCsvRow);
    my ($ssnId, $ssn, $error, $borrowernumberOld) = split(',', $ssnReportCsvRow);

    my $ssnKey;
    if ($ssnId) {
      $ssnKey = substr('ssn0000000000', 0, -1*length($ssnId)) . $ssnId;
    }
    elsif ($error =~ /^Hetula::Exception::Ssn::Invalid/) {
      $ssnKey = 'INVALID'.$ssn;
      print "$ssnKey\n";
    }
    else {
      $ssnKey = "$error. Original ssn '$ssn'.";
    }

    my $borrowernumberNew = $borrowernumberConversionTable->fetch($borrowernumberOld);
    unless ($borrowernumberNew) {
      ERROR "Old borrowernumber '$borrowernumberOld' couldn't be converted to a new borrowernumber. Skipping ssnKey '$ssnKey'";
      next;
    }

    $s->addBorrowerAttribute({borrowernumber => $borrowernumberNew}, 'SSN', $ssnKey);
  }
}

=head2 duplicateOthernamesHandler

Checks from Koha if the given borrowers.othernames is unique.
If not,

 @returns String, the given othernames, appended with a random integer.

=cut

sub duplicateOthernamesHandler($s, $othernames) {
  unless ($s->{sth_othernamesTaken}) {
    $s->{sth_othernamesTaken} =
      $s->{dbh}->prepare("SELECT othernames FROM borrowers WHERE othernames = ?") or die("Preparing the othernamesTaken() query failed: ".$s->{dbh}->errstr());
  }

  $s->{sth_othernamesTaken}->execute($othernames);
  my ($theOthername) = $s->{sth_othernamesTaken}->fetchrow_array();
  if (defined($theOthername)) {
    $othernames .= 100*rand(1);
    return $s->duplicateOthernamesHandler($othernames); #Recursively keep adding random integers until a free slot is found.
  }
  else {
    return $othernames;
  }
}

=head2 profileBcrypts

When profiling bulkPatronImport.pl
I realized the Crypt::Eksblowfish::Bcrypt consumes an incommensurate amount of CPU time.
Profiling methods of making it very fast (at the expense of "safety").

=cut

sub profileBcrypts($s) {
  require Crypt::Eksblowfish::Bcrypt;
  require Digest::Bcrypt;
  require Digest;
  require Koha::AuthUtils;
  my $pass = 'I walk through the valley of my own shadow';
  my $iterations = 1000;
  my ($cost, $settings, $testName, $start, $runtime);

  _profileEksblowfishBcryptKoha($s, $iterations, $pass, 1);
  _profileEksblowfishBcryptKoha($s, $iterations, $pass, 4);
  _profileEksblowfishBcryptKoha($s, $iterations, $pass, 6);
  _profileEksblowfishBcrypt    ($s, $iterations, $pass, 1);
  _profileEksblowfishBcrypt    ($s, $iterations, $pass, 4);
  _profileEksblowfishBcrypt    ($s, $iterations, $pass, 6);
  _profileDigestBcrypt         ($s, $iterations, $pass, 1);
  _profileDigestBcrypt         ($s, $iterations, $pass, 4);
  _profileDigestBcrypt         ($s, $iterations, $pass, 6);
}

sub bcryptSettings($s, $cost) {
  $cost = "0$cost" if length $cost < 2;
  return '$2a$'.$cost.'$'.Crypt::Eksblowfish::Bcrypt::en_base64(Koha::AuthUtils::generate_salt('weak', 16))
}

sub _profileEksblowfishBcryptKoha($s, $iterations, $pass, $cost) {
  my $testName = "Koha::AuthUtils::hash_password($cost)";
  INFO "Profiling $testName, iterations=$iterations";
  my $start = Time::HiRes::gettimeofday();
  Koha::AuthUtils::hash_password($pass, $s->bcryptSettings($cost)) while ($iterations--);
  my $runtime = Time::HiRes::gettimeofday() - $start;
  INFO "Profiled  $testName in $runtime";
}

sub _profileEksblowfishBcrypt($s, $iterations, $pass, $cost) {
  my $testName = "Crypt::Eksblowfish::Bcrypt::bcrypt($cost)";
  INFO "Profiling $testName, iterations=$iterations";
  my $start = Time::HiRes::gettimeofday();
  Crypt::Eksblowfish::Bcrypt::bcrypt($pass, $s->bcryptSettings($cost)) while ($iterations--);
  my $runtime = Time::HiRes::gettimeofday() - $start;
  INFO "Profiled  $testName in $runtime";
}

sub _profileDigestBcrypt($s, $iterations, $pass, $cost) {
  my $testName = "Digest::Bcrypt($cost)";
  INFO "Profiling $testName, iterations=$iterations";
  my $start = Time::HiRes::gettimeofday();
  while ($iterations--) {
    my $bcrypt = Digest->new('Bcrypt', cost => $cost, salt => Koha::AuthUtils::generate_salt('weak', 16));
    $bcrypt->add($pass)->digest;
  }
  my $runtime = Time::HiRes::gettimeofday() - $start;
  INFO "Profiled  $testName in $runtime";
}

sub checkPreserveId($s, $legId, $newId) {
  if ($s->p('preserveIds') && $legId ne $newId) {
    WARN "Trying to preserve IDs: Legacy borrowernumber '$legId' is not the same as the new borrowernumber '$newId'.";
    return 0;
  }
  return 1;
}

return 1;
