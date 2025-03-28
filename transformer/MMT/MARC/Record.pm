package MMT::MARC::Record;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::MARC::Field;
use MMT::MARC::Subfield;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::MARC::Record - MARC Record implementation using the HashList data structure

=head1 DESCRIPTION

This beats MARC::Record in internal editing performance by factors, at the expense of a more intense memory footprint.

=head1 COPYRIGHT

Koha-Suomi Oy 2015

=head1 REPOSITORY

https://github.com/KohaSuomi/OrigoMMTPerl

=head2 DATA STRUCTURE

$Record =
{
    leader => {
	"LEADER TEXT STRING"
    },
    fields => {
        001 => [
            0 => {
                i1 => "1",
                i2 => "0",
                a => [
                    0   => "subfield content",
                    1 => "repeated subfield content",
                    n => "nth subfield content"
                ],
                x => [...]
            }
            n => {...}
        ]
        nnn => [...]
    }
}

=cut

sub new {
  my $class = shift;
  my $self = {@_};

  #initialize the owned fields reference array
  $self->{fields} = [];

  bless($self, $class);
  return $self;
}

sub newFromXml {
  my ($class, $xmlPtr) = @_;
  my $self = $class->new();

  my (@fields, @subfields);

  unless ($$xmlPtr =~ m!^\s*<record.*?>(.+?)</record>\s*$!sm) {
    die "Bad MARC record:\n$$xmlPtr\n";
  }
  my $fields = $1;

  unless ($fields =~ m!<leader>(.+?)</leader>!sm) {
    die "Bad MARC leader:\n$$xmlPtr\n";
  }
  $self->leader($1);

  unless (@fields = $fields =~ m!
                  <(data|control)field\s+tag="(\d+)"     #Extract field type and code
                    (?:\s+ind1="(.?)"\s+ind2="(.?)")?    #Optional indicators
                  >                                      #End field starting element
                  \s*                                    #Let go of surrounding whitespace
                    (.+?)                                #Capture everything inside the field as the subfields
                  \s*                                    #Let go of surrounding whitespace
                  </(?:data|control)field>               #Until we reach the end of field
  !gsmx) {                                               #Extract as many of these MARC::Field matches as can be found
    die "Bad MARC fields:\n$fields\n";
  }
  for (my $i=0 ; $i<@fields ; $i+=5) {
    my ($type, $code, $ind1, $ind2, $subfields) = ($fields[$i], $fields[$i+1], $fields[$i+2], $fields[$i+3], $fields[$i+4]);

    $log->debug("New Field: type='".$type."', code='".$code."', ind1='".($ind1//'')."', ind2='".($ind2//'')."'");
    my $field = MMT::MARC::Field->new($code, $ind1, $ind2);
    $self->addField($field);

    if ($field->isControlfield) {
      $field->addSubfield('0', $subfields);
    }
    else {
      unless (@subfields = $subfields =~ m!
                    <subfield\s+code="(.)">                #Pick the subfield code
                    \s*                                    #Let go of surrounding whitespace
                      (.+?)                                #Capture everything inside the subfield as the contents
                    \s*                                    #Let go of surrounding whitespace
                    </subfield>                            #Until we reach the end of subfield
      !gsmx) {
        die "Bad MARC subfields:\n$subfields\n";
      }

      for (my $j=0 ; $j<@subfields ; $j+=2) {
        my ($code, $content) = ($subfields[$j], $subfields[$j+1]);

        $log->debug("New Subfield: code='".($code//'undef')."', content='".($content//'undef')."'");
        my $subfield = MMT::MARC::Subfield->new($code, $content);
        $field->addSubfield($subfield);
      }
    }
  }

  return $self;
}

=head2 serialize

MARC serialization to MARCXML

COPYRIGHT Koha-Suomi Oy
Originally from https://github.com/KohaSuomi/OrigoMMTPerl

=cut

sub serialize($r) {
  my $fieldType;

  my @sb; #Initialize a new StringBuilder(TM) to collect all printable text for one huge IO operation.

  push @sb, '<record format="MARC21" type="Bibliographic" xmlns="http://www.loc.gov/MARC21/slim">'."\n";
  push @sb, '  <leader>'.($r->leader || '').'</leader>'."\n";

  ##iterate all the fields
  foreach my $f ( @{$r->getAllFields("sorted")} ) {

    unless ($f->code()) {
      $log->warning("Biblio docId '".$r->docId."' has an empty field!");
    }

    if($f->isControlfield) {
      push @sb, '  <controlfield tag="'.$f->code.'">';
      my $sf = $f->getUnrepeatableSubfield('0');
      push @sb, $sf->content;
      push @sb, "</controlfield>\n";
    }
    else {
      push @sb, '  <datafield tag="'.$f->code.'" ind1="'.$f->indicator(1).'" ind2="'.$f->indicator(2).'">';
      foreach my $sf (  @{ $f->getAllSubfields() }  ) {
        push @sb, "\n".'    <subfield code="'.$sf->code.'">'.$sf->contentXMLEscaped.'</subfield>';
      } #EndOf subfields iteration
      push @sb, "\n  </datafield>\n";
    }
  } #EndOf fields iteration
  push @sb, '</record>'."\n";

  return join('',@sb);
}

#Receives either a 3-digit field identifier or a MARC:Field-object
sub addField {
  my $self = shift;
  my $field = shift;
  my $fieldNumber;

  unless ($field) {
    print "Record '".$self->docId()."'. Trying to add field with no field code!\n";
    return undef;
  }

  #Make sure the storable object is a MARC::Field, if not then make one out of it, if possible
  unless (ref $field eq 'MMT::MARC::Field') {
    $field = MMT::MARC::Field->new($field);
  }

  if ( exists $self->{$field->code} && ref $self->{$field->code} eq 'ARRAY' ) {
    push @{$self->{$field->code}}, $field;
  }
  else {
    $self->{$field->code} = [$field];
  }

  #Set this MARC::Record as the parent of the newly created MARC::Field
  $field->parent($self);

  #update the owned fields reference list
  push @{$self->{fields}}, $field;
  return $field;
}
#PARAM1 = the field code, whose every instance is removed from this record, eg. '245'
sub deleteFields {
  my $self = shift;
  my $field = shift;

  if (defined $self->{$field} && ref $self->{$field} eq "ARRAY") {

    #iterate the owned fields reference list, {fields}, backwards so splicing the array causes no issues during iteration.
    for ( my $index = @{$self->{fields}}-1; $index >= 0; --$index ) {
      splice( @{$self->{fields}}, $index, 1 ) if ($self->{fields}->[$index]->code() eq $field);
    }

    #Finalize the delete by removing hash->array references and DESTROY:ing the object
    while (my $delme = pop @{$self->{$field}}) {
      $delme->DESTROY();
      undef $delme;
    }
    delete $self->{$field};
  }
}
#param1 = the Field object reference
sub deleteField {
  my $self = shift;
  my $field = shift;
  my $code = $field->code();

  #remove the given field from the hash->array data structure
  for ( my $i = @{$self->{$code}}-1; $i >= 0; --$i ) {
    if ( $self->{$code}->[$i] eq $field) {
      splice( @{$self->{$code}}, $i, 1 );
      last();
    }
  }
  delete $self->{$code} if scalar @{$self->{$code}} == 0;

  #iterate the owned fields reference list, {fields}, backwards so splicing the array causes no issues during iteration.
  for ( my $index = @{$self->{fields}}-1; $index >= 0; --$index ) {
    if ($self->{fields}->[$index] eq $field) {
      splice( @{$self->{fields}}, $index, 1 );
      last();
    }
  }

  $field->DESTROY();
}
sub fields {
  my $self = shift;
  my $field = shift;

  if ($field) {
    return $self->{$field} if exists $self->{$field};
    return undef;
  }
  return $self->getAllFields();
}

sub getControlfield($self, $code) {
  return $self->getUnrepeatableSubfield($code, '0');
}

sub getAllFields {
  my $self = shift;
  my $as_sorted = shift;

  return $self->{fields} if (! $as_sorted);

  if (@{$self->{fields}} > 1) {
    $self->{fields} = [sort {$a->{fieldNumber} cmp $b->{fieldNumber}} @{$self->{fields}}];
    return $self->{fields};
  }
  return $self->{fields};
}
sub getAllSubfields {
  my $self = shift;
  my $fieldCode = shift;
  my $subfieldCode = shift;

  my $subfields = [];

  if ($fieldCode && $subfieldCode) {
    if (my $fs = $self->fields($fieldCode)) {
      foreach ( @$fs ) {
        next if (! (defined($_->subfields($subfieldCode))) );
        foreach ( @{$_->subfields($subfieldCode)} ) {
          push @$subfields, $_;
        }
      }
    }
  }
  else {
    foreach ( @{$self->{fields}} ) {
      foreach ( $_->getAllSubfields() ) {
        push @$subfields, @$_;
      }
    }
  }

  return $subfields;
}
sub docId {
  my $self = shift;
  my $docId = shift;

  if ($docId) {
    $self->{docId} = $docId;

    #save the docid as the 001-field
    my $target = $self->getControlfield('001');
    if (! (defined $target)) {
      $target = MMT::MARC::Field->new("001");
      $target->addSubfield("0", $docId);
      $self->addField(  $target  );
    }
    ##replace the old one if exists
    else {
      $target->content($docId);
    }
  }
  elsif (not($self->{docId})) {
    my $target = $self->getControlfield('001');
    $self->{docId} = $target->content() if $target;
  }
  return $self->{docId};
}
sub publicationDate {
  my ($self, $publicationDate) = @_;

  if ($publicationDate) {
    my $sf008 = $self->getControlfield('008');
    if ($sf008 && $sf008->content() =~ /^(.{7}).{4}(.+)$/) {
      $sf008->content( $1.$publicationDate.$2 );
    }
    else {
      $self->addUnrepeatableSubfield('008', '0', "       $publicationDate    ");
    }
    $self->{publicationDate} = $publicationDate;
    return $publicationDate;
  }
  unless ($self->{publicationDate}) {
    my $sf008 = $self->getControlfield('008');
    if ($sf008 && $sf008->content() =~ /^.{7}(\d{4}).+$/) {
      $self->{publicationDate} = $1;
    }
  }

  return $self->{publicationDate} || '';
}
sub status {
  my $self = shift;
  my $status = shift;

  $self->{status} = $status if defined $status;
  return $self->{status};
}
sub childId {
  my $self = shift;
  my $childId = shift;

  $self->{childId} = $childId if defined $childId;
  return $self->{childId};
}
sub marcFormat {
  my $self = shift;
  my $marcFormat = shift;

  $self->{marcFormat} = $marcFormat if defined $marcFormat;
  return $self->{marcFormat};
}
sub modTime {
  my $self = shift;
  my $modTime = shift;

  if ($modTime) {
    unless ($modTime =~ /^(\d{4})-(\d{2})-(\d{2})   #YMD
                          (?:
                            [T ]
                            (\d{2}):(\d{2}):(\d{2}) #HMS
                          )?$/x) {
      print "modTime '$modTime' is not ISO8601!\n";
    }
    $self->{modTime} = $1.$2.$3.($4 || '00').($5 || '00').($6 || '00').".0";

    #save the docid as the 001-field
    my $target = $self->getControlfield('005');
    if (! (defined $target)) {
      $target = MMT::MARC::Field->new("005");
      $target->addSubfield("0", $self->{modTime});
      $self->addField(  $target  );
    }
    ##replace the old one if exists
    else {
      $target->content($self->{modTime});
    }
  }
  return $self->{modTime};
}
sub dateReceived {
  my $self = shift;
  my $dateReceived = shift;

  if ($dateReceived) {
    $self->{dateReceived} = $dateReceived;

    #save the docid as the 001-field
    my $target = $self->getUnrepeatableSubfield('942','1');
    if (! (defined $target)) {
      $target = $self->addUnrepeatableSubfield('942','1', $dateReceived);
    }
    ##replace the old one if exists
    else {
      $target->content($dateReceived);
    }
  }
  return $self->{dateReceived};
}
sub rowId {
  my $self = shift;
  my $rowId = shift;

  $self->{rowId} = $rowId if defined $rowId;
  return $self->{rowId};
}
sub pallasLabel {
  my $self = shift;
  my $pallasLabel = shift;

  $self->{pallasLabel} = $pallasLabel if $pallasLabel;
  return $self->{pallasLabel};
}
sub leader {
  my $self = shift;
  my $leader = shift;

  $self->{leader} = $leader if $leader;
  return $self->{leader};
}
sub signum {
  my $self = shift;

  unless ($self->{signum}) {
    #Get the proper SIGNUM (important) Use one of the Main Entries or the Title Statement
    my $leader = $self->leader(); #If this is a video, we calculate the signum differently, 06 = 'g'
    my $signumSource; #One of fields 100, 110, 111, 130, or 245 if 1XX is missing
    my $nonFillingCharacters = 0;

    if (substr($leader,6,1) eq 'g' && ($signumSource = $self->getUnrepeatableSubfield('245', 'a'))) {
      $nonFillingCharacters = $signumSource->parent()->indicator2();
    }
    elsif ($signumSource = $self->getUnrepeatableSubfield('100', 'a')) {

    }
    elsif ($signumSource = $self->getUnrepeatableSubfield('110', 'a')) {

    }
    elsif ($signumSource = $self->getUnrepeatableSubfield('111', 'a')) {

    }
    elsif ($signumSource = $self->getUnrepeatableSubfield('130', 'a')) {
      $nonFillingCharacters = $signumSource->parent()->indicator1();
      $nonFillingCharacters = 0 if (not(defined($nonFillingCharacters)) || $nonFillingCharacters eq ' ');
    }
    elsif ($signumSource = $self->getUnrepeatableSubfield('245', 'a')) {
      $nonFillingCharacters = $signumSource->parent()->indicator2();
    }
    if ($signumSource) {
      $self->{signum} = uc(substr($signumSource->content(), $nonFillingCharacters, 3));
    }
  }
  return $self->{signum};
}
sub countryOfOrigin {
  my $self = shift;
  my $coo = shift;

  $self->{countryOfOrigin} = $coo if $coo;
  return $self->{countryOfOrigin};
}
#These records are finally deleted during Component Part and Multirecord merging in SharedDocidRecordsHandler()
sub markAsDeleted {
  my $self = shift;
  $self->{deleted} = 1;
}
sub isDeleted {
  my $self = shift;

  if (exists $self->{deleted}) {
      return 1;
  }
  return 0;
}
sub isComponentPart {
  my $self = shift;

  return $self->getComponentParentDocid();
}
sub getComponentParentDocid {
  my $self = shift;
  if (my $f773w = $self->getUnrepeatableSubfield('773','w')) {
      return $f773w->content();
  }
  return 0;
}
sub isASerial {
  my $self = shift;
  my $ias = shift;

  if (defined $ias) {
      if ($ias == 1) {
          $self->{isASerial} = 1;
      }
      elsif ($ias == 0) {
          delete $self->{isASerial} if $ias == 0;
      }
  }

  return (exists $self->{isASerial}) ? 1 : 0;
}
sub isASerialMother {
  my $self = shift;
  my $ias = shift;

  if (defined $ias) {
    if ($ias == 1) {
      $self->{isASerialMother} = 1;
    }
    elsif ($ias == 0) {
      delete $self->{isASerialMother} if $ias == 0;
    }
  }

  return (exists $self->{isASerialMother}) ? 1 : 0;
}

sub addUnrepeatableSubfield {
  my $self = shift;
  my $fieldCode = shift;
  my $subfieldCode = shift;
  my $subfieldContent = shift;

  unless ($fieldCode) {
    print "Record '".$self->docId()."'. Trying to add subfield with no field code!\n";
    return undef;
  }
  unless (defined $subfieldCode) {
    print "Record '".$self->docId()."'. Trying to add subfield for field '$fieldCode', but no subfield code!\n";
    return undef;
  }
  unless (defined $subfieldContent) {
    print "Record '".$self->docId()."'. Trying to add subfield for field '$fieldCode', subfield '$subfieldCode', but no subfield content!\n";
    return undef;
  }

  if (my $sf = $self->getUnrepeatableSubfield($fieldCode, $subfieldCode)) {
    $sf->content( $subfieldContent );
    return $sf;
  }
  else {
    my $f = $self->getUnrepeatableField( $fieldCode );
    if (! $f) {
      $f = MMT::MARC::Field->new( $fieldCode ) ;
      $self->addField($f);
    }

    my $sf = MMT::MARC::Subfield->new( $subfieldCode, $subfieldContent );
    $f->addSubfield($sf);
    return $sf;
  }
}

sub getUnrepeatableSubfield {
  my $self = shift;
  my $fieldCode = shift;
  my $subfieldCode = shift;

  return undef if (! (defined $self->fields($fieldCode)) );
  foreach ( @{$self->fields($fieldCode)} ) {

    return undef if (! (defined $_->subfields($subfieldCode)) );
    foreach ( @{$_->subfields($subfieldCode)} ) {
      return $_;
    }
  }
}

sub getUnrepeatableField {
  my $self = shift;
  my $fieldCode = shift;

  my $fields = $self->fields($fieldCode);
  return undef if (! (defined $fields) );
  return $fields->[0];
}

sub getOrAddUnrepeatableField {
  my ($self, $fieldCode, $ind1, $ind2) = @_;
  return $self->{$fieldCode}->[0] if exists $self->{$fieldCode};
  return $self->addField(MMT::MARC::Field->new($fieldCode, $ind1, $ind2));
}

sub language {
  my ($self) = @_;
  my $lang;
  if (my $f008 = $self->getUnrepeatableSubfield('008', '0')) {
    if (length($f008->content) >= 38) {
      if ($lang = substr($f008->content, 35, 3)) {
        return $lang if $lang =~ /^[a-zA-Z]{3}$/;
      }
    }
  }
  return $lang->content if ($lang = $self->getUnrepeatableSubfield('041', 'a'));
  return $lang->content if ($lang = $self->getUnrepeatableSubfield('240', 'l'));
  return undef;
}

#If Field's code changes, we need to move it to another hash bucket.
sub relocateField { #params: ->($oldCode, $MARC::Field)
  my $self = shift;
  my $oldCode = shift;
  my $f = shift;

  my $removeFieldFromArray;
  $removeFieldFromArray = sub {
    for ( my $i=0; $i < @{$self->{$_[0]}} ; $i++ ) {
      if ($f eq $self->{$_[0]}->[$i]) {
        splice @{$self->{$_[0]}},$i,1;

        delete $self->{$_[0]} if (  @{$self->{$_[0]}} == 0  );

        last;
      }
    }
  };

  #find the same object reference inside the codes hash bucket, and delete it
  &$removeFieldFromArray($oldCode);
  #find the same object reference inside the subfields array, and delete it
  &$removeFieldFromArray("fields");

  $self->addField($f);
}

sub relocateSubfield {
  my ($self, $fromFieldCode, $toFieldCode, $fromSubfieldCode, $toSubfieldCode) = @_;

  if (my $fields = $self->fields($fromFieldCode)) {
    for my $field (@$fields) {

      if ($toFieldCode && $fromFieldCode ne $toFieldCode) {
        $field->setCode($toFieldCode);
      }

      if ($fromSubfieldCode && $toSubfieldCode) {
        if (my $subfields = $field->subfields($fromSubfieldCode)) {
          for my $subfield (@$subfields) {
            $subfield->code($toSubfieldCode);
          }
        }
      }
    }
  }
}

sub getCallNumber() {
  my $self = shift;
  my $callNumber; #Try to fetch it from default ISIL, but if it is not available, any library will do.

  my $f852a = $self->fields('852');
  my $defaultIsil = TranslationTables::isil_translation::GetDefaultIsil();
  foreach my $f852 (@$f852a) {
    if (my $sfa = $f852->getUnrepeatableSubfield('a') ) {
      if ($sfa->content() eq $defaultIsil) {
        my $sfh = $f852->getUnrepeatableSubfield('h');
        $callNumber = $sfh->content();
        last();
      }
    }
  }
  if (! $callNumber) {
    if (my $sfh = $self->getUnrepeatableSubfield('852','h') ) {
      $callNumber = $sfh->content();
    }
  }
  return $callNumber;
}
sub getCallNumberClass() {
  my $self = shift;
  my $callNumber = $self->getCallNumber();
  if (defined $callNumber && $callNumber =~ /^(\d+)/) {
    $callNumber = $1;
    return $callNumber;
  }
  else {
    my $breakpoint;
  }
}

#delete everything inside this record. Perl refuses to GC these MARC::Records, because of a circular reference from MARC::Subfield -> MARC::Field -> MARC::Record.
#We need to manually hard destroy these.
sub DESTROY {
  my $self = shift;

  foreach my $k (keys %$self) {

    if (ref $self->{$k} eq "ARRAY") {
      my $array = $self->{$k};
      for(my $i=0 ; $i < @{$array} ; $i++) {
        if (ref $array->[$i] eq "MMT::MARC::Field") {
          $array->[$i]->DESTROY();
        }
        undef $array->[$i];
      }
      undef @{$self->{$k}};
    }

    undef $self->{$k};
  }
  undef %$self; #Snipe myself
}

#Make compiler happy
1;
