package Bulk::BibImporter;

#Pragmas
use Modern::Perl;
use experimental 'smartmatch', 'signatures';
binmode( STDOUT, ":encoding(UTF-8)" );
binmode( STDIN,  ":encoding(UTF-8)" );
use utf8;
use Carp;
use English;
use threads;
use threads::shared;
use Thread::Semaphore;
#$|=1; #Are hot filehandles necessary?

## Thank you https://stackoverflow.com/questions/12696375/perl-share-filehandle-with-threads
# Flag to inform all threads that application is terminating
my $SIG_TERMINATE_RECEIVED :shared = 0;
$SIG{INT} = $SIG{TERM} = sub {
  print("\n>>> Terminating <<<\n\n");
  $SIG_TERMINATE_RECEIVED = 1;
};

my $preventJoiningBeforeAllWorkIsDone;

my $jobBufferMaxSize = 500;

# External modules
use Time::HiRes qw(gettimeofday);
use Log::Log4perl qw(:easy);
use Thread::Queue;

# Koha modules used
use MARC::File::XML;
use MARC::Batch;#
use C4::Context;
use C4::Biblio;

#Local modules
use Bulk::ConversionTable::BiblionumberConversionTable;


# Distribute jobs to workers via this structure since a shared file handle can no longer be reliably accessed from threads even when using locks
my $recordQueue = Thread::Queue->new();
my $bnConversionQueue = Thread::Queue->new();

## Overload C4::Biblio::ModZebra to prevent indexing during record migration.
package C4::Biblio {
  no warnings 'redefine';
  sub ModZebra {
    return undef;
  }
  use warnings 'redefine';
}

sub new($class, $params) {
  my %params = %$params; #Shallow copy to prevent unintended side-effects
  my $self = bless({}, $class);
  $self->{_params} = \%params;

  INFO "Opening BiblionumberConversionTable '".$self->p('biblionumberConversionTable')."' for writing";
  $self->{biblionumberConversionTable} = Bulk::ConversionTable::BiblionumberConversionTable->new( $self->p('biblionumberConversionTable'), 'write' );

  return $self;
}

sub p($s, $param) {
  die "No such parameter '$param'!" unless (defined($s->{_params}->{$param}));
  return $s->{_params}->{$param};
}

=head2 bimp

Does the actual MARC::Record migration

=cut

sub bimp($s) {
  my $starttime = gettimeofday;

  $preventJoiningBeforeAllWorkIsDone = Thread::Semaphore->new( -1*$s->p('workers') +1 ); #Semaphore blocks until all threads have released it.

  my @threads;
  push @threads, threads->create(\&worker, $s)
    for 1..$s->p('workers');

  my $next = Bulk::Util::getMarcFileIterator($s);
  #Enqueue MFHDs to the job queue. This way we avoid strange race conditions in the file handle
  while (not($SIG_TERMINATE_RECEIVED) && defined(my $record = $next->())) {
    if ($recordQueue->pending() > $jobBufferMaxSize) { # This is a type of buffering to avoid loading too much into memory. Wait for a while, if the job queue is getting large.
      TRACE "Thread MAIN - Jobs queued '".$recordQueue->pending()."' , sleeping";
      while (not($SIG_TERMINATE_RECEIVED) && $recordQueue->pending() > $jobBufferMaxSize/2) {
        Time::HiRes::usleep(100); #Wait for the buffer to cool down
      }
    }

    chomp($record);
    $recordQueue->enqueue($record);

    INFO "Queued $. Records" if ($. % 1000 == 0);

    while (my $bid = $bnConversionQueue->dequeue_nb()) {
      $s->{biblionumberConversionTable}->writeRow($bid->{old}, $bid->{new}, $bid->{op}, $bid->{status});
    }
  }

  # Signal to threads that there is no more work.
  $recordQueue->end();

  #This script crashes when threads are being joined, so wait for them to stop working first.
  #It is very hacky, but so far there seems to be no side-effects for it.
  #It is easier to do this, than employ some file-splitting and forking.
  $preventJoiningBeforeAllWorkIsDone->down();

  INFO "Writing remaining '".$bnConversionQueue->pending()."' biblionumber conversions";
  while (my $bid = $bnConversionQueue->dequeue_nb()) {
    $s->{biblionumberConversionTable}->writeRow($bid->{old}, $bid->{new}, $bid->{op}, $bid->{status});
  }
  $s->{biblionumberConversionTable}->close(); #Close the filehandle to not lose any data

  my $timeneeded = gettimeofday - $starttime;
  INFO "\n$. MARC records done in $timeneeded seconds\n";

  # ((((: Wait for all the threads to finish. :DDDDDDD
  for (@threads) {
    $_->join();
    INFO "Thread ".$_->tid()." - Joined";
  }
  # :XXXX

  return undef;
}

