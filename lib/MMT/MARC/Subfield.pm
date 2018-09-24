package MMT::MARC::Subfield;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::MARC::Field;
use MMT::MARC::Subfield;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::MARC::Field - MARC Record implementation using the HashList data structure

=head1 COPYRIGHT

Koha-Suomi Oy 2015

=head1 REPOSITORY

https://github.com/KohaSuomi/OrigoMMTPerl

=cut

sub new($class, $code, $content) {
  my $self = bless({}, $class);;

  $self->code($code) if (defined $code);
  $self->content($content) if (defined $content);

  return $self;
}

sub code($self, $code=undef) {
  if (defined $code) {
    $code = lc $code; #Some subfield codes are upper case, which is a bug

    if (! defined $self->{code}) {
      $self->{code} = $code;
    }
    elsif (! ($self->{code} eq $code) ) {
      my $oldCode = $self->{code};
      $self->{code} = $code;
      $self->parent()->relocateSubfield($oldCode, $self);
    }
  }
  return $self->{code};
}

sub content {
  my $self = shift;
  my $content = shift;

  if (defined $content) {
    if ($content =~ /\S{500,}/) { #Zebra indexer dies if single words inside subfields are too long. It is also most certainly an error if such a thing happens.
      if (ref $self ne 'MMT::MARC::Subfield') {
        my $dbg = 1;
      }
      else {
        my $field = $self->parent() if $self;
        my $record = $field->parent() if $field;
        my $docid = $record->docId() if $record;
        print 'MARC::Subfield->content(): Subfield word is too long with over "500" characters. Subfield word is removed.'."\n".
              (($docid) ? 'Record docId: "'.$docid.'",' : '' ).
              (($field) ? 'Field code: "'.$field->code().'",' : '' ).
              (($self && $self->code()) ? 'Subfield code: "'.$self->code().'",' : '' )."  bad content follows:\n".
              $content;
        $content =~ s/\S{500,}//gsm;
      }
    }
    $self->{content} = $content;
  }
  return $self->{content};
}

sub contentXMLEscaped {
  my ($self) = @_;
  my $c = $self->{content};
  $c =~ s/&/&amp;/sg;
  $c =~ s/</&lt;/sg;
  $c =~ s/>/&gt;/sg;
  $c =~ s/"/&quot;/sg;
  return $c;
}

sub parent {
  my $self = shift;
  my $parent = shift;

  if ($parent) {
    $self->{parent} = $parent;
  }
  return $self->{parent}; 
}

sub DESTROY {
  my $self = shift;

  foreach my $k (keys %$self) {
    $self->{$k} = undef;
    delete $self->{$k};
  }
  undef %$self;
  undef $self;
}

#Make compiler happy
1;