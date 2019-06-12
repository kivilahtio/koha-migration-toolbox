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
use Koha::Auth::PermissionManager;

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

=head2 AddMember

Trimmed down copy of C4::Members::AddMember

=cut

sub AddMember($s, $data, $useDBIx=0) {
  # generate a proper login if none provided
  $data->{'userid'} = C4::Members::Generate_Userid($data->{'borrowernumber'}, $data->{'firstname'}, $data->{'surname'}) unless $data->{'userid'};
  delete $data->{'borrowernumber'} unless ($s->p('preserveIds'));

  # add expiration date if it isn't already there
  unless ( $data->{'dateexpiry'} ) {
    $data->{'dateexpiry'} = $s->{now};
  }

  # add enrollment date if it isn't already there
  unless ( $data->{'dateenrolled'} ) {
    $data->{'dateenrolled'} = $s->{now};
  }

  # create a disabled account if no password provided
  $data->{'password'} = ($data->{'password'}) ?
                          Koha::AuthUtils::hash_password($data->{'password'}, $s->bcryptSettings(2)) : #The bcrypt iterations has been dropped from 8 to 2 to significantly speed up the migration.
                          '!';

  # Default privacy if none provided
  $data->{privacy} = 1 unless exists $data->{privacy};
  $data->{'privacy_guarantor_checkouts'} = 0;

  $data->{checkprevcheckout} = 0 unless $data->{checkprevcheckout};
  $data->{lang} = 'fi' unless $data->{lang};

  $data->{othernames} = $s->duplicateOthernamesHandler($data->{othernames});

  if ($useDBIx) { #DBIx migrated 8800 Patrons in 8 minutes
    my $patron=Koha::Patron->new($data);
    $patron->store;
    $s->checkPreserveId($data->{'borrowernumber'}, $patron->borrowernumber);
    $data->{'borrowernumber'}=$patron->borrowernumber;
  }
  else {          #DBD::MySQL migrated 10500 Patrons in 11 minutes
    $s->addBorrowerDBI($data);
  }

  return $data->{'borrowernumber'};
}

=head2 addBorrowerDBI

Hypothesis that DBIx::Class is sloooow. It doesn't seem that way now compared to this one.

 @returns LIST of
               - DBI prepared statement
               - All the column names in the borrowers-table. This is used to populate the INSERT statements later.

=cut

sub addBorrowerDBI($s, $patron) {
  unless ($s->{sth_addBorrower}) {
    my $sth = $s->{dbh}->column_info( undef, undef, 'borrowers', '%' );
    my $cols = $sth->fetchall_arrayref({}) or die("Fetching koha.borrowers column definitions failed: ".$s->{dbh}->errstr());
    my @borrowerColumns = map {$_->{COLUMN_NAME}} @$cols;
    my @placeholders = map {'?'} (1..@borrowerColumns);

    my $sth_addBorrower = $s->{dbh}->prepare( #Is DBIx just so freaking sloooooowwwww?
        "INSERT INTO borrowers\n".
        "    (".join(',',@borrowerColumns).")\n".
        "VALUES\n".
        "    (".join(',',@placeholders).")\n"
    ) or die "Preparing the koha.borrowers insertion statement failed: ".$s->{dbh}->errstr();

    $s->{sth_addBorrower} = $sth_addBorrower;
    $s->{borrowerColumns} = \@borrowerColumns;
  }

  my @params = map {$patron->{$_}} @{$s->{borrowerColumns}};
  eval {
    $s->{sth_addBorrower}->execute(@params) or die("Adding borrower failed: ".$s->{sth_addBorrower}->errstr());
  };
  if ($@) {
    if (Bulk::AutoConfigurer::borrower($patron, $@)) {
      $s->{sth_addBorrower}->execute(@params) or die("Adding borrower failed: ".$s->{sth_addBorrower}->errstr());
    }
  }

  my $borrowernumber = $s->{dbh}->last_insert_id(undef, undef, 'borrowers', undef);
  unless ($borrowernumber) {
    die "last_insert_id() not available after adding a borrower?: ".$s->{dbh}->errstr();
  }

  $s->checkPreserveId($patron->{borrowernumber}, $borrowernumber);
  $patron->{borrowernumber} = $borrowernumber;
}

=head2 addBorrowerAttribute

C4::Members::Attributes doesn't have an accessor to simply add a single entry.

=cut

sub addBorrowerAttribute($s, $patron, $attribute, $value) {
  unless ($s->{sth_addBorrowerAttribute}) {
    $s->{sth_addBorrowerAttribute} = $s->{dbh}->prepare(
      "INSERT INTO borrower_attributes (borrowernumber, code, attribute) VALUES (?, ?, ?)"
    );
  }
  $s->{sth_addBorrowerAttribute}->execute($patron->{borrowernumber}, $attribute, $value) or die("Adding borrower_attribute 'SSN' failed for borrowernumber='".$patron->{borrowernumber}."': ".$s->{sth_addBorrowerAttribute}->errstr());
}

sub addDefaultAdmin($s, $defaultAdmin) {
  my ($username, $password) = split(':', $defaultAdmin);
  INFO "Adding default admin";
  my $dbh = C4::Context->dbh;
  my $categorycode = $dbh->selectrow_array("SELECT categorycode from categories LIMIT 1") or die "Failed to get default admin categorycode ".$dbh->errstr(); #Pick any borrower.categorycode
  my $branchcode = $dbh->selectrow_array("SELECT branchcode from branches LIMIT 1") or die "Failed to get default admin branchcode ".$dbh->errstr(); #Pick any borrower.branchcode
  my %defaultAdmin = (
    cardnumber =>   "kalifi",
    surname =>      "Kalifi",
    firstname =>    "Kalifin",
    othernames =>   "paikalla",
    address =>      "Kalifinkuja 12 b 7",
    city =>         "Kalifila",
    zipcode =>      "12345",
    dateofbirth =>  "1985-09-06",
    branchcode =>   $branchcode,
    categorycode => $categorycode,
    dateenrolled => "2015-09-25",
    dateexpiry =>   "2018-09-25",
    password =>     $password,
    userid =>       $username,
    privacy =>      1,
  );
  eval {
    $defaultAdmin{borrowernumber} = C4::Members::AddMember(%defaultAdmin);
    INFO "Granting default admin permissions";
    my $permissionManager = Koha::Auth::PermissionManager->new();
    $permissionManager->grantPermission($defaultAdmin{borrowernumber}, 'superlibrarian', 'superlibrarian');
  };
  if ($@) {
    print "Error while adding the default admin: $@";
  }
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

  Koha::Patron::Debarments::_UpdateBorrowerDebarmentFlags($borrowernumber);
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
    my $p = Koha::Patrons->find($bn);
    unless ($p) {
      WARN "No such Patron '$bn' in the DB";
      next;
    }
    $p->set_default_messaging_preferences();
  }
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
