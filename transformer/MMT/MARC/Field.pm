package MMT::MARC::Field;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::MARC::Subfield;
use MMT::MARC::Record;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::MARC::Field - MARC Record implementation using the HashList data structure

=head1 COPYRIGHT

Koha-Suomi Oy 2015

=head1 REPOSITORY

https://github.com/KohaSuomi/OrigoMMTPerl

=cut

sub new($class, $code, $ind1=undef, $ind2=undef, $subfields=undef) {
  my $self = bless({}, $class);

  setCode($self, $code);

  #initialize the owned subfields reference array
  $self->{subfields} = [];
  if ($subfields) {
    die "Given subfields '$subfields' not an ARRAY, for Field '".$self->{fieldNumber}."' in parent '".$self->parent->docId()."'" if (not(ref($subfields) eq 'ARRAY'));
    $self->addSubfield($_) for @$subfields;
  }

  $self->setIndicator(1, $ind1) if $ind1;
  $self->setIndicator(2, $ind2) if $ind2;

  return $self;
}

sub isControlfield($self) {
  return 1 if $self->code lt '010';
  return 0;
}

sub setCode {
  my $self = $_[0];
  my $code = $_[1];

  if (exists $self->{fieldNumber} && $self->{fieldNumber} ne $code) {
    my $oldCode = $self->{fieldNumber};
    $self->{fieldNumber} = ($code =~ m/^\d\d\d$/) ? $code : die "$!\nERROR: given fieldNumber $code is not 3-digits!\n"; #duplicate code
    $self->parent()->relocateField($oldCode, $self);
  }
  else {
    $self->{fieldNumber} = ($code =~ m/^\d\d\d$/) ? $code : die "$!\nERROR: given fieldNumber $code is not 3-digits!\n"; #duplicate code
  }
}

sub code {
  my $self = shift;
  return $self->{fieldNumber};
}

sub setIndicator($self, $indicator, $value) {
  if ($self->isControlfield) {
    die "controlfield '".$self->code."' shouldn't have indicators? Trying to add indicator '$indicator' with value '$value'";
  }
  $self->{"i$indicator"} = defined($value) ? $value : ' ';
}

sub indicator($self, $indicator) {
  if ($self->isControlfield) {
    return undef;
  }
  return $self->{"i$indicator"} if defined $self->{"i$indicator"};
  return " ";
}

=head2 addSubfield

 @param {Char or MMT::MARC::Subfield} subfield code or the subfield itself to add
 @param {String} Content of the subfield, optional
 @param {HASHRef of operation => target}
          first => 1    # Put the new subfield as the first subfield
          last => 1     # Put the subfield last under this field
          after => 'a'  # Put the subfield after the last instance of subfield 'a'
          before => 'c' # Put the subfield just before the first instance of subfield 'c'

=cut

sub addSubfield($self, $subfield_code, $content=undef, $position={last => 1}) {
  my $sf;

  unless (defined($subfield_code)) {
    print "Record '".$self->parent->docId()."'. Trying to add subfield, but no subfield code!\n";
    return undef;
  }

  if (ref $subfield_code eq 'MMT::MARC::Subfield') {
    $sf = $subfield_code;
  }
  else {
    unless (defined($content)) {
      print "Record '".$self->parent()->docId()."'. Trying to add subfield '$subfield_code' for field '".$self->code()."', but no subfield content!\n";
      return undef;
    }
    $sf = MMT::MARC::Subfield->new($subfield_code, $content);
  }

  if ( exists $self->{$sf->code} && ref $self->{$sf->code} eq 'ARRAY' ) {
    push @{$self->{$sf->code}}, $sf;
  }
  else {
    $self->{$sf->code} = [$sf];
  }

  #Set this MARC::Field as the parent of the newly created MARC::Subfield
  $sf->parent($self);

  #update the owned fields reference list
  if (exists $position->{last}) {
    push @{$self->{subfields}}, $sf;
  }
  elsif (exists $position->{first}) {
    unshift @{$self->{subfields}}, $sf;
  }
  elsif (exists $position->{before}) {
    my $success;
    for (my $i=0 ; $i<@{$self->{subfields}} ; $i++) {
      if ((ref $position->{before} && $self->{subfields}->[$i] == $position->{before}) ||
                                      ($self->{subfields}->[$i]->code eq $position->{before})) {
        splice(@{$self->{subfields}}, $i, 0, $sf);
        $success = 1;
        last;
      }
    }
    unless ($success) {
      push @{$self->{subfields}}, $sf;
    }
  }
  elsif (exists $position->{after}) {
    my $success;
    for (my $i=scalar(@{$self->{subfields}})-1 ; $i>=0 ; $i--) {
      if ((ref $position->{after} && $self->{subfields}->[$i] == $position->{after}) ||
                                    ($self->{subfields}->[$i]->code eq $position->{after})) {
        splice(@{$self->{subfields}}, $i+1, 0, $sf);
        $success = 1;
        last;
      }
    }
    unless ($success) {
      push @{$self->{subfields}}, $sf;
    }
  }

  return $sf;
}

