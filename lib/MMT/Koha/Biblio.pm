package MMT::Koha::Biblio;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::Shell;
use MMT::MARC::Regex;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::Koha::Biblio - Transform biblios

=cut

=head2 build

 @param {String reference} Voyager xml record
 @param {TBuilder}

=cut

sub build($s, $xmlPtr, $b) {
  $s->{biblionumber} = MMT::MARC::Regex->controlfield($xmlPtr, '001');
  unless ($s->{biblionumber}) {
    MMT::Exception::Delete->throw(error => "Missing field 001 with record:\n$$xmlPtr\n!!");
  }

  MMT::MARC::Regex->controlfield($xmlPtr, '003', MMT::Config::organizationISILCode(), {after => '001'});

  $s->isSuppressInOPAC($xmlPtr, $b);
  $s->linkBoundRecord($xmlPtr, $b);
  $s->translateLinks($xmlPtr, $b);

  if ($$xmlPtr =~ s!<subfield code="9">([^0-9]+)</subfield>!!gsm) {
    $log->trace($s->logId().". Subfield \$9 = '$1' dropped. \$9 must be a number!") if $log->is_trace();
  }

  $s->{xmlPtr} = $xmlPtr;
  return $s;
}

sub logId($s) {
  return "Biblio '".$s->id()."'";
}

sub id($s) {
  return $s->{biblionumber};
}

sub serialize($s) {
  return ${$s->{xmlPtr}}."\n";
}

=head2 isSuppressInOPAC

Sets the 942$n if the holding record is suppressed in OPAC

=cut

sub isSuppressInOPAC($s, $xmlPtr, $b) {
                                       #Key for the info is built with bib_id.mfhd_id.location_id
  my $suppressInOpac = $b->{SuppressInOpacMap}->get($s->id().'NULLNULL');
  if ($suppressInOpac) {
    $suppressInOpac = $suppressInOpac->[0]->{suppress_in_opac};
    $log->debug($s->logId()." - Suppress in opac '$suppressInOpac'") if $log->is_debug();

    MMT::MARC::Regex->datafield($xmlPtr, '942', 'n', $suppressInOpac);
  }
}

=head2 linkBoundRecord

Link this Bib under the bound bib's parent record.
Executes only if this Bib is a bound record.

Bound parent record is transparently created if missing in the Loader, because due to the Perl's multi-threading nature of share-nothing, communicating the creation
of the bound parent bib is very difficult and communicating between processes is extra slow.
It is much easier to just spam the DB during loading to check if the bound parent record already exists or not.

=cut

sub linkBoundRecord($s, $xmlPtr, $b) {
  my $boundParent = $b->{BoundBibParent}->get($s->id());
  return unless $boundParent;

  $boundParent = $boundParent->[0]->{bound_parent_bib_id};
  die($s->logId()." - Bound parent biblionumber '$boundParent' is not a valid digit?") unless ($boundParent =~ /^\d+$/);

  $log->info($s->logId()." is a part of a bound record. Linking it under the reserved bound parent record biblionumber '$boundParent'");
  if (my $f773w = MMT::MARC::Regex->datafield($xmlPtr, '773', 'w')) {
    $log->warn($s->logId()." already has Field '773\$w'with value '$f773w'. This is overwritten with '$boundParent'. Sorry."); #TODO: Try to figure out a good solution if we encounter bound bibs which are also component parts.
  }
  MMT::MARC::Regex->datafield($xmlPtr, '773', 'w', $boundParent); #Overwrites any existing field 773
  MMT::MARC::Regex->subfield($xmlPtr, '773', 'i', 'Bound biblio');
  MMT::MARC::Regex->subfield($xmlPtr, '773', 't', 'Bound biblio parent record');
}

=head2 translateLinks

Voyager has multiple possible linking types, such as
  HOST      - component part link from host to child
  COMP      - component part link from child to host
  ISSNPREC  - serial biblio's previous number
  ISSNSUCC  - serial biblio's next number
for the exhaustive list, see. voyager.dup_detection_profile

Koha currently only supports one link type,
component part 773w -> host 001

Extractor provides a list/repository of parent-to-child bib_ids.

Here we check if the biblio at hand is something we can link in Koha and enforces a proper Koha-linkage.

=cut

sub translateLinks($s, $xmlPtr, $b) {
  my $linksBySource = $b->{BibLinkRelationsBySource}->get($s->id()); #Use biblionumber to get all the relations starting from this record
  my $linksByDest = $b->{BibLinkRelationsByDest}->get($s->id());   #Use biblionumber to get all the relations ending at this record

  return unless ($linksBySource || $linksByDest);

  $log->debug($s->logId()." - Found '".($linksBySource ? scalar(@$linksBySource) : 0)."' links by source, '".($linksByDest ? scalar(@$linksByDest) : 0)."' links by destination") if $log->is_debug();

  # A bib can have multiple instances of a link pointing to different targets.
  # Keep track of how many times a certain type of link is used for to track the n-th MARC Field repetition the link refers to.
  #   This is presuming the biblio link indexes are indexed in the order the Fields are present in the MARC Record.
  my %linkFieldIndex;

  for my $link (@$linksBySource) {
    my $linkConfig = $b->{BibLinkTypes}->translate($s, $xmlPtr, $b, $link->{dup_profile_code});
    next unless $linkConfig->{do};
    next if $linkConfig->{reverseLookup};
    $s->_linkFix($linkConfig, $link, $xmlPtr, \%linkFieldIndex);
  }
  for my $link (@$linksByDest) {
    my $linkConfig = $b->{BibLinkTypes}->translate($s, $xmlPtr, $b, $link->{dup_profile_code});
    next unless $linkConfig->{do};
    next unless $linkConfig->{reverseLookup};
    $s->_linkFix($linkConfig, $link, $xmlPtr, \%linkFieldIndex);
  }
}

