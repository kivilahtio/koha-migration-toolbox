package Bulk::MFHDImporter;

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
use C4::Context;
use C4::Holdings;

#Local modules
use Bulk::ConversionTable::BiblionumberConversionTable;
use Bulk::ConversionTable::SubscriptionidConversionTable;


# Distribute jobs to workers via this structure since a shared file handle can no longer be reliably accessed from threads even when using locks
my $mfhdQueue = Thread::Queue->new();
my $hnConversionQueue = Thread::Queue->new();


sub new($class, $params) {
  my %params = %$params; #Shallow copy to prevent unintended side-effects
  my $self = bless({}, $class);
  $self->{_params} = \%params;

  INFO "Opening BiblionumberConversionTable '".$self->p('biblionumberConversionTable')."' for reading";
  $self->{biblionumberConversionTable} = Bulk::ConversionTable::BiblionumberConversionTable->new( $self->p('biblionumberConversionTable'), 'read' );
  INFO "Opening Holding_idConversionTable '".$self->p('holding_idConversionTable')."' for writing";
  $self->{holding_idConversionTable} = Bulk::ConversionTable::SubscriptionidConversionTable->new( $self->p('holding_idConversionTable'), 'write' );

  return $self;
}

sub p($s, $param) {
  die "No such parameter '$param'!" unless (defined($s->{_params}->{$param}));
  return $s->{_params}->{$param};
}

=head2 doImport

Does the dirty deed

import conflicts with require feature.

=cut

sub doImport($s) {
  my $starttime = gettimeofday;

  $preventJoiningBeforeAllWorkIsDone = Thread::Semaphore->new( -1*$s->p('workers') +1 ); #Semaphore blocks until all threads have released it.

  my @threads;
  push @threads, threads->create(\&worker, $s)
    for 1..$s->p('workers');

  my $i = Bulk::Util::getMarcFileIterator($s);
  #Enqueue MFHDs to the job queue. This way we avoid strange race conditions in the file handle
  while (not($SIG_TERMINATE_RECEIVED) && defined(my $mfhd = $i->())) {
    if ($mfhdQueue->pending() > $jobBufferMaxSize) { # This is a type of buffering to avoid loading too much into memory. Wait for a while, if the job queue is getting large.
      TRACE "Thread MAIN - Jobs queued '".$mfhdQueue->pending()."' , sleeping";
      while (not($SIG_TERMINATE_RECEIVED) && $mfhdQueue->pending() > $jobBufferMaxSize/2) {
        Time::HiRes::usleep(100); #Wait for the buffer to cool down
      }
    }

    chomp($mfhd);
    $mfhdQueue->enqueue($mfhd);

    INFO "Queued $. MFHDs" if ($. % 1000 == 0);

    while (my $hid = $hnConversionQueue->dequeue_nb()) {
      $s->{holding_idConversionTable}->writeRow($hid->{old}, $hid->{new});
    }
  }

  # Signal to threads that there is no more work.
  $mfhdQueue->end();

  #This script crashes when threads are being joined, so wait for them to stop working first.
  #It is very hacky, but so far there seems to be no side-effects for it.
  #It is easier to do this, than employ some file-splitting and forking.
  $preventJoiningBeforeAllWorkIsDone->down();

  INFO "Writing remaining '".$hnConversionQueue->pending()."' holding_id conversions";
  while (my $hid = $hnConversionQueue->dequeue_nb()) {
    $s->{holding_idConversionTable}->writeRow($hid->{old}, $hid->{new});
  }
  $s->{holding_idConversionTable}->close(); #Close the filehandle to not lose any data

  my $timeneeded = gettimeofday - $starttime;
  INFO "\n$. MARC records done in $timeneeded seconds\n";

  # Wait for all the threads to finish.
  for (@threads) {
    $_->join();
    INFO "Thread ".$_->tid()." - Joined";
  }

  return undef;
}

sub worker($s) {
  my $tid;
  eval {
  $tid = threads->tid();

  Bulk::Util::invokeThreadCompatibilityMagic();

  while (not($SIG_TERMINATE_RECEIVED) && defined(my $mfhd = $mfhdQueue->dequeue())) {
    DEBUG "Thread $tid - New job";
    TRACE "$$mfhd\n";

    my $record = MARC::Record->new_from_xml($$mfhd, 'UTF-8', 'MARC21');
    # Extracting the controlfield like this is much faster than creating MARC::Record-objects
    my $biblionumberOld = eval {$record->field($s->p('legacyBibIdFieldDef'))->data()};
    if (not($biblionumberOld) || $@) {
      FATAL "MFHD Record is missing field '".$s->p('legacyBibIdFieldDef')."', containing the legacy biblionumber! $@\n$$mfhd\nSKIPPING RECORD!\n";
      next;
    }
    my $biblionumber = $s->{biblionumberConversionTable}->fetch($biblionumberOld);
    unless ($biblionumber) {
      FATAL "No biblionumber mapping for legacy biblionumber '$biblionumberOld'. SKIPPING RECORD!";
      next;
    }

    my $holding_idOld = eval {$record->field( $s->p('legacyIdFieldDef') )->data()};
    if (not($holding_idOld) || $@) {
      FATAL "MFHD Record is missing controlfield '".$s->p('legacyIdFieldDef')."', containing the legacy holding_id! $@\n$$mfhd\nSKIPPING RECORD!\n";
      next;
    }

    my $holding_id = eval { AddHolding( $record, '', $biblionumber ) };
    if ($@) {
      FATAL "Adding a new holding record failed: $@";
      next;
    }

    my %hid :shared = (old => $holding_idOld, new => $holding_id);
    $hnConversionQueue->enqueue(\%hid);
  }

  DEBUG "Thread $tid - Finished";
  };
  if ($@) {
    warn "Thread ".($tid//'undefined')." - died:\n$@\n";
  }

  $preventJoiningBeforeAllWorkIsDone->up(); #This worker has finished working
}

# Copy the C4::Holdings::AddHolding()
# so it can be mutilated

sub AddHolding {
    my $record          = shift;
    my $frameworkcode   = shift;
    my $biblionumber    = shift;
    if (!$record) {
        carp('AddHolding called with undefined record');
        return;
    }

    my $dbh = C4::Context->dbh;

    my $biblio = Koha::Biblios->find( $biblionumber );
    die "No biblio in Koha with biblionumber='$biblionumber'. Is the biblionumber conversion table out of sync?" unless $biblio;
    my $biblioitemnumber = $biblio->biblioitem->biblioitemnumber;

    # transform the data into koha-table style data
    C4::Charset::SetUTF8Flag($record);
    my $rowData = C4::Holdings::TransformMarcHoldingToKoha( $record );

    my ($holding_id) = C4::Holdings::_koha_add_holding( $dbh, $rowData, $frameworkcode, $biblionumber, $biblioitemnumber );

    C4::Holdings::_koha_marc_update_ids( $record, $frameworkcode, $holding_id, $biblionumber, $biblioitemnumber );

    # now add the record
    C4::Holdings::ModHoldingMarc( $record, $holding_id, $frameworkcode );

    C4::Log::logaction( "CATALOGUING", "ADD", $holding_id, "holding" ) if C4::Context->preference("CataloguingLog");
    return $holding_id;
}

1;
