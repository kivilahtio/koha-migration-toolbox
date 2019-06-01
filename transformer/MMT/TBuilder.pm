package MMT::TBuilder;

use MMT::Pragmas;

#External modules
use Text::CSV;
use Time::HiRes;
use threads;
use threads::shared;
use Thread::Semaphore;
use Thread::Queue;

#Local modules
use MMT::Builder;
use MMT::Cache;
use MMT::Tester;
my Log::Log4perl $log = Log::Log4perl->get_logger(__PACKAGE__);

#Add a bit of type-safety
#use fields qw(inputFile outputFile type); # use fields doesn't work with subroutine signatures...


### Threading control
## Thank you https://stackoverflow.com/questions/12696375/perl-share-filehandle-with-threads
# Flag to inform all threads that application is terminating
my $SIG_TERMINATE_RECEIVED :shared = 0;

# Distribute jobs to workers via this structure since a shared file handle can no longer be reliably accessed from threads even when using locks
my $preventJoiningBeforeAllWorkIsDone;
my $inputQueue;
my $outputQueue;

my $jobBufferMaxSize = 500;

my $OUT_FH;

### Threads under control


=head1 NAME

MMT::TBuilder - Threaded builder implementation

=head1 DESCRIPTION

-Dynamically loads the correct Koha object instance to build
-Loads the translation tables, they are accessible by the last part of the translation table class name
-Loads external repositories, to be accessible using the given repository name
-Invokes the correct MMT::Voyager2Koha::Object's new() and build() as per the interface definition for each row
 in the given $inputFile
-Writes transformed .migrateme-"Koha object files" into the configured Export directory

=head2 SYNOPSIS

  my $b = MMT::TBuilder->new({
    type => 'Item',
    inputFile => '02-items.csv',
    repositories => [
      {name => "Last borrow dates", file => "02-borrow-dates.csv", keys => ['barcode']},
      ...
    ],
    translationTables => [
      {name => "LocationId", params => [1,2,3]},
      ...
    ],
  });

=cut

sub new($class, $params) {
  $log->trace("Constructor(@_)") if $log->is_trace();
  my $s = bless($params, $class);


  $log->logdie("$class attribute 'type' is not defined") unless $s->{type};

  $s->{inputFile} = MMT::Config::exportsDir."/".$s->{inputFile};
  $s->{outputFile} = MMT::Config::kohaImportDir.'/'.($s->{outputFile} ? $s->{outputFile} : $s->{type}.'.migrateme');
  MMT::Builder::_loadRepositories($s);
  MMT::Builder::_loadTranslationTables($s);
  $s->{tester} = MMT::Tester->new(MMT::Config::testDir.'/'.$s->{type}.'.yaml');

  #prepare reader
  $s->{inputFile} =~ /\.(\w+)?$/;
  $s->{fileType} = $1;
  $log->debug("Input file '".$s->{inputFile}."' is of type '".$s->{fileType}."'");
  if ($s->{fileType} eq 'csv') {
    $s->openCsvFile();
    $s->{next} = $s->getCsvIterator();
  }
  elsif ($s->{fileType} eq 'marcxml') {
    $s->{next} = $s->getMarcFileIterator(); #Drop a closure
  }
  else {
    $log->logdie("Unknown input file type '$s->{fileType}' for file '$s->{inputFile}'");
  }

  #prepare writer
  $log->info("Opening file '".$s->{outputFile}."' for export");
  open($s->{outFH}, '>:encoding(UTF-8)', $s->{outputFile}) or $log->logdie("Opening file '".$s->{outputFile}."' failed: $!");

  #Identify the class package
  $s->{objectClass} = 'MMT::'.MMT::Config->sourceSystemType.'2Koha::'.$s->{type};
  MMT::Builder::__dynaload($s->{objectClass});

  return $s;
}

=head2 now

 @returns The current datetime in ISO8601 YYYY-MM-DDTHH:MM:SS