sub _linkFix($s, $linkConfig, $link, $xmlPtr, $linkFieldIndex) {
  my $sourceFieldCode         = ($linkConfig->{reverseIndex}) ? substr($link->{dest_index}, 0, 3) : substr($link->{source_index}, 0, 3);
  my $destinationBiblionumber = ($linkConfig->{reverseIds})   ? $link->{source_bibid}             : $link->{dest_bibid};

  $log->trace($s->logId()." - _linkFix() :> \$linkConfig='".$link->{dup_profile_code}."', \$sourceFieldCode='$sourceFieldCode', \$destinationBiblionumber='$destinationBiblionumber'") if $log->is_trace();
  $log->trace($s->logId().Data::Printer::np($link)) if $log->is_trace();

  unless ($sourceFieldCode eq $linkConfig->{expectedSourceField}) {
    $log->warn($s->logId()." - Voyager link type is '".$link->{dup_profile_code}."', but the source field '$sourceFieldCode' is not of the expected field code '".$linkConfig->{expectedSourceField}."'? This is atypical.");
  }

  if (my $fields = MMT::MARC::Regex->datafields($xmlPtr, $sourceFieldCode)) {
    my $fieldIndex = $linkFieldIndex->{ $link->{dup_profile_code}.$sourceFieldCode.$link->{seqnum} }++ || 0; #Keep track of how many times a single link type for a specific field code has appeared, pick the correct Field for mutation.
    my $targetField = $fields->[$fieldIndex];
    if (@$fields > 1) {
      $log->warn($s->logId()." - Multiple instances of repeated link field '$sourceFieldCode'. Picking Field index '$fieldIndex'. The link transformation might be inaccurate.") if $log->is_warn();
    }
    unless ($targetField) {
      $log->warn($s->logId()." - Link field '$sourceFieldCode' repeated, but no matching Field index '$fieldIndex' exists?. Creating a new Field. The link transformation might be inaccurate.") if $log->is_warn();
      $s->_linkCreateField($xmlPtr, $b, $sourceFieldCode, $destinationBiblionumber);
      next;
    }

    my $sfW = $targetField->subfield('w');
    if ($sfW && ($sfW eq $destinationBiblionumber || $sfW =~ m!\(.+?\)$destinationBiblionumber!)) {
      $log->trace($s->logId()." - Link validated, using \$linkConfig='".$link->{dup_profile_code}."', \$sourceFieldCode='$sourceFieldCode', \$destinationBiblionumber='$destinationBiblionumber'") if $log->is_trace();
    }
    elsif (! $sfW) {
      $log->trace($s->logId()." - Voyager link type '".$link->{dup_profile_code}."' is missing 'w'. Autovivificating.") if $log->is_trace();
    }
    elsif ($sfW ne $destinationBiblionumber) {
      $log->warn($s->logId()." - Voyager link type '".$link->{dup_profile_code}."' has a bad destination biblionumber '$sfW'. Should be '$destinationBiblionumber'. Fixing.") if $log->is_warn();
    }

    $targetField->subfield('w', _linkCreateSubfieldW($destinationBiblionumber));
    MMT::MARC::Regex->replace($xmlPtr, $targetField);
    $log->trace($s->logId()." - Replaced field '$sourceFieldCode' subfield 'w' with '"._linkCreateSubfieldW($destinationBiblionumber)."'") if $log->is_trace();
  }
  else {
    $log->warn($s->logId()." - Linking MARC21 Field missing for Voyager link type '".$link->{dup_profile_code}."' to destination '$destinationBiblionumber'") if $log->is_warn();

    $s->_linkCreateField($xmlPtr, $b, $sourceFieldCode, $destinationBiblionumber);
  }
}
sub _linkCreateSubfieldW($targetBiblionumber) {
  return '('.MMT::Config::organizationISILCode().')'.$targetBiblionumber;
}
sub _linkCreateField($s, $xmlPtr, $b, $sourceFieldCode, $destinationBiblionumber) {
  MMT::MARC::Regex->subfield($xmlPtr, $sourceFieldCode, 'w', _linkCreateSubfieldW($destinationBiblionumber));
  MMT::MARC::Regex->subfield($xmlPtr, $sourceFieldCode, 't', _linkCreateSubfieldW($destinationBiblionumber)); # subfield t is mandatory so we just put whatever is available here.
  $log->trace($s->logId()." - Created field '$sourceFieldCode' subfield 'w' with '"._linkCreateSubfieldW($destinationBiblionumber)."'") if $log->is_trace();
}

###########################################################################################
###########################################################################################

=head2 usemarcon

Use usemarcon to do the transformation.

=cut

sub usemarcon() {
  my $inputMARCFile = MMT::Config::voyagerExportDir()."/biblios.marcxml";
  my $outputMARCFile = MMT::Config::kohaImportDir()."/biblios.marcxml";
  my $cmd = "usemarcon/usemarcon usemarcon/rules-hamk/rules.ini $inputMARCFile $outputMARCFile";
  my ($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = MMT::Shell::run($cmd);
  return !$success; # Getopt::OO callback errors if we return something.
}

return 1;