sub subfields {
  my $self = shift;
  my $subfield = shift;

  if (defined $subfield) {
    return $self->{$subfield} if exists $self->{$subfield};
    return undef;
  }
  return undef;
}

sub getAllSubfields {
  my $self = shift;
  my $as_sorted = shift;

  return $self->{subfields} if (! $as_sorted);

  if (@{$self->{subfields}} > 1) {
    $self->{subfields} = [sort {$a->{code} cmp $b->{code}} @{$self->{subfields}}];
    return $self->{subfields};
  }
  return $self->{subfields};
}

sub getUnrepeatableSubfield {
  my $self = shift;
  my $subfieldCode = shift;
  my $sfa = $self->subfields($subfieldCode);

  return undef if (! (defined $sfa) );
  foreach ( @{$sfa} ) { #return the first instance, which should be the last as well
    return $_;
  }
}

sub parent {
  my $self = shift;
  my $parent = shift;

  if ($parent) {
    $self->{parent} = $parent;
  }
  return $self->{parent}; 
}

#If Subfield's code changes, we need to move it to another hash bucket.
sub relocateSubfield { #params: ->($oldCode, $MARC::Subfield)
  my $self = shift;
  my $oldCode = shift;
  my $sf = shift;

  my $removeSubfieldFromArray;
  $removeSubfieldFromArray = sub {
    for ( my $i=0; $i < @{$self->{$_[0]}} ; $i++ ) {
      if ($sf eq $self->{$_[0]}->[$i]) {
        splice @{$self->{$_[0]}},$i,1;

        delete $self->{$_[0]} if (  @{$self->{$_[0]}} == 0  );

        last;
      }
    }
  };

  #find the same object reference inside the codes hash bucket, and delete it
  &$removeSubfieldFromArray($oldCode);
  #find the same object reference inside the subfields array, and delete it
  &$removeSubfieldFromArray("subfields");

  $self->addSubfield($sf);
}

sub toText {
  my $self = shift;
  my $text = '';

  foreach my $sf (@{$self->getAllSubfields()}) {
    $text .= $sf->code()."\t".$sf->content()."\t";
  }
  return $text;
}

sub contentToText {
  my $self = shift;
  my $text = '';

  foreach my $sf (@{$self->getAllSubfields()}) {
    $text .= $sf->content()."\t";
  }
  return $text;
}

#param1 = the Subfield object reference
sub deleteSubfield {
  my $self = shift;
  my $subfield = shift;

  return 0 if (ref $subfield ne 'MMT::MARC::Subfield');

  my $code = $subfield->code();

  #remove the given field from the hash->array data structure
  for ( my $i = @{$self->{$code}}-1; $i >= 0; --$i ) {
    if ( $self->{$code}->[$i] eq $subfield) {
      splice( @{$self->{$code}}, $i, 1 );
      last();
    }
  }
  delete $self->{$code} if scalar @{$self->{$code}} == 0;

  #iterate the owned fields reference list, {fields}, backwards so splicing the array causes no issues during iteration.
  for ( my $index = @{$self->{subfields}}-1; $index >= 0; --$index ) {
    if ($self->{subfields}->[$index] eq $subfield) {
      splice( @{$self->{subfields}}, $index, 1 );
      last();
    }
  }

  $subfield->DESTROY();
  return 1;
}