sub worker($s) {
  my $tid;
  eval {
  $tid = threads->tid();

  Bulk::Util::invokeThreadCompatibilityMagic();

  my $oplibMatcher;
  if ($s->p('matchLog')) {
    WARN "Bulk::OplibMatcher is TODO for ElasticSearch";
    #$oplibMatcher = Bulk::OplibMatcher->new($s->p('matchLog'));
  }

  while (not($SIG_TERMINATE_RECEIVED) && defined(my $recordXmlPtr = $recordQueue->dequeue())) {
    DEBUG "Thread $tid - New job";
    TRACE "$$recordXmlPtr\n";

    my $record = MARC::Record->new_from_xml($$recordXmlPtr, 'UTF-8', 'MARC21');
    my $legacyBiblionumber = $s->getLegacyBiblionumber($record);
    next unless $legacyBiblionumber;

    my $matchedBiblionumber;
    my $matchResult = $oplibMatcher->checkMatch($record) if $oplibMatcher;
    if ($matchResult && $matchResult =~ /^PEN/) { #This result needs manual confirmation and is waiting for manual override instructions
      print 'P';
      #we let it slip
    }
    elsif ($matchResult && $matchResult =~ /^KILL/) { #This result is manually instructed to die
      print 'K';
      next();
    }
    elsif ($matchResult && $matchResult =~ /^OK/) { #This result is added as a new record
      print 'O';
    }
    elsif ($matchResult && $matchResult =~ /^CP/) { #This component part is added as a new record, because the component parent has been added as well.
      print 'C';
    }
    elsif ($matchResult && $matchResult > 0) { #A match found and we got the target biblionumber
      print 'M';
      $matchedBiblionumber = $matchResult;
    }
    else {
      #No match found, safe to migrate.
    }

    my ($operation, $statusOfOperation, $newBiblionumber);
    ($operation, $statusOfOperation)                   = $s->mergeRecords($record, $recordXmlPtr, $matchedBiblionumber) if     ($matchedBiblionumber);
    ($operation, $statusOfOperation, $newBiblionumber) = $s->addRecord   ($record, $recordXmlPtr, $legacyBiblionumber)  unless ($matchedBiblionumber);

    my %bid :shared = (old => $legacyBiblionumber, new => $matchedBiblionumber // $newBiblionumber // 0, op => $operation, status => $statusOfOperation);
    $bnConversionQueue->enqueue(\%bid);
  }
  };
  if ($@) {
    warn "Thread ".($tid//'undefined')." - died:\n$@\n";
  }

  $preventJoiningBeforeAllWorkIsDone->up(); #This worker has finished working
}

=head2 disableUnnecessarySystemSettings

Disable logging for the biblios and authorities import operation. It would unnecessarily slow the import.

=cut

sub disableUnnecessarySystemSettings($s, $prefs) {
  INFO "Disabling sysprefs:\n".Data::Dumper::Dumper($prefs);
  C4::Context->disable_syspref_cache(); # Disable the syspref cache so we can change logging settings

  while (my ($spref, $vals) = each %$prefs) {
    C4::Context->set_preference($spref, $vals->{new});
  }
}
sub reEnableSystemSettings($s, $prefs) {
  INFO "Enabling sysprefs:\n".Data::Dumper::Dumper($prefs);
  while (my ($spref, $vals) = each %$prefs) {
    C4::Context->set_preference($spref, $vals->{old});
  }
}

=head2 getLegacyBiblionumber

@returns Integer, biblionumber from the old system
          undef, if biblionumber was not found!

=cut

sub getLegacyBiblionumber($s, $record) {
  unless ($s->p('legacyIdFieldDef') =~ /^(\d{3})[^0-9a-z]?([0-9a-z]?)$/) {
    die ("Unable to parse \$legacyIdFieldDef='".$s->p('legacyIdFieldDef')."' for field and subfield definitions");
  }
  my ($f, $sf) = ($1, $2);
  my $legacyBiblionumber;

  if ($record->field($f)) {
    if ($f lt "010") {
      $legacyBiblionumber = $record->field($f)->data();
    }
    else {
      $legacyBiblionumber = $record->subfield($f, $sf);
    }
  }
  else {
    ERROR "Error when getting the legacy biblionumber from definition '".$s->p('legacyIdFieldDef')."': Record from file '".$s->p('inputMarcFile')."' on line '$.' is missing field '$f'. Removing this Record.";
    return undef;
  }

  $legacyBiblionumber =~ s/(?:^\s*)|(?:\s*$)//gsm; #Trim whitespace from around
  unless ($legacyBiblionumber) {
    ERROR "Error when getting the legacy biblionumber from definition '".$s->p('legacyIdFieldDef')."': Record from file '".$s->p('inputMarcFile')."' has an empty [sub]field? Removing this Record.";
    return undef;
  }

  return $legacyBiblionumber;
}

=head2 mergeRecords

The incoming MARC::Record has been reliably matched against an existing MARC::Record.
Do the merging using the given merge strategy.

@returns LIST, [0] -> operation done, the $mergeStrategy
                [1] -> status of the operation, ERROR vs OK

=cut

sub mergeRecords($s, $record, $recordXmlPtr, $legacyBiblionumber, $matchedBiblionumber) {
  if ($s->p('mergeStrategy') eq 'overwrite') {
    my ($biblioitemnumber, $biblionumber) = eval { C4::Biblio::ModBiblio($record, $matchedBiblionumber, C4::Biblio::GetFrameworkCode($matchedBiblionumber)) };
    if ($@) {
      ERROR "Overwriting biblio $legacyBiblionumber->$matchedBiblionumber failed: $@\n";
      return ($s->p('mergeStrategy'), 'ERROR');
    } else {
      return ($s->p('mergeStrategy'), 'OK');
    }
  }
  elsif ($s->p('mergeStrategy') eq 'defer') {
    return ($s->p('mergeStrategy'), 'OK');
  }
  else {
    die("Unknown \$mergeStrategy='".$s->p('mergeStrategy')."'!");
  }
}

=head2 addRecord

@returns LIST, [0] -> operation done, the $mergeStrategy
               [1] -> status of the operation, ERROR vs OK
               [2] -> new biblionumber if adding succeeded without errors.

=cut

sub addRecord($s, $record, $recordXmlPtr, $legacyBiblionumber) {
  if ($s->p('migrateStrategy') eq 'fast' || $s->p('migrateStrategy') eq 'chunk') {
    $s->addRecordFast($record, $recordXmlPtr, $legacyBiblionumber);
  }
  elsif ($s->p('migrateStrategy') eq 'koha') {
    $s->addRecordKoha($record, $recordXmlPtr, $legacyBiblionumber);
  }
}

sub addRecordKoha($s, $record, $recordXmlPtr, $legacyBiblionumber) {
  my ($newBiblionumber, $newBiblioitemnumber) = eval { C4::Biblio::AddBiblio($record, '') };
  die "Biblionumber '$newBiblionumber' and biblioitemnumber '$newBiblioitemnumber' do not match! This causes critical issues in Koha!\n" if $newBiblionumber != $newBiblioitemnumber;

  if ($@) {
    ERROR "Adding biblio '$legacyBiblionumber' failed: $@\n";
    return ("insert", "ERROR");
  } else {
    return ("insert", "OK", $newBiblionumber);
  }
}

sub addRecordFast($s, $record, $recordXmlPtr, $legacyBiblionumber) {
  my $dbh = C4::Context->dbh();
  $dbh->{AutoCommit} = 0;

  my $frameworkcode = '';
  my $olddata = C4::Biblio::TransformMarcToKoha($record, $frameworkcode);
  $olddata->{biblionumber} = $legacyBiblionumber if $s->p('preserveIds');
  my ($newBiblionumber, $error1)     = _koha_add_biblio($dbh, $olddata, $frameworkcode);
  if ($error1) {
    ERROR "Error1=$error1";
    return ("insert", "ERROR1", $newBiblionumber);
  }

  $s->checkPreserveId($legacyBiblionumber, $newBiblionumber);

  $olddata->{'biblionumber'} = $newBiblionumber;
  $olddata->{'biblioitemnumber'} = $newBiblionumber;
  my ($newBiblioitemnumber, $error2) = _koha_add_biblioitem($dbh, $olddata);
  if ($error2) {
    ERROR "Error2=$error2";
    return ("insert", "ERROR2", $newBiblionumber);
  }

  $dbh->commit();

  die "Biblionumber '$newBiblionumber' and biblioitemnumber '$newBiblioitemnumber' do not match! This causes critical issues in Koha!\n" if $newBiblionumber != $newBiblioitemnumber;

  unless ($s->{sth_insertBiblioMetadata}) {
    $s->{sth_insertBiblioMetadata} = $dbh->prepare("INSERT INTO biblio_metadata (biblionumber, format, marcflavour, metadata) VALUES (?, ?, ?, ?)");
  }
  $s->{sth_insertBiblioMetadata}->execute($newBiblionumber, 'marcxml', 'MARC21', $recordXmlPtr ? $$recordXmlPtr : $record->as_xml());
  if ($s->{sth_insertBiblioMetadata}->errstr()) {
    ERROR "Error3=".$s->{sth_insertBiblioMetadata}->errstr();
    return ("insert", "ERROR3", $newBiblionumber);
  }

  return ("insert", "OK", $newBiblionumber);
}

=head2 OVERLOADS C4::Biblio::_koha_add_biblio

Make sure the logic hasn't changed in your Koha-version

=cut

sub _koha_add_biblio {
    my ( $dbh, $biblio, $frameworkcode ) = @_;

    my $error;

    # set the series flag
    unless (defined $biblio->{'serial'}){
        $biblio->{'serial'} = 0;
        if ( $biblio->{'seriestitle'} ) { $biblio->{'serial'} = 1 }
    }

    my $query = "INSERT INTO biblio
        SET biblionumber = ?,
            frameworkcode = ?,
            author = ?,
            title = ?,
            unititle =?,
            notes = ?,
            serial = ?,
            seriestitle = ?,
            copyrightdate = ?,
            datecreated=NOW(),
            abstract = ?
        ";
    my $sth = $dbh->prepare($query);
    $sth->execute(
        $biblio->{biblionumber}, $frameworkcode, $biblio->{'author'},      $biblio->{'title'},         $biblio->{'unititle'}, $biblio->{'notes'},
        $biblio->{'serial'},        $biblio->{'seriestitle'}, $biblio->{'copyrightdate'}, $biblio->{'abstract'}
    );

    my $biblionumber = $dbh->{'mysql_insertid'};
    if ( $dbh->errstr ) {
        $error .= "ERROR in _koha_add_biblio $query" . $dbh->errstr;
        warn $error;
    }

    $sth->finish();

    #warn "LEAVING _koha_add_biblio: ".$biblionumber."\n";
    return ( $biblionumber, $error );
}

=head2 OVERLOADS C4::Biblio::_koha_add_biblioitem

Forces the primary key if available.

Make sure the logic hasn't changed in your Koha-version

=cut

sub _koha_add_biblioitem {
    my ( $dbh, $biblioitem ) = @_;
    my $error;

    my ($cn_sort) = C4::ClassSource::GetClassSort( $biblioitem->{'biblioitems.cn_source'}, $biblioitem->{'cn_class'}, $biblioitem->{'cn_item'} );
    my $query = "INSERT INTO biblioitems SET
        biblioitemnumber = ?,
        biblionumber    = ?,
        volume          = ?,
        number          = ?,
        itemtype        = ?,
        isbn            = ?,
        issn            = ?,
        publicationyear = ?,
        publishercode   = ?,
        volumedate      = ?,
        volumedesc      = ?,
        collectiontitle = ?,
        collectionissn  = ?,
        collectionvolume= ?,
        editionstatement= ?,
        editionresponsibility = ?,
        illus           = ?,
        pages           = ?,
        notes           = ?,
        size            = ?,
        place           = ?,
        lccn            = ?,
        url             = ?,
        cn_source       = ?,
        cn_class        = ?,
        cn_item         = ?,
        cn_suffix       = ?,
        cn_sort         = ?,
        totalissues     = ?,
        ean             = ?,
        agerestriction  = ?
        ";
    my $sth = $dbh->prepare($query);
    $sth->execute(
        $biblioitem->{'biblioitemnumber'},
        $biblioitem->{'biblionumber'},     $biblioitem->{'volume'},           $biblioitem->{'number'},                $biblioitem->{'itemtype'},
        $biblioitem->{'isbn'},             $biblioitem->{'issn'},             $biblioitem->{'publicationyear'},       $biblioitem->{'publishercode'},
        $biblioitem->{'volumedate'},       $biblioitem->{'volumedesc'},       $biblioitem->{'collectiontitle'},       $biblioitem->{'collectionissn'},
        $biblioitem->{'collectionvolume'}, $biblioitem->{'editionstatement'}, $biblioitem->{'editionresponsibility'}, $biblioitem->{'illus'},
        $biblioitem->{'pages'},            $biblioitem->{'bnotes'},           $biblioitem->{'size'},                  $biblioitem->{'place'},
        $biblioitem->{'lccn'},             $biblioitem->{'url'},                   $biblioitem->{'biblioitems.cn_source'},
        $biblioitem->{'cn_class'},         $biblioitem->{'cn_item'},          $biblioitem->{'cn_suffix'},             $cn_sort,
        $biblioitem->{'totalissues'},      $biblioitem->{'ean'},              $biblioitem->{'agerestriction'}
    );
    my $bibitemnum = $dbh->{'mysql_insertid'};

    if ( $dbh->errstr ) {
        $error .= "ERROR in _koha_add_biblioitem $query" . $dbh->errstr;
        warn $error;
    }
    $sth->finish();
    return ( $bibitemnum, $error );
}

sub checkPreserveId($s, $legId, $newId) {
  if ($s->p('preserveIds') && $legId ne $newId) {
    WARN "Trying to preserve IDs: Legacy biblionumber '$legId' is not the same as the new biblionumber '$newId'.";
    return 0;
  }
  return 1;
}

return 1;