=cut

sub now($s) {
  unless ($s->{now}) {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $s->{now} = sprintf("%04d-%02d-%02dT%02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
  }
  return $s->{now};
}

my $i = 0; #Track how many KohaObjects are processed
my $w = 0; #Track how many KohaObjects actually survived the build
sub build($s) {
  $log->info($s->{type}." - Starting to build");

  my $starttime = Time::HiRes::gettimeofday;


  if (not(MMT::Config::workers())) { #non-threaded logic for clarity on what actually happens unde the hood
    while (defined(my $textPtr = $s->{next}->())) {
      $i++;
      my $textPtr = $s->task($textPtr);
      $s->writeToDisk($textPtr) if $textPtr;
    }
  }
  else { #>Thread logic starts
    $log->info("Multithreading with '".MMT::Config::workers()."' workers.");
    #Override signals to gracefully terminate
    $SIG{INT} = $SIG{TERM} = sub {
      print("\n>>> Terminating <<<\n\n");
      $SIG_TERMINATE_RECEIVED = 1;
    };
    $inputQueue = Thread::Queue->new();
    $outputQueue = Thread::Queue->new();

    $preventJoiningBeforeAllWorkIsDone = Thread::Semaphore->new( -1*MMT::Config::workers() +1 ); #Semaphore blocks until all threads have released it.

    my @threads;
    push @threads, threads->create(\&_worker, $s)
      for 1..MMT::Config::workers();

    #Enqueue MFHDs to the job queue. This way we avoid strange race conditions in the file handle
    while (not($SIG_TERMINATE_RECEIVED) && defined(my $record = $s->{next}->())) {
      $i++;

      my $wait;
      if ($inputQueue->pending() > $jobBufferMaxSize) { # This is a type of buffering to avoid loading too much into memory. Wait for a while, if the job queue is getting large.
        $log->debug("Thread MAIN - Jobs queued '".$inputQueue->pending()."' , sleeping") if $log->is_debug();
        while (not($SIG_TERMINATE_RECEIVED) && $inputQueue->pending() > $jobBufferMaxSize/2) {
          $s->_purgeOutputBuffer();
          Time::HiRes::usleep(100); #Wait for the buffer to cool down
        }
      }

      chomp($record);
      $inputQueue->enqueue($record);
      $i++;

      $log->info("Queued $. Records") if ($. % 1000 == 0);

      $s->_purgeOutputBuffer();
    }

    # Signal to threads that there is no more work.
    $inputQueue->end();

    #This script crashes when threads are being joined, so wait for them to stop working first.
    #It is very hacky, but so far there seems to be no side-effects for it.
    #It is easier to do this, than employ some file-splitting and forking.
    $preventJoiningBeforeAllWorkIsDone->down();

    $log->info("Writing remaining '".$outputQueue->pending()."' records");
    $s->_purgeOutputBuffer();

    # ((((: Wait for all the threads to finish. :DDDDDDD
    for (@threads) {
      $_->join();
      $log->info("Thread ".$_->tid()." - Joined");
    }
    # :XXXX
  } #<Thread logic ends

  my $timeneeded = Time::HiRes::gettimeofday - $starttime;
  $log->info("\n$. records done in $timeneeded seconds\n");

  close $s->{outFH};
  close $s->{inFH} if $s->{inFH};
  $log->info("Built, $w/$i objects survived");

  return undef; #Getopt::OO callback errors if we return something.
}

=head2 task

The core build task the workers perform without any of the threading fluff

 @param {String ref} The data from disk to turn into something great!
 @returns {String ref} The transformed data to write to disk.

=cut

sub task($s, $textPtr) {
  my $o;
  if ($s->{fileType} eq 'csv') {
    eval {
      my @colNames = $s->{csv}->column_names();
      $o = {};
      $s->{csv}->bind_columns(\@{$o}{@colNames});
      $s->{csv}->parse($$textPtr);
    };
    if ($@) {
      $log->error("Unparseable .csv-row!\n$@\nThe unparseable row follows\n$$textPtr");
      return;
    }

    if ($o->{DUPLICATE}) {
      $log->debug("Duplicate entry skipped at input file line '$.'");
      return;
    }
  }
  else {
    $o = $textPtr;
  }

  my $ko = $s->{objectClass}->new(); #Instantiate first, so we get better error handling when we can catch the failed object when building it.
  eval {
    $ko->build($o, $s);
  };
  if ($@) {
    if (ref($@) eq 'MMT::Exception::Delete') {
      $log->error($ko->logId()." was dropped. Reason: ".$@->error) if $log->is_error();
    }
    else {
      $log->fatal("Received an unhandled exception '".MMT::Validator::dumpObject($@)."'") if $log->is_fatal();
    }
    return undef; #Prevent implicit truthy return from getting put to the write queue
  }
  else {
    $log->debug("Writing ".$ko->logId()) if $log->is_debug();
    $s->{tester}->test($ko);
    return $ko->serialize();
  }
}

=head2 _worker

Deals with the threading layer. All business logic is in the task()

=cut

sub _worker($s) {
  my $tid;
  eval {
    $tid = threads->tid();

    while (not($SIG_TERMINATE_RECEIVED) && defined(my $textPtr = $inputQueue->dequeue())) {
      $log->trace("Thread $tid - New job");
      $textPtr = $s->task($textPtr);
      $outputQueue->enqueue($textPtr);
    }
  };
  if ($@) {
    $log->fatal("Thread ".($tid//'undefined')." - died:\n$@\n");
  }

  $preventJoiningBeforeAllWorkIsDone->up(); #This worker has finished working
}

=head2 writeToDisk

Write the output job queue to disk

=cut

sub writeToDisk($s, $textPtr) {
  print { $s->{outFH} } $textPtr, "\n";
  $w++;
}

sub _purgeOutputBuffer($s) {
  while (my $textPtr = $outputQueue->dequeue_nb()) {
    $s->writeToDisk($textPtr);
  }
}

=head2 getTextIterator

 @returns Subroutine, call this to get a reference to the text chunk
          undef, if nothing more to fetch

=cut

sub getTextIterator($s, $input_record_separator=undef) {
  local $INPUT_RECORD_SEPARATOR = $input_record_separator if defined $input_record_separator; #Let perl split text for us in proper chunks
  open($s->{inFH}, '<:encoding(UTF-8)', $s->{inputFile}) or die("Opening the file '$s->{inputFile}' for iteration failed: $!")
    unless $s->{inFH};

  my $_i;
  $_i = sub {
    local $INPUT_RECORD_SEPARATOR = $input_record_separator if defined $input_record_separator;
    my $textPtr = $s->_getChunk($s->{inFH});
    return undef unless defined $textPtr;

    $$textPtr =~ s/(?:^\s+)|(?:\s+$)//gsm; #Trim leading and trailing whitespace

    return $textPtr;
  };
  return $_i;
}

=head2 getCsvIterator

Checks the row for .csv parsing issues before passing it on. Trying to recover from various issues regarding .csv-parsing.
Because complex data structure sharing with Perl's multithreading capabilities is excruciatingly slow, we need to
serialize the parsed .csv columns back to a string to move it around.

=cut

sub getCsvIterator($s, $input_record_separator=undef) {
  local $INPUT_RECORD_SEPARATOR = $input_record_separator if defined $input_record_separator; #Let perl split text for us in proper chunks
  open($s->{inFH}, '<:encoding(UTF-8)', $s->{inputFile}) or die("Opening the file '$s->{inputFile}' for iteration failed: $!")
    unless $s->{inFH};

  my $csv = Text::CSV->new(MMT::Config::csvInputNew());

  my $_i;
  $_i = sub {
    my ($recursionDepth) = @_;
    local $INPUT_RECORD_SEPARATOR = $input_record_separator if defined $input_record_separator;

    my $verifiedCsvString = eval {
      my $cols = $csv->getline($s->{inFH});
      if ($csv->error_diag() && $csv->error_diag() !~ /^EOF - End of data in parsing input stream/) {
        $log->error("Parsing a new .csv row from file '".$s->{inputFile}."' failed:\n".$csv->error_diag);
        return '!ERROR!';
      }
      return undef unless $cols;

      $csv->combine(@$cols) || $log->error("Combining the parsed .csv-row failed:\n".$csv->error_diag);
      return $csv->string();
    };
    if ($@) {
      $log->error("Unparseable .csv-row!\n$@");
      $verifiedCsvString = '!ERROR!';
    }
    if (not(defined($verifiedCsvString))) {
      return undef;
    }
    elsif ($verifiedCsvString !~ /^!ERROR!$/) {
      return \$verifiedCsvString;
    }
    else {
      return $_i->(($recursionDepth ? $recursionDepth+1 : 1)) if (not($recursionDepth) || $recursionDepth < 5);
      $log->logdie("Broken .csv. Too deep recursion '$recursionDepth' to recover.");
    }
  };
  return $_i;
}

=head2 openCsvFile

=cut

sub openCsvFile($s) {
  $s->{csv} = Text::CSV->new(MMT::Config::csvInputNew());
  open($s->{inFH}, '<:encoding(UTF-8)', $s->{inputFile}) or $log->logdie("Loading file '".$s->{inputFile}."' failed: $!");
  $s->{csv}->header($s->{inFH}, MMT::Config::csvInputHeader());
  $log->info("Loading file '".$s->{inputFile}."', identified columns '".join(',', $s->{csv}->column_names())."'");
  return $s->{csv}; #Have a meaningful truthy return value
}

=head2 getMarcFileIterator

  my $i = $s->getMarcFileIterator();
  my ($marcXmlPointer) = $i->();

The Marc::Record -package from CPAN is dreadfully slow for complex mutations.
Supercharge it.

 @returns Subroutine, call this to get XML as a reference to String

=cut

sub getMarcFileIterator($s) {
  local $INPUT_RECORD_SEPARATOR = '</record>'; #Let perl split MARCXML for us
  open($s->{inFH}, '<:encoding(UTF-8)', $s->{inputFile}) or die("Opening the MARC file '$s->{inputFile}' for slurping failed: $!") # Make sure we have the proper encoding set before handing these to the MARC-modules
    unless $s->{inFH};

  my $_i;
  $_i = sub {
    my ($recursionDepth) = @_;
    local $INPUT_RECORD_SEPARATOR = '</record>'; #Let perl split MARCXML for us
    my $textPtr = $s->_getChunk($s->{inFH});
    return undef unless defined $textPtr;

    $$textPtr =~ s/\s+$//gsm; #Trim trailing whitespace
    #Trim colection information or other whitespace fluff
    $$textPtr =~ s!^.+?<record!<record!sm;
    $$textPtr =~ s!</record>.+$!</record>!sm;

    unless ($$textPtr =~ /<record.+?<\/record>/sm) {
      $log->fatal("Broken MARCXML:\n$$textPtr");
      return $_i->(($recursionDepth ? $recursionDepth+1 : 1)) if (not($recursionDepth) || $recursionDepth < 5);
      $log->logdie("Broken MARCXML. Too deep recursion '$recursionDepth' to recover.:\n$$textPtr");
    }
    return $textPtr;
  };
  return $_i;
}

sub _getChunk($s, $FH) {
  my $text = <$FH>;
  unless (defined($text)) {
    if ($!) {
      $log->logdie("Trying to read a chunk of text from file '$s->{inputFile}' failed: $!");
    }
    $log->debug("No more text in file '$s->{inputFile}'");
    return undef;
  }
  return \$text;
}

return 1;