=head mergeField

    $field->mergeField( $newField );
This method makes this Field copy another MARC::Field's subfields to itself.
When conflicting subfields are found, the new subfield is simply added by the existing
 subfield and a notification is printed.
@RETURNS String, if an error has hapened.

=cut

sub mergeField {
  my $self = shift;
  my $newField = shift;

  unless (ref $newField eq 'MMT::MARC::Field') {
    print "MARC::Field->mergeField($newField): \$newField is not a MARC::Field-object, for Biblio id '".($self->parent() ? $self->parent()->docId() : 'NO_PARENT:(')."' and Field '".$self->code()."'!\n";
    return 'ERROR';
  }

  my $newSfs = $newField->getAllSubfields();
  if ($newSfs) {
    foreach my $sf (@$newSfs) {
      if ($self->subfields( $sf->code() )) { #We already have subfields of this code
        print "MARC::Field->mergeField($newField): Subfield '".$sf->code()."' already exists, for Biblio id '".($self->parent() ? $self->parent()->docId() : 'NO_PARENT:(')."' and Field '".$self->code()."'. Adding it normally.\n";
      }

      my $sfCopy = MMT::MARC::Subfield->new($sf->code(), $sf->content());
      $self->addSubfield($sfCopy);
    }
  }
}

=head mergeAllSubfields

    $field->mergeAllSubfields($targetSubfield, $subfieldSeparator);
    $field->mergeAllSubfields($targetSubfieldCode, $subfieldSeparator);
Merges all subfields inside this field under the given subfield.
Contents are separated by the given separator.
@PARAM1,  MARC::Subfield or subfield code.
@PARAM2,  String
@RETURNS, "NOSUBFIELD", if no subfield is found.
          "OK", reference to the merged target subfield if merging happened.
          undef, if nothing to merge.

=cut

sub mergeAllSubfields {
  my ($self, $targetSubfield, $separator) = @_;
  $separator = ' - ' unless $separator;

  unless (ref $targetSubfield eq 'MMT::MARC::Subfield') {
    $targetSubfield = $self->getUnrepeatableSubfield( $targetSubfield );
  }
  unless ($targetSubfield) {
    return "NOSUBFIELD";
  }

  my $sfs = $self->getAllSubfields();
  my @mergeableContent;
  if ($sfs) {
    #Collect content and destroy the sibling subfields
    foreach my $sf (@$sfs) {
      if ($sf eq $targetSubfield) { #Don't merge target to itself!
        next();
      }

      my $content = $sf->content();
      push @mergeableContent, $content if $content && length $content > 0;
      $self->deleteSubfield($sf);
    }
    #Append the content to $targetSubfield
    if (scalar(@mergeableContent)) {
      $targetSubfield->content( $targetSubfield->content().$separator.join($separator, @mergeableContent) );
      return 'OK';
    }
  }
  return undef;
}

=head2 hasSubfield

 @param1 MMT::MARC::Subfield, if given, looks if this specific Object instance is present
 or
 @param1 String (subfield code), if given, looks if a subfield with this given subfield code has the exact same content
 @param2 String (subfield content), looks for exact match against this subfield content

 @returns MMT::Marc::Subfield or undef

=cut

sub hasSubfield {
  my ($self, $sf, $sfContent) = @_;
  if (ref($sf)) {
    if (my $sfs = $self->subfields($sf->code)) {
      return grep {$_ == $sf} @$sfs;
    }
    else {
      return undef;
    }
  }
  else {
    if (my $sfs = $self->subfields($sf)) {
      return grep {$_->content eq $sfContent} @$sfs;
    }
    else {
      return undef;
    }
  }
}

sub DESTROY {
  my $self = shift;

  foreach my $k (keys %$self) {

    if (ref $self->{$k} eq "ARRAY") {
      my $array = $self->{$k};
      for(my $i=0 ; $i < @{$array} ; $i++) {
        if (ref $array->[$i] eq "MMT::MARC::Subfield") {
          weaken $array->[$i];
        }
        undef $array->[$i];
      }
      undef @{$self->{$k}};
    }

    undef $self->{$k};
  }
  undef %$self;
}

#Make compiler happy
1;