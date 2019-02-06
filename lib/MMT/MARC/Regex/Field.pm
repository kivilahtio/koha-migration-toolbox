package MMT::MARC::Regex::Field;

use Modern::Perl;
use utf8;
use English;

use feature 'refaliasing';
no warnings 'experimental::refaliasing';

use Data::Printer;
use Scalar::Util qw(reftype);

=head1 NAME

MMT::MARC::Regex::Field - Transform MARCXML Fields using plain regular expressions

=head1 DESCRIPTION

This module does simple MARCXML record mutations with pure regexps.

=cut

=head2 overload

Stringification is overloaded to return the mutated version of the Field.
The original version is kept in the background.

=cut

use overload '""' => sub {
  return $_[0]->lazyLoaded ? ${$_[0]->[1]} : ${$_[0]->[0]};
};

sub new {
  my ($class, $xmlPtr) = @_;
  return bless([$xmlPtr], $class);
}

sub lazyLoaded {
  return $_[0]->[1];
}

=head2 refs

Lazy-load the MARCXML-fragment into something which can be replaced to the existing MARCXML

 @returns References to the original and mutatable Field MARCXML fragments

=cut

sub refs {
  unless ($_[0]->lazyLoaded) {
    my $clone = ${$_[0]->[0]};
    $_[0]->[1] = \$clone;
  }
  return ($_[0]->[0], $_[0]->[1]);
}

sub original {
  return $_[0]->[0];
}
sub mutated {
  return $_[0]->lazyLoaded ? $_[0]->[1] : $_[0]->[0];
}

my $_p; #The padding used in the incoming records.

# We could directly refer the parent class' variable, but that would make brutally ugly regexps.
sub _getPadding {
  $_p = $MMT::MARC::Regex::_p;
  die __PACKAGE__."_getPadding() :> Parent class doesn't know the MARCXML padding?" unless $_p;
  return $_p;
}

=head2 subfield

Get or replace the given Subfield's contents.

If nothing to replace, creates a new subfield to the defined position with a given subfield or contents.

 @param {Char} The MARC Subfield code to select. Picks the first repetition if multiple fields available.
 @param {String} OPTIONAL. The content to put/substitute, otherwise gets the value
 @param {HASH reference} Position where to put the new Field:
                         after => 'c'   # Places the subfield after the first instance of subfield 'c'
                         first => 1     # Places the new subfield first
                         last => 1      # Default bahviour, appends the new subfield to the end of the datafield
 @returns {String} The operation that happened:
                   One of: ['replace', 'after', 'last', 'first']
                   OR
                   If no content was given, the subfield contents of the given subfield or undef

=cut

sub subfield {
  my ($self, $sfCode, $content, $position) = @_;
  die "parameter \$sfCode is undefined" unless defined($sfCode);

  unless (defined($content)) {
    unless ($self =~ m!
      <subfield\s+code="$sfCode">                     #Correct subfield found
        (.*?)                                         #Target acquired
      </subfield>                                     #Subfield closes
    !smx) {
      return undef;
    }
    return $1;
  }

  my ($orig, $muta) = $self->refs;

  # Replace an existing field
  if ($$muta =~ s!
    (                                                     #Lookbehind for the subfield start tag (nooo... Variable length lookbehind not implemented in regex)
      <subfield\s+code="$sfCode"\s*>                      #Correct subfield found
    )                                                     #Lookbehind closes
      .*?                                                 #Target acquired
    (?=                                                   #Lookahead to substitute only the subfield contents
      </subfield>                                         #Subfield closes
    )                                                     #Terminate lookahead
  !$1$content!smx) {
    return 'replace';
  }

  _getPadding() unless defined($_p); #Padding is needed only now, so avoid calculating it until necessary

  #Prepend a subfield
  if ($position->{first}) {
    if ($$muta =~ s!
      (                                                   #
        <datafield\s+tag=".+?".+?>                        #Capture the leading datafield-element
      )                                                   #
      (?=                                                 #Lookahead to substitute only the leading datafield-element
          .*?                                             #Rewind until the end of this datafield
        </datafield>                                      #
      )                                                   #Terminate lookahead
      !$1\n$_p$_p<subfield code="$sfCode">$content</subfield>!smx) {
      return 'first';
    }
  }

  #Append a subfield after some other
  if ($position->{after}) {
    if ($$muta =~ s!
      (                                                   #Lookbehind, find a reliably uniquely identifiable position to alter with precision (nooo... Variable length lookbehind not implemented in regex)
          .*?                                             #Rewind until the desired subfield is found
          <subfield\s+code="$position->{after}"\s*>       #Correct subfield found
            .*?
          </subfield>                                     #And closed
      )                                                   #Terminate lookbehind
                                                          #Substitution target acquired
    !$1\n$_p$_p<subfield code="$sfCode">$content</subfield>!smx) {
      return 'after';
    }
  }

  #Append a subfield by default
  if ($$muta =~ s!
    (                                                   #Lookbehind, find a reliably uniquely identifiable position to alter with precision (nooo... Variable length lookbehind not implemented in regex)
      <datafield\s+tag=".+?".+?>                        #Find the correct datafield, capture the indentation depth
        .*?                                             #Rewind until the end of this datafield
    )                                                   #Terminate lookbehind
                                                        #Substitution target acquired
    (?=                                                 #Lookahead to substitute only the subfield contents
      </datafield>                                      #
    )                                                   #Terminate lookahead
    !$1$_p<subfield code="$sfCode">$content</subfield>\n$_p!smx) {
    return 'last';
  }

  die "Unable to set the subfield '$sfCode' with content '$content' for field:\n$$orig\n!!";
}

=head2 subfields

 @returns {ARRAYRef of Strings} The complete subfields

=cut

sub subfields {
  my ($self) = @_;

  if (my @subfields = $self =~ m!
    (                                               #Capture a subfield instance
    <subfield\s+code=".">                           #Correct subfield found
      .*?                                           #Target acquired
    </subfield>                                     #Subfield closes
    )                                               #Close capture
  !smxg) {
    return \@subfields;
  }
  return [];
}

return 1;
