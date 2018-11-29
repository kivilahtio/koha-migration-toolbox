package MMT::MARC::Regex;

use Modern::Perl;
use utf8;
use English;

use Data::Printer;

=head1 NAME

MMT::MARC::Regex - Transform biblios using plain regular expressions

=head1 DESCRIPTION

This module does simple MARCXML record mutations with pure regexps.
This is significantly faster,
if only a small amount of modifications is needed to be done,
compared to MARC::Record or MMT::Marc::Record implementations,
due to the slowness of needing to parse records into complex data structures.

=cut

my $_p; #The padding used in the incoming records.

sub _getPadding {
  my ($xmlPtr) = @_;

  my $recordPadding;
  if ($$xmlPtr =~ m!^(\s*?)<record!sm) {
    $recordPadding = $1;
  }
  else {
    die "Unable to get the indentation of <record> for record:\n$$xmlPtr\n!!";
  }

  if ($$xmlPtr =~ m!^(\s*?)<subfield!sm) {
    $_p = substr(  $1, 0, int((length($1) - length($recordPadding)) / 2)  );
  }
  elsif ($$xmlPtr =~ m!^(\s*?)<(?:data|control)field!sm) {
    $_p = substr(  $1, 0, int((length($1) - length($recordPadding)) / 1)  );
  }
  else {
    die "Unable to get the indentation for record:\n$$xmlPtr\n!!";
  }

  return $_p;
}

=head2 controlfield

Get or replace the given Controlfield's contents.

If nothing to replace, creates a new controlfield to the defined position.

 @param {String reference} The MARC XML String to mutate
 @param {String} The MARC Controlfield code/tag to select
 @param {String} The content to put/substitute
 @param {HASH reference} Position where to put the new Field:
                         after => '003' # Places the new field after the first instance of field 003
                         first => 1     # Places the new field after the first controlfield
                         last => 1      # Default bahviour, appends the new field to the end of the record
 @returns {String} The operation that happened:
                   One of: ['replace', 'after', 'last']
                   OR
                   If no content was given, the value of the given controlfield or undef

=cut

sub controlfield {
  my ($self, $xmlPtr, $code, $content, $position) = @_;

  unless (defined($content)) {
    unless ($$xmlPtr =~ m!<controlfield tag="$code">(.+?)</controlfield>!sm) {
      return undef;
    }
    return $1;
  }

  #Replace an existing field
  if ($$xmlPtr =~ s!
               <controlfield\s+tag="$code">(.+?)</controlfield>
              !<controlfield tag="$code">$content</controlfield>!smx) {
    return 'replace';
  }

  _getPadding($xmlPtr) unless defined($_p); #Padding is needed only now, so avoid calculating it until necessary

  #Add a new field after some other field
  if ($position->{after}) {
    if ($$xmlPtr =~ s!
                  (<controlfield\s+tag="$position->{after}">.+?</controlfield>)
                !$1\n$_p<controlfield tag="$code">$content</controlfield>!smx) {
      return 'after';
    }
  }
  if ($position->{first}) {
    if ($$xmlPtr =~ s!
                    </leader>            #Add a new field to the beginning
                  !</leader>\n$_p<controlfield tag="$code">$content</controlfield>!smx) {
      return 'first';
    }
  }
  #Default to just appending the controlfield after all the other controlfields
  if ($$xmlPtr =~ s!
                  (?=<datafield)            #Add a new field to the beginning
                !<controlfield tag="$code">$content</controlfield>\n$_p!smx) {
    return 'last';
  }
  die "Unable to set the field '$code' with content '$content' for record:\n$$xmlPtr\n!!";
}

=head2 datafield

Get or replace the given Field's contents.

If nothing to replace, creates a new field to the defined position with a given subfield or contents.

 @param {String reference} The MARC XML String to mutate
 @param {String} The MARC Field code/tag to select
 @param {Char} The MARC Subfield code to select
 @param {String} The content to put/substitute
                 If no MARC Subfield code is given, this is presumed to be the content to put inside a field, eg.
                   <subfield code="a">APUA</subfield>
                   <subfield code="h">HUIPPUA</subfield>

                 If a MARC subfield code is given, this is expected to be the contents of the new subfield inside the new field.
                 If you want to put subfields under an existing field, use C<subfield()>
 @param {HASH reference} Position where to put the new Field:
                         after => '852' # Places the new field after the first instance of field 852
                         first => 1     # Places the new field after the first controlfield
                         last => 1      # Default bahviour, appends the new field to the end of the record
 @returns {String} The operation that happened:
                   One of: ['replace', 'after', 'last']
                   OR
                   If no content was given, the subfield contents of the given datafield or undef

=cut

