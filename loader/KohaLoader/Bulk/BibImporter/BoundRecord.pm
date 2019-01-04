package Bulk::BibImporter::BoundRecord;

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
use Bulk::BibImporter;

sub migrate($s, $record, $recordXmlPtr) {
  #Check if this is marked to be a bound biblio by the migration pipeline
  my $f773i = $record->subfield('773', 'i');
  unless ($f773i && $f773i eq 'Bound biblio') {
    return;
  }

  #Check if some worker thread has already created the bound bib parent record.
  my $f773w = $record->subfield('773', 'w') or die("Record has 773\$i and looks like a bound biblio, but doesn't have 773\$w which points to the reserved bound bib parent record biblionumber. Erroneus record dump: $$recordXmlPtr\n");
  unless (C4::Biblio::GetBiblio($f773w)) {
    return (_createBoundBibParentRecord($s, $record, $f773w), $f773w);
  }
  return undef; #Prevent implicit returning of the result of C4::Biblio::GetBiblio when there is nothing to add.
}

sub _createBoundBibParentRecord($s, $boundBibRecord, $parentBiblionumber) {
  my $parent = $boundBibRecord->clone();

  #Prepare hex id
  my @set = ('0' ..'9', 'A' .. 'F');
  my $hexId = join '' => map $set[rand @set], 1 .. 8;
  my $title = "Bound biblio parent record $hexId";

  $parent->field('001')->update($parentBiblionumber); #Bound bibs can link to this parent now #TODO: Needs to be biblionumberConversionTable:able
  $parent->field('245') ?
      $parent->field('245')->update(a => $title) : #This is clearly distinguished as a temporary placeholder that needs to be manually fixed.
      $parent->insert_fields_ordered(MARC::Field->new('245', 'a' => $title));

  my @link_fields = $parent->field('773');
  $parent->delete_fields(@link_fields);

  return Bulk::BibImporter::addRecordFast($s, $parent, \$parent->as_xml_record('MARC21'), $parentBiblionumber);
}

1;
