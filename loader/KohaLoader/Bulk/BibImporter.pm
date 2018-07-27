package Bulk::BibImporter;

#Pragmas
use Modern::Perl;
use experimental 'smartmatch', 'signatures';
binmode( STDOUT, ":encoding(UTF-8)" );
binmode( STDIN,  ":encoding(UTF-8)" );
use utf8;
use Carp;
#$|=1; #Are hot filehandles necessary?

# External modules
use Time::HiRes qw(gettimeofday);
use Log::Log4perl qw(:easy);

# Koha modules used
use MARC::File::XML;
use MARC::Batch;#
use C4::Context;
use C4::Biblio;

#Local modules
use Bulk::ConversionTable::BiblionumberConversionTable;

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

  my $oplibMatcher;
  if ($s->p('matchLog')) {
    die ("Bulk::OplibMatcher is TODO for ElasticSearch");
    $oplibMatcher = Bulk::OplibMatcher->new($s->p('matchLog'), $s->p('verbose'));
  }

  INFO "Opening BiblionumberConversionTable '".$s->p('biblionumberConversionTable')."' for writing";
  $s->{biblionumberConversionTable} = Bulk::ConversionTable::BiblionumberConversionTable->new( $s->p('biblionumberConversionTable'), 'write' );

  my $next = $s->getMarcFileIterator();

  my $i=0;
  while (1) {
    my ($record, $recordXmlPtr) = eval { $next->() };
    if ( $@ ) {
      print "Bad MARC record $i: $@ skipped\n";
      next;
    }
    last unless ($record);
    $i++;
    INFO "Processed $i Bibs" if ($i % 100 == 0);

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
    $s->{biblionumberConversionTable}->writeRow($legacyBiblionumber, $matchedBiblionumber // $newBiblionumber // 0, $operation, $statusOfOperation);
  }

  my $timeneeded = gettimeofday - $starttime;
  print "\n$i MARC records done in $timeneeded seconds\n";
}


=head2 getMarcFileIterator

 @returns Subroutine, call this to get a list of:
                      [0] -> the next MARC::Record
                      [1] -> XML as String

=cut

sub getMarcFileIterator($s) {
  if ($s->p('migrateStrategy') eq 'fast') {
    INFO "Slurping MARC XML chunks"; #This is memory intensive, timing it via logger
    my $recordsAsXml = $s->_slurpMarcFile();
    INFO "Done slurping MARC XML chunks";
    my $i = 0;
    return sub {
      return undef unless ($i < scalar(@$recordsAsXml));
      return (MARC::Record->new_from_xml($recordsAsXml->[$i], 'UTF-8', 'MARC21'), \$recordsAsXml->[$i++]);
    };
  }
  elsif ($s->p('migrateStrategy') eq 'koha') {
    my $batch = $s->_openMarcFile();
    return sub {return ($batch->next(), undef)}; #No access to the plain XML this way
  }
}

sub _slurpMarcFile($s) {
  local $/ = undef;
  open(my $FH, '<:encoding(UTF-8)', $s->p('inputMarcFile')) or die("Opening the MARC file '".$s->p('inputMarcFile')."' for slurping failed: $!"); # Make sure we have the proper encoding set before handing these to the MARC-modules
  my $xmls = <$FH>;
  my @xmls = $xmls =~ /(<record>.+?<\/record>)/gsm;
  return \@xmls;
}

sub _openMarcFile($s) {
  open(my $FH, '<:encoding(UTF-8)', $s->p('inputMarcFile')) or die("Opening the MARC file '".$s->p('inputMarcFile')."' for reading failed: $!"); # Make sure we have the proper encoding set before handing these to the MARC-modules
  $MARC::File::XML::_load_args{BinaryEncoding} = 'UTF-8';
  $MARC::File::XML::_load_args{RecordFormat} = 'USMARC';
  my $file = MARC::File::XML->in($FH) or die("Loading MARC File '".$s->p('inputMarcFile')."' with MARC::File failed: ".$MARC::File::ERROR);
  return $file;
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
  if ($s->p('migrateStrategy') eq 'fast') {
    $s->addRecordFast($record, $recordXmlPtr, $legacyBiblionumber);
  }
  elsif ($s->p('migrateStrategy') eq 'koha') {
    $s->addRecordKoha($record, $recordXmlPtr, $legacyBiblionumber);
  }
  else {
    die ("Unknown migration strategy '".$s->p('migrateStrategy')."'");
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
  my $frameworkcode = '';
  my $olddata = C4::Biblio::TransformMarcToKoha($record, $frameworkcode);
  my ($newBiblionumber, $error1)     = C4::Biblio::_koha_add_biblio($dbh, $olddata, $frameworkcode);
  if ($error1) {
    ERROR "Error1=$error1";
    return ("insert", "ERROR1", $newBiblionumber);
  }

  $olddata->{'biblionumber'} = $newBiblionumber;
  my ($newBiblioitemnumber, $error2) = C4::Biblio::_koha_add_biblioitem($dbh, $olddata);
  if ($error2) {
    ERROR "Error2=$error2";
    return ("insert", "ERROR2", $newBiblionumber);
  }

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

return 1;