sub datafield {
  my ($self, $xmlPtr, $fCode, $sfCode, $content, $position) = @_;
  die "parameter \$fCode is undefined" unless defined($fCode);

  unless (defined($content)) {
    unless ($$xmlPtr =~ m!<datafield tag="$fCode".*?>\s*?\n?(.*?)\s*</datafield>!sm) {
      return undef;
    }
    return $1;
  }

  $content = "<subfield code=\"$sfCode\">$content</subfield>" if $sfCode;

  #Replace an existing field
  if ($$xmlPtr =~ s!
              (<datafield\s+tag="$fCode".*?>).+?</datafield>
              !$content</datafield>!smx) {
    return 'replace';
  }

  _getPadding($xmlPtr) unless defined($_p); #Padding is needed only now, so avoid calculating it until necessary

  #Add a new field after some other field
  if ($position->{after}) {
    if ($$xmlPtr =~ s!
                  (<datafield\s+tag="$position->{after}".*?>.+?</datafield>)
                !$1\n$_p<datafield tag="$fCode" ind1=" " ind2=" ">\n$_p$_p$content\n$_p</datafield>!smx) {
      return 'after';
    }
  }
  if ($position->{first}) {
    if ($$xmlPtr =~ s!
                    (?=<datafield)            #Add a new field to the beginning
                  !<datafield tag="$fCode" ind1=" " ind2=" ">\n$_p$_p$content\n$_p</datafield>\n$_p!smx) {
      return 'first';
    }
  }
  #Default to just appending the datafield after all the other datafields
  if ($$xmlPtr =~ s!
                (?=</record)            #Add a new field to the end
                !$_p<datafield tag="$fCode" ind1=" " ind2=" ">\n$_p$_p$content\n$_p</datafield>\n!smx) {
    return 'last';
  }
  die "Unable to set the field '$fCode' with content '$content' for record:\n$$xmlPtr\n!!";
}

=head2 subfield

Get or replace the given Subfield's contents.

If nothing to replace, creates a new subfield to the defined position with a given subfield or contents.

 @param {String reference} The MARC XML String to mutate
 @param {String} The MARC Field code/tag to select. Picks the first repetition if multiple fields available.
 @param {Char} The MARC Subfield code to select. Picks the first repetition if multiple fields available.
 @param {String} The content to put/substitute
 @param {HASH reference} Position where to put the new Field:
                         after => 'c'   # Places the subfield after the first instance of subfield 'c'
                         first => 1     # Places the new subfield first
                         last => 1      # Default bahviour, appends the new subfield to the end of the datafield
 @returns {String} The operation that happened:
                   One of: ['replace', 'after', 'last']
                   OR
                   If no content was given, the subfield contents of the given subfield or undef

=cut

sub subfield {
  my ($self, $xmlPtr, $fCode, $sfCode, $content, $position) = @_;
  die "parameter \$fCode is undefined" unless defined($fCode);
  die "parameter \$sfCode is undefined" unless defined($sfCode);

  $$xmlPtr =~ m!
    <datafield\s+tag="$fCode".+?>
      (.+?)
    </datafield>
  !smx;
  my $field = $1;
  my $oldField = $1;

  return undef if (not($field) && not($content)); #If we are looking for the subfield value, return nothing because there is no field

  unless (defined($content)) {
    unless ($field =~ m!
      <subfield\s+code="$sfCode">                     #Correct subfield found
        (.*?)                                         #Target acquired
      </subfield>                                     #Subfield closes
    !smx) {
      return undef;
    }
    return $1;
  }

  if ($field) {
    # Replace an existing field
    if ($field =~ s!
      (                                                     #Lookbehind for the subfield start tag (nooo... Variable length lookbehind not implemented in regex)
        <subfield\s+code="$sfCode"\s*>                      #Correct subfield found
      )                                                     #Lookbehind closes
        .*?                                                 #Target acquired
      (?=                                                   #Lookahead to substitute only the subfield contents
        </subfield>                                         #Subfield closes
      )                                                     #Terminate lookahead
    !$1$content!smx) {
      $$xmlPtr =~ s!\Q$oldField\E!$field!sm;
      return 'replace';
    }

    _getPadding($xmlPtr) unless defined($_p); #Padding is needed only now, so avoid calculating it until necessary

    #Prepend a subfield
    if ($position->{first}) {
      $field = "\n$_p$_p<subfield code=\"$sfCode\">$content</subfield>" . $field;
      $$xmlPtr =~ s!\Q$oldField\E!$field!sm;
      return 'first';
    }

    #Append a subfield after some other
    if ($position->{after}) {
      if ($field =~ s!
        (                                                   #Lookbehind, find a reliably uniquely identifiable position to alter with precision (nooo... Variable length lookbehind not implemented in regex)
            .*?                                             #Rewind until the desired subfield is found
            <subfield\s+code="$position->{after}"\s*>       #Correct subfield found
              .*?
            </subfield>                                     #And closed
        )                                                   #Terminate lookbehind
                                                            #Substitution target acquired
      !$1\n$_p$_p<subfield code="$sfCode">$content</subfield>!smx) {
        $$xmlPtr =~ s!\Q$oldField\E!$field!sm;
        return 'after';
      }
    }

    #Append a subfield by default
    if ($$xmlPtr =~ s!
      (                                                   #Lookbehind, find a reliably uniquely identifiable position to alter with precision (nooo... Variable length lookbehind not implemented in regex)
        <datafield\s+tag="$fCode".+?>                     #Find the correct datafield, capture the indentation depth
          .*?                                             #Rewind until the end of this datafield
      )                                                   #Terminate lookbehind
                                                          #Substitution target acquired
      (?=                                                 #Lookahead to substitute only the subfield contents
        </datafield>                                      #
      )                                                   #Terminate lookahead
      !$1$_p<subfield code="$sfCode">$content</subfield>\n$_p!smx) {
      return 'last';
    }
  }
  else { #There is no field
    return $self->datafield($xmlPtr, $fCode, $sfCode, $content, $position);
  }

  die "Unable to set the subfield '$fCode\$$sfCode' with content '$content' for record:\n$$xmlPtr\n!!";
}

return 1;
