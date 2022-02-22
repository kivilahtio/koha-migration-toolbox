package MMT::PrettyLib2Koha::Biblio;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::MARC::Record;
use MMT::MARC::Field;
use MMT::MARC::Subfield;
use MMT::PrettyLib2Koha::Biblio::MaterialTypeRepair;
use MMT::Validator;
use MMT::PrettyLib2Koha::Item;
use MMT::PrettyCirc2Koha::Item;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;
use MMT::Exception::Delete::Silently;

=head1 NAME

MMT::PrettyLib2Koha::Biblio - Transform biblios

=cut

# Deduplicate used Field 001 values. Used to autovifivicate 001 if missing.
my %f001s;

=head2 build

Creates a MARC::Record from a tabular data structure.
FinMARC -> MARC21 conversion is done post-transformation using USERMARCON

 @param1 {HASHRef} PrettyLib csv record row
 @param2 {TBuilder}

=cut

sub build($s, $o, $b) {

  $s->{biblionumber} = $o->{Id};
  unless ($s->{biblionumber}) {
    MMT::Exception::Delete->throw(error => "Missing field 001 with record:\n".Data::Printer::np($o)."\n!!");
  }

  dropPassiveCirc($s, $o, $b) if (ref($s) eq 'MMT::PrettyCirc2Koha::Biblio');

  sanitateInput($o);

  $s->{record} = MMT::MARC::Record->new();
  # Creates FinMARC which is later converted to MARC21
  parseFxxx(@_); # Turn tabular field definitions to MARC::Fields
  linkTitleExtension(@_) unless (ref($s) eq 'MMT::PrettyCirc2Koha::Biblio');

  ## Everything from now-on is MARC21

  # Gather information needed to build the leader
  my %leader;

  $s->{record}->addUnrepeatableSubfield('003', '0', MMT::Config::organizationISILCode()); # Set the cataloguing organization code
  $s->{record}->addUnrepeatableSubfield('040', 'c', MMT::Config::organizationISILCode());

  $s->{record}->modTime($o->{UpdateDate} || $o->{SaveDate}); # Set 005

  _setF001($s, $o->{F001} || $s->id); # Enforce Field 001

  linkToMother(@_, \%leader); # Create 773 to parent record.

  $s->{record}->leader( $s->_buildLeader(\%leader) );

  $s->{record}->addUnrepeatableSubfield('008', '0', $s->_build008($o));
  $s->{record}->publicationDate(getPublicationYear($o));

  $s->mergeLinks($o, $b);

  $s->{record}->addUnrepeatableSubfield('942', 'c', getItemType(@_));

  addCustomRepeatableFields($s);

  MMT::PrettyLib2Koha::Biblio::MaterialTypeRepair::forceControlFields(@_);
}

=head2 sanitateInput

Sanitate some values which can be in inconsistent formats across PrettyLib databases

 @param1 PrettyLirc object

=cut

sub sanitateInput($o) {
  for my $k (qw(UpdateDate SaveDate)) {
    $o->{$k} = MMT::Validator::parseDate($o->{$k}) if ($o->{$k});
  }
}

=head2 mergeLinks

Merges Biblio join tables to the MARC::Record.
The source tables don't have FinMARC information embedded, so we do implicit MARC21-conversion here.

So these subroutines need to generate MARC21-data!

=cut

sub mergeLinks($s, $o, $b) {
  linkAuthors(@_);
  linkBigTexts(@_) if (ref($s) eq 'MMT::PrettyLib2Koha::Biblio');
  linkClasses(@_);
  linkDocuments(@_);
  linkPublishers(@_);
  linkSeries(@_);
  linkSubjects(@_);
  linkSerialHoldings(@_) if     (ref($s) eq 'MMT::PrettyCirc2Koha::Biblio');
}

sub logId($s) {
  return "Biblio '".$s->id()."'";
}

sub id($s) {
  return $s->{biblionumber};
}

sub serialize($s) {
  return $s->{record}->serialize();
}

=head2 parseFxxx

Title.csv has columns named as F001, ..., f440, ... F410xyv

They follow a regular pattern containing indicators and subfields.
Parse this custom pattern to MMT::MARC::Record

=cut

sub parseFxxx($s, $o, $b) {
  while (my ($column, $data) = each(%$o)) {
    next unless $data;
    if ($column =~ /^F(\d\d\d)$/i || $column =~ /^F(410)xyv$/) {
      my $code = $1;
      $log->trace($s->logId." - Found Field '$code', with \$data '$data'") if $log->is_trace();

      if ($code < 10) {
        #Controlfields
        unless ($data) {
          $log->debug($s->logId()." - Skipping field '$code' is missing \$data?") if $log->is_debug();
          next;
        }
        $s->{record}->addUnrepeatableSubfield($code, '0', _ss($data));
      }
      else {
        #Datafields
        _parseDatafield(@_, $code, $data);
      }
    }
  }
}

sub _parseDatafield($s, $o, $b, $code, $data) {
  my ($indicator1, $indicator2, @subfields);

  if (my @elements = split(/\x{1F}/, $data)) {
    ($indicator1, $indicator2) = split(//, $elements[0]);
    for (my $i=1 ; $i<@elements ; $i++) {
      my $sf = MMT::MARC::Subfield->new(_ss(substr($elements[$i],0,1)), _ss(substr($elements[$i],1)));
      unless ($sf->content()) {
        $log->debug($s->logId()." - Skipping subfield '$code\$".$sf->code()."' is missing \$data?") if $log->is_debug();
        next;
      }
      push(@subfields, $sf);
      $log->trace($s->logId." - Found Subfield '".$subfields[-1]->code."' '".$subfields[-1]->content."'") if $log->is_trace();
    }
  }
  elsif ($data) {
    MMT::Exception::Delete->throw(error => "Unable to parse the given MARC Field code '$code' containing data '$data'");
  }

  if (@subfields) {
    my $field = MMT::MARC::Field->new(_ss( $code),
                                          ($indicator1 ? _si($indicator1) : ''),
                                          ($indicator2 ? _si($indicator2) : ''),
                                          \@subfields);
    $s->{record}->addField($field);
    normalizeLanguageCodes($field) if $code eq '041';
    normalizeInternationalStandardNumbers($s, $field, $code) if $code eq '020' or $code eq '021' or $code eq '022' or $code eq '024' or $code eq '025' or $code eq '027';
    return $field;
  }
  else {
    $log->debug($s->logId()." - Skipping field '$code' is missing subfields?");
  }
  return undef;
}

sub addCustomRepeatableFields($s) {
  for my $field (@{MMT::Config::marcAddCustomRepeatableField()}) {
    my $marc_field = MMT::MARC::Field->new($field->{tag}, $field->{indicator1}, $field->{indicator2}, []);
    $s->{record}->addField($marc_field);
    for my $subfield (@{$field->{subfields}}) {
      $marc_field->addSubfield($_, $subfield->{$_}) for keys %$subfield;
    }
  }
}

sub normalizeLanguageCodes($field) {
  my $sfs = $field->getAllSubfields();
  $_->content( lc($_->content()) ) for @$sfs;
}

sub normalizeInternationalStandardNumbers($s, $field, $code) {
  my $isn;
  $isn = 'ISBN' if $code eq '021';
  $isn = 'ISSN' if $code eq '022';
  $isn = 'ISRC' if $code eq '024';
  $isn = 'ISMN' if $code eq '025';
  $isn = 'ISRN' if $code eq '027';

  my $isn_re = MMT::Config::Biblio_ISNFilter($isn);

  return unless $isn_re;

  my $isnsubfields = $field->getAllSubfields();
  for my $isnSubfield (@$isnsubfields) {
    if ($isnSubfield->content() =~ m/($isn_re)/) {
      my $normalized_isn = $1;
      if ($isnSubfield->code() eq 'a') {
        $isnSubfield->content($normalized_isn);
      }
      elsif ($isnSubfield->code() eq 'c') {
        if ($field->getUnrepeatableSubfield('a')) {
          # if subfield a exists, create new field
          my $new_field = MMT::MARC::Field->new(_ss($code));
          $new_field->addSubfield('a', $isnSubfield->content($normalized_isn));
          $s->{record}->addField($new_field);
          $field->deleteSubfield($isnSubfield);
          $log->debug($s->logId()." - Created new field $code and removed subfield c from old field");
        } else {
          # otherwise move subfield c contents to subfield a
          $isnSubfield->code('a');
          $isnSubfield->content($normalized_isn);
          $log->debug($s->logId()." - Relocated $isn field '$code' from subfield c to subfield a");
        }
      }
    }
    else {
      $log->warn($s->logId()." - Unable to normalize $isn field '$code' value '" . $isnSubfield->content() . "'");
    }
  }
}

=head2 linkToMother

PrettyLib.Title.Mother_Id links the current record into some other record.
Create a 773-link to the component mother/parent.

=cut

sub linkToMother($s, $o, $b, $leader) {
  # Set biblio link / Id_mother / 773w
  if ($o->{Id_Mother}) {
    if (my $mother = $b->{Titles}->get($o->{Id_Mother})) {
      unless ($mother->[0]->{F001}) {
        $log->debug($s->logId." - Link to Id_Mother '".$o->{Id_Mother}."' but the mother has no Field 001? Adding biblionumber '".$o->{Id_Mother}."' to 773w.");
      }


      #Create the component parent link field
      my @sfs;
      # First the 'w'
      push(@sfs, MMT::MARC::Subfield->new('w', $mother->[0]->{F001} || $o->{Id_Mother}));
      # Then look for 't' from a long list of candidates
      for my $fieldCandidate (qw(245 240 210 222 247 246 243 242)) {
        if (my $f = _parseDatafield($s, $o, $b, $fieldCandidate, $mother->[0]->{"F$fieldCandidate"})) {
          if ($f->subfields('a') && $f->subfields('a')->[0] && $f->subfields('a')->[0]->content()) {
            push(@sfs, MMT::MARC::Subfield->new('t', $f->subfields('a')->[0]->content()));
            last;
          }
        }
      }

      unless (@sfs == 2) {
        $log->error($s->logId()." - Is missing 773\$t. Cannot find it from 245\$a.");
      }

      my $newField = $s->{record}->addField( MMT::MARC::Field->new('773', '0', '#', \@sfs) );

      $leader->{isComponentPart} = 1;
      $log->debug($s->logId." - Component part link (773w) created to parent '".($mother->[0]->{F001} || $o->{Id_Mother})."', with link text 't'='". (eval { $newField->subfields('t')->[0]->content() } || 'MISSING') ."'") if $log->is_debug();
    }
    else {
      $log->warn($s->logId." - Links to Id_Mother '".$o->{Id_Mother}."' but no matching biblionumber in PrettyLib?");
    }
  }
}

=head2 linkAuthors

PrettyLib.AuthorCross -> Authors -> Field 100

=cut

sub linkAuthors($s, $o, $builder) {
  my (@subfields);
  if (my $authorCrosses = $builder->{AuthorCross}->get($o->{Id})) {
    $log->trace($s->logId." - Found '".scalar(@$authorCrosses)."' authors.") if $log->is_trace();

    @$authorCrosses = sort {$a->{Pos} <=> $b->{Pos}} @$authorCrosses; # PrettyLib.AuthorCross.Pos seems to denote the ordering of these subject-words.
    for my $authorCross (@$authorCrosses) {
      if (my $authors = $builder->{Authors}->get($authorCross->{Id_Author})) {
        for my $author (@$authors) {
          $author->{Author} = _ss($author->{Author});
          unless ($author->{Author}) {
            $log->debug($s->logId." - Found an empty Author with Id '".$author->{Id}."'.") if $log->is_debug();
            next;
          }

          my @subfields;

          my ($fieldCode, $i1, $i2) = ('100', 0, '#');
          if    ($authorCross->{Id_Field} == 23) {
            $fieldCode = '100';
            $i1 = 0;
            $i2 = '#';
          }
          elsif ($authorCross->{Id_Field} == 24) {
            $fieldCode = '700';
            $i1 = 0;
            $i2 = '#';
          }
          elsif ($authorCross->{Id_Field} == 25) {
            $fieldCode = '110';
            $i1 = 2;
            $i2 = '#';
          }
          else {
            $log->fatal($s->logId()." - Unknown AuthorCross.Id_Field '".$authorCross->{Id_Field}."'!");
          }

          my $af = MMT::Config::Biblio_authorFilter();
          if ($af) {
            my %evalRv;
            my $evalOk;
            eval "if (\$author->{Author} =~ $af) { \%evalRv = \%+; \$evalOk = 1 } else { \$evalOk = 0 }"; # $rr is for ex. s/(?<e>\(suom\.\))//
            if ($@) { $log->error($s->logId." - AuthorFilter '$af' error: '$@'"); }
            elsif ($evalOk or exists $author->{FilteredSubfields}) {
              my @capturedSubfields = $evalOk ? keys(%evalRv) : keys(%{$author->{FilteredSubfields}});
              for my $sfCodeOrType (@capturedSubfields) {
                my $sfContent = $evalOk ? $evalRv{$sfCodeOrType} : $author->{FilteredSubfields}->{$sfCodeOrType};
                # translate $sfContent
                my $sfContentTranslateMap = MMT::Config::Biblio_authorFilterMatchTranslationMap();
                $sfContent = $sfContentTranslateMap->{$sfContent} if exists $sfContentTranslateMap->{$sfContent};
                if ($sfCodeOrType eq 'relatorterm') {
                  if ($fieldCode eq '700') {
                    push(@subfields, MMT::MARC::Subfield->new('x', $sfContent));
                  }
                  else {
                    push(@subfields, MMT::MARC::Subfield->new('e', $sfContent));
                  }
                }
                else {
                  push(@subfields, MMT::MARC::Subfield->new($sfCodeOrType, $sfContent));
                }
                $author->{FilteredSubfields}->{$sfCodeOrType} = $sfContent unless exists $author->{FilteredSubfields}->{$sfCodeOrType};
              }
            }
          }

          push(@subfields, MMT::MARC::Subfield->new('a', $author->{Author}));

          if ($fieldCode eq '700') {
            $s->{record}->addField(MMT::MARC::Field->new($fieldCode, $i1, $i2, \@subfields));
          }
          else {
            my $field = $s->{record}->getUnrepeatableField($fieldCode);
            $field = $s->{record}->addField(MMT::MARC::Field->new($fieldCode, $i1, $i2, [])) unless $field;
            $field->addSubfield($_) for @subfields;
            if (my $sfs = $field->subfields('a')) {
              $log->error($s->logId()." - Has '".scalar(@$sfs)."' Author field '$fieldCode'. Only one allowed!")
                  if @$sfs > 1;
            }
          }
        }
      }
    }
  }
}

=head2 linkBigTexts

PrettyLib.BigText -> Summaries -> Field 505

=cut

sub linkBigTexts($s, $o, $builder) {
  if (my $texts = $builder->{BigText}->get($o->{Id})) {
    $log->trace($s->logId." - Found '".scalar(@$texts)."' BigTexts.") if $log->is_trace();

    for my $text (@$texts) {
      my $textFiltered = _ss($text->{TextContent}) if $text->{TextContent};
      next unless($textFiltered);

      $s->{record}->addField(MMT::MARC::Field->new('505', $text->{Id_Type}, '#', [
        MMT::MARC::Subfield->new('a', $textFiltered),
      ]));
    }
  }
}

=head2 linkClasses

PrettyLib.ClassCross -> Class -> Field ??? Trying 084$a for now. This might depend a lot about how the library organized these values.

=cut

sub linkClasses($s, $o, $builder) {
  my (@subfields);
  if (my $crosses = $builder->{ClassCross}->get($o->{Id})) {
    $log->trace($s->logId." - Found '".scalar(@$crosses)."' classes.") if $log->is_trace();

    @$crosses = sort {$a->{Pos} <=> $b->{Pos}} @$crosses; # PrettyLib.ClassCross.Pos seems to denote the ordering of these subject-words.
    for my $cross (@$crosses) {
      if (my $classes = $builder->{Class}->get($cross->{Id_Class})) {
        for my $class (@$classes) {
          $class->{Class} = _ss($class->{Class});
          unless ($class->{Class}) {
            $log->debug($s->logId." - Found an empty Class with Id '".$class->{Id}."'.") if $log->is_debug();
            next;
          }


          #Classify based on the class classifier rules
          my ($classifiedOk, $field);
          for my $classifier (@{MMT::Config::pl_class_classifiers()}) {
            last if $classifiedOk;
            if ($class->{Class} =~ /$classifier->{regexp}/) {
              $classifiedOk = 1;
              $log->trace($s->logId()." - Classifier '".$classifier->{regexp}."' matches '".$class->{Class}."'.") if $log->is_trace();

              $field = $s->{record}->getUnrepeatableField($classifier->{field});
              unless ($field) {
                $field = MMT::MARC::Field->new($classifier->{field}, $classifier->{indicator1}, $classifier->{indicator2});
                $s->{record}->addField($field);
              }

              $field->addSubfield('a', $class->{Class}, {after => 'a'});

              if ($classifier->{subfields}) {
                for my $sfRule (@{$classifier->{subfields}}) {
                  my ($code, $value) = ((keys(%$sfRule))[0], (values(%$sfRule))[0]);

                  my $sf = $field->getUnrepeatableSubfield($code);
                  unless ($sf) {
                    $field->addSubfield(MMT::MARC::Subfield->new($code, $value));
                  }
                  else {
                    $sf->content($value);
                  }
                }
              }

            }
          }
          $log->error($s->logId()." - Classifying Class '".$class->{Class}."' failed. No matching classifier found. Update the configuration parameter 'pl_class_classifiers'") unless ($classifiedOk);
        }
      }
    }
  }
}

=head2 linkDocuments

PrettyLib.Documents contains links to remote resources.

These belong to 856$u

=cut

sub linkDocuments($s, $o, $b) {
  if (my $documents = $b->{Documents}->get($o->{Id})) {
    for my $document (@$documents) {
      $document->{DocName} =~ s/^\s+|\s+$//gsm; #Trim leading/tailing whitespace
      unless ($document->{DocName}) {
        $log->error($s->logId." - Found a Document with Id '".$document->{Id}."' of type '".($document->{DocType} ? $document->{DocType} : 'NULL')."' linking to this Record, but the Document is missing it's URL/URI") if $log->is_error();
        next;
      }
      $s->{record}->addField(
        MMT::MARC::Field->new('856', undef, undef, [
          MMT::MARC::Subfield->new('u', $document->{DocName}),
          MMT::MARC::Subfield->new('z', $document->{DocType} || 'Verkkoaineisto'),
        ])
      );
      $log->debug($s->logId." - Linked in 856\$u Document '".$document->{DocType}."' '".$document->{DocName}."'") if $log->is_debug();
    }
  }
}

=head2 linkPublishers

PrettyLib.PublisherCross -> Publishers -> Field ???

Maybe 260$abc, 028, 044

=cut

sub linkPublishers($s, $o, $builder) {
  my (@subfields);
  if (my $publisherCrosses = $builder->{PublisherCross}->get($o->{Id})) {
    $log->trace($s->logId." - Found '".scalar(@$publisherCrosses)."' publishers.") if $log->is_trace();
    @$publisherCrosses = sort {$a->{Pos} <=> $b->{Pos}} @$publisherCrosses; # PrettyLib.PublisherCross.Pos seems to denote the ordering of these subject-words.
    for my $publisherCross (@$publisherCrosses) {
      if (my $publishers = $builder->{Publishers}->get($publisherCross->{Id_Publisher})) {
        for my $publisher (@$publishers) {
          $publisher->{Name} = _ss($publisher->{Name});
          $publisher->{Place} = _ss($publisher->{Place});
          unless ($publisher->{Name} || $publisher->{Place}) {
            $log->debug($s->logId." - Found an empty Subject with Id '".$publisher->{Id}."'.") if $log->is_debug();
            next;
          }
          push(@subfields, MMT::MARC::Subfield->new('a', $publisher->{Place})) if $publisher->{Place};
          push(@subfields, MMT::MARC::Subfield->new('b', $publisher->{Name}))  if $publisher->{Name};
        }
      }
    }
  }
  return unless @subfields;

  my $field = $s->{record}->getUnrepeatableField('260');
  unless ($field) {
    $field = MMT::MARC::Field->new('260', '#', '#'); # indicator1, names are in format "Surname, Firstnames"
    $s->{record}->addField($field);
  }
  ((not($field->hasSubfield($_->code, $_->content))) ? $field->addSubfield($_) : undef) for @subfields;
}

=head2 linkSeries

PrettyLib.SeriesCross -> Series -> Field 410 && 440 && 490

=cut

sub linkSeries($s, $o, $builder) {
  if (my $seriesCrosses = $builder->{SeriesCross}->get($o->{Id})) {
    $log->trace($s->logId." - Found '".scalar(@$seriesCrosses)."' series.") if $log->is_trace();
    @$seriesCrosses = sort {$a->{Pos} <=> $b->{Pos}} @$seriesCrosses; # PrettyLib.SeriesCross.Pos seems to denote the ordering of these subject-words.

    # For some reason PrettyLib has 410 with only $xyv, and then in addition Series + SeriesCross. Clean up the initial 410$vxy and merge with proper Series.
    my $v;
    my $f410 = $s->{record}->getUnrepeatableField('410');
    if ($f410) {
      $v = $f410->getUnrepeatableSubfield('v');
      $v = $v->content() if $v;
      $s->{record}->deleteField($f410);
    }

    for my $seriesCross (@$seriesCrosses) {
      if (my $seriess = $builder->{Series}->get($seriesCross->{Id_Series})) {
        for my $series (@$seriess) {
          unless ($series->{Title} || $series->{ISSN}) {
            $log->debug($s->logId." - Found an empty Series with Id '".$series->{Id}."'.") if $log->is_debug();
            next;
          }

          $series->{bCompany} = _ss($series->{bCompany});
          $series->{bTitle} = _ss($series->{bTitle});
          $series->{ISSN} = _ss($series->{ISSN});
          $series->{Name1} = _ss($series->{Name1});
          $series->{Name2} = _ss($series->{Name2});
          $series->{SeriesInfo} = _ss($series->{SeriesInfo});
          $series->{SubSeries} = _ss($series->{SubSeries});
          $series->{SubTitle} = _ss($series->{SubTitle});
          $series->{Title} = _ss($series->{Title});
          $series->{URL} = _ss($series->{URL});
          $series->{f440d} = _ss($series->{f440d});
          $series->{f440n} = _ss($series->{f440n});

          # Create the 8xx series added entry Field, since PrettyLib has the extra information for that.
          my $marcField;
          if ($series->{bCompany}) {
            $marcField = 410;
          }
          if ($series->{bTitle}) {
            $log->warn($s->logId." - Found a Series entry with both bTitle and bCompany? '".$series->{SeriesInfo}." : ".$series->{ISSN}."'") if $marcField;
            $marcField = 440;
          }
          unless ($marcField) {
            $log->warn($s->logId." - Found a Series entry with no bTitle and bCompany? '".$series->{SeriesInfo}." : ".$series->{ISSN}."'");
            $marcField = 440;
          }

          if (not(MMT::Config::pl_biblio_seriesMARCCompatibility()) || MMT::Config::pl_biblio_seriesMARCCompatibility() eq '4XX') {
            my $field4xx = $s->{record}->getUnrepeatableField($marcField);
            $field4xx = MMT::MARC::Field->new($marcField, '2', ' ') unless ($field4xx);
            if ($field4xx eq '410') {
              $field4xx->addSubfield('a', $series->{Name1} || $series->{Title}) if ($series->{Name1} || $series->{Title});
              $field4xx->addSubfield('c', $series->{Name2}) if $series->{Name2};
              $field4xx->addSubfield('g', $series->{SubSeries}) if $series->{SubSeries};
              $field4xx->addSubfield('h', $series->{SubTitle}) if $series->{SubTitle};
              $field4xx->addSubfield('w', $series->{ISSN}) if $series->{ISSN};
            } else {
              $field4xx->addSubfield('a', $series->{Title} || $series->{SeriesInfo}) if $series->{Title} || $series->{SeriesInfo};
              $field4xx->addSubfield('b', $series->{Name1} || $series->{Name2}) if ($series->{Name1} || $series->{Name2});
              $field4xx->addSubfield('d', $series->{f440d}) if $series->{f440d};
              $field4xx->addSubfield('n', $series->{f440n}) if $series->{f440n};
              $field4xx->addSubfield('g', $series->{SubSeries}) if $series->{SubSeries};
              $field4xx->addSubfield('h', $series->{SubTitle}) if $series->{SubTitle};
              $field4xx->addSubfield('w', $series->{ISSN}) if $series->{ISSN};
            }
            if ($v) {
              $field4xx->addSubfield('v', $v);
              $v = undef;
            }
            $s->{record}->addField($field4xx) unless ($s->{record}->getUnrepeatableField($marcField));
          }

          if (MMT::Config::pl_biblio_seriesMARCCompatibility() && MMT::Config::pl_biblio_seriesMARCCompatibility() eq '490') {
            my $field490 = $s->{record}->getUnrepeatableField('490');
            $field490 = MMT::MARC::Field->new('490', ' ', ' ') unless ($field490);
            $field490->addSubfield('a', $series->{Title} || $series->{SeriesInfo}) if $series->{Title} || $series->{SeriesInfo};
            $field490->addSubfield('b', $series->{Name1} || $series->{Name2}) if ($series->{Name1} || $series->{Name2});
            $field490->addSubfield('d', $series->{f440d}) if $series->{f440d};
            $field490->addSubfield('n', $series->{f440n}) if $series->{f440n};
            $field490->addSubfield('g', $series->{SubSeries}) if $series->{SubSeries};
            $field490->addSubfield('h', $series->{SubTitle}) if $series->{SubTitle};
            $field490->addSubfield('w', $series->{ISSN}) if $series->{ISSN};
            if ($v) {
              $field490->addSubfield('v', $v);
              $v = undef;
            }
            $s->{record}->addField($field490) unless ($s->{record}->getUnrepeatableField('490'));
          }
        }
      }
    }
  } else {
    my $f410 = $s->{record}->getUnrepeatableField('410');
    if ($f410) {
      $log->warn($s->logId." - Found field 410 with no Series entry?");    
      if (not(MMT::Config::pl_biblio_seriesMARCCompatibility()) || MMT::Config::pl_biblio_seriesMARCCompatibility() eq '4XX') {
        my $f4xx = MMT::MARC::Field->new('440', ' ', ' ') unless ($s->{record}->getUnrepeatableField('440'));
        $f4xx->mergeField($f410);
        $s->{record}->deleteField($f410);
        $s->{record}->addField($f4xx) unless ($s->{record}->getUnrepeatableField('440'));
      }
      elsif (MMT::Config::pl_biblio_seriesMARCCompatibility() && MMT::Config::pl_biblio_seriesMARCCompatibility() eq '490') {
        my $f490 = MMT::MARC::Field->new('490', ' ', ' ') unless ($s->{record}->getUnrepeatableField('490'));
        $f490->mergeField($f410);
        $s->{record}->deleteField($f410);
        $s->{record}->addField($f490) unless ($s->{record}->getUnrepeatableField('490'));
      }
    }
  }
}

=head2 linkSubjects

PrettyLib.SubjectCross -> Subjects -> Field 653$a
Koha wants each Subject to be in a separate Field instance.

# 653 - Index Term-Uncontrolled https://marc21.kansalliskirjasto.fi/bib/6XX.htm#653

=cut

sub linkSubjects($s, $o, $builder) {
  my @subfields;
  if (my $subjectCrosses = $builder->{SubjectCross}->get($o->{Id})) {
    $log->trace($s->logId." - Found '".scalar(@$subjectCrosses)."' subjects.") if $log->is_trace();
    @$subjectCrosses = sort {$a->{Pos} <=> $b->{Pos}} @$subjectCrosses; # PrettyLib.SubjectCross.Pos seems to denote the ordering of these subject-words.
    for my $subjectCross (@$subjectCrosses) {
      if (my $subjects = $builder->{Subjects}->get($subjectCross->{Id_Subject})) {
        for my $subject (@$subjects) {
          $subject->{Subject} = _ss($subject->{Subject});
          unless ($subject->{Subject}) {
            $log->debug($s->logId." - Found an empty Subject with Id '".$subject->{Id}."'.") if $log->is_debug();
            next;
          }
          my @subfields;

          my ($fieldCode, $subfieldA, $subfield2, $indicator1, $indicator2) = ('653', $subject->{Subject}, undef, '#', '#'); #Defaults for unknown and uncontrolled index term
          if    ($subject->{List} == 152) { # YSA
            $fieldCode = '650';
            $subfield2 = 'YSA';
            $indicator1 = '#';
            $indicator2 = '7';
          }
          elsif ($subject->{List} == 192) { # Kirjastokohtaiset (Organization specific)
            $fieldCode = '650';
            $subfield2 = MMT::Config::organizationISILCode();
            $indicator1 = '#';
            $indicator2 = '7';
          }
          elsif ($subject->{List} == 199) { # Avainsanat (Topical keywords) ??? TODO::
            $fieldCode = '650';
            $subfield2 = MMT::Config::organizationISILCode();
            $indicator1 = '#';
            $indicator2 = '7';
          }
          elsif ($subject->{List} == 0) { # MeSH (Medical Subject Headings)
            $fieldCode = '650';
            $indicator1 = '#';
            $indicator2 = '2';
          }
          elsif ($subject->{List} == 50) { # MUSA (Musiikki asiasanasto)
            $fieldCode = '650';
            $subfield2 = 'MUSA';
            $indicator1 = '#';
            $indicator2 = '7';
          }
          else {
            $log->warn($s->logId()." - Subject list '".$subject->{List}."' is unknown. Subject word in unknown list '$subfieldA'");
          }

          push(@subfields, MMT::MARC::Subfield->new('a', $subfieldA)) if $subfieldA;
          push(@subfields, MMT::MARC::Subfield->new('2', $subfield2)) if $subfield2;
          $s->{record}->addField(MMT::MARC::Field->new($fieldCode, $indicator1, $indicator2, \@subfields));
        }
      }
    }
  }
}

=head2 linkTitleExtension

PrettyLib.TitleExtension contains extra MARC fields.

=cut

sub linkTitleExtension($s, $o, $b) {
  if (my $texes = $b->{TitleExtension}->get($o->{Id})) {
    for my $tex (@$texes) {
      $s->{record}->addUnrepeatableSubField(
        $tex->{iMarc},
        $tex->{strSubField},
        $tex->{strValue},
      );
      $log->debug($s->logId." - Linked TitleExtension Field '".$tex->{iMarc}."\$".$tex->{strSubField}."' = '".$tex->{strValue}."'") if $log->is_debug();
    }
  }
}

=head2 linkSerialHoldings

PrettyCirc.CircleStorage contains MARC21 Holdings records for serials storage needs

=cut

sub linkSerialHoldings($s, $o, $b) {
  if (my $holdings = $b->{CircleStorage}->get($o->{Id})) {
    for my $h (@$holdings) {
      # Textual holdings follow the ANSI/NISO Z39.71 or ISO 10324 standard
      my @textualHoldings = ();
      push(@textualHoldings, $h->{PeriodVol}) if $h->{PeriodVol};
      push(@textualHoldings, '('.$h->{PeriodYear}.')') if $h->{PeriodYear};

      my @sfs = (MMT::MARC::Subfield->new('a', join(' ', @textualHoldings)));
      push(@sfs, MMT::MARC::Subfield->new('z', $h->{PeriodNumber})) if $h->{PeriodNumber};
      push(@sfs, MMT::MARC::Subfield->new('x', $h->{Notes})) if $h->{Notes};

      $s->{record}->addField(
        MMT::MARC::Field->new('866', '3', '1', \@sfs)
      );

      $log->debug($s->logId." - Linked Serial holdings '".join(' | ', map {$_->code().':'.$_->content()} @sfs)."'") if $log->is_debug();
    }
  }
}

=head2 getItemType

@STATIC

  Used statically from Item conversion as well.

=cut

sub getItemType($s, $o, $b) {

  my ($titleType, $item, $items);
  if (ref($s) =~ /Item/) {
    unless(defined($o->{Id_Title})) {
      die $s->logId()." - Missing 'biblionumber'?";
    }
    my $titles = $b->{Title}->get( $o->{Id_Title} );
    my $title = $titles->[0] if $titles;
    $titleType = $title->{TitleType} if $title;
    $item = $o;
  }
  else {
    $titleType = $o->{TitleType}; # If we are building Biblios, which have innately the attribute TitleType
    unless(defined($titleType)) {
      $log->warn($s->logId().' - Missing TitleType as bibliounmber="'.($o->{Id_Title} // $s->{biblionumber}).'"!');
    }
    $items = $b->{Items}->get($s->{biblionumber});
    $item = $items->[0] if $items;
    #return undef unless $item;
  }

  if ($items) {
    $item = bless($item, 'MMT::PrettyLib2Koha::Item')  if (ref($s) eq 'MMT::PrettyLib2Koha::Biblio');
    $item = bless($item, 'MMT::PrettyCirc2Koha::Item') if (ref($s) eq 'MMT::PrettyCirc2Koha::Biblio');
    die "Unable to bless \$item as PrettyLib or PrettyCirc Item for Biblio '$s'!" unless blessed($item);
    $item->setPermanent_location($item, $b);
    return $item->{itype} if ($item->{itype});
    return 'EJ' if (ref($s) eq 'MMT::PrettyCirc2Koha::Item' && MMT::PrettyLib2Koha::Item::_circIsElectronic($item));
  }
  return $b->{ItemTypes}->translate($s, $item, $b, $titleType); # Try to get the itemtype from the biblio or the item
}

=head2 getPublicationYear

@STATIC

  Attempts to parse Year1 or 260$c

=cut

sub getPublicationYear($o) {
    if ($o->{Year1} =~ /^\d\d\d\d$/) {
      return $o->{Year1};
    }
    my $f260c = $o->{F260c};
       $f260c =~ s/[^0-9]{4}//;

    if ($f260c =~ /^\d\d\d\d$/) {
      return $f260c;
    }

    return;
}

=head2 dropPassiveCirc

PrettyCirc Biblios that have only passive Items/Subscriptions, are dropped.
Unless they have holdings information.

=cut

sub dropPassiveCirc($s, $o, $b) {
  my $kill = undef;

  my $items = $b->{Items}->get($s->{biblionumber});
  if ($items) {
    my @activeItems = grep {
      not(MMT::PrettyLib2Koha::Item::_circIsPassive($_))
    } @$items;
    $kill = 1 if not(@activeItems);
  }
  else {
    $kill = 1;
  }
  if ($kill) {
    unless (my $holdings = $b->{CircleStorage}->get($o->{Id})) {
      MMT::Exception::Delete->throw(error => "This PrettyCirc Biblio is completely passive, dropping it.")
    }
  }
}

sub getDeleteListId($s) {
  return 'BIBL'.($s->id() || 'UNDEF')
}

=head2 _setF001

Field 001 has duplicate record control numbers?

Deduplicate or not?

Sometimes they are ISBN/ISSN/EAN

In practice the 001 should be unique in a DB, which doesn't differentiate with 003

=cut

sub _setF001($s, $f001Content) {
  if (0) { #deduplicate record control numbers?
    if (exists $f001s{$f001Content}) {
      $log->warn($s->logId." - Field 001 collission! Record '$f001s{$f001Content}' has reserved the Field 001 value '$f001Content'. Trying to use biblionumber '".$s->id."' instead.");

      if (exists $f001s{$s->id}) {
        $log->error($s->logId." - Field 001 collission! Record '$f001s{$f001Content}' has reserved the Field 001 value '$f001Content'. Biblionumber fallback '".$s->id."' is reserved by record '".$f001s{$s->id}."' instead. Using a random number.");

        my $recordControlNumber = 1000000000000000000 + int(rand(999999999999999999));
        $f001s{$recordControlNumber} = $s->id;
        $s->{record}->addUnrepeatableSubfield('001', '0', $recordControlNumber);
      }
      else {
        $f001s{$s->id} = $s->id;
        $s->{record}->addUnrepeatableSubfield('001', '0', $s->id);
      }
    }
    else {
      $f001s{$f001Content} = $s->id;
      $s->{record}->addUnrepeatableSubfield('001', '0', $f001s{$f001Content});
    }
  }
  else { #preserve even duplicate record control numbers.
    $s->{record}->addUnrepeatableSubfield('001', '0', $s->id);
  }
}

sub _buildLeader($s, $flags) {

  return
#Character Positions
#00-04 - Record length
    '00000'.

#05 - Record status
#
#    a - Increase in encoding level
#    c - Corrected or revised
#    d - Deleted
#    n - New
#    p - Increase in encoding level from prepublication
    'n'.

#06 - Type of record
#
#    a - Language material
#    c - Notated music
#    d - Manuscript notated music
#    e - Cartographic material
#    f - Manuscript cartographic material
#    g - Projected medium
#    i - Nonmusical sound recording
#    j - Musical sound recording
#    k - Two-dimensional nonprojectable graphic
#    m - Computer file
#    o - Kit
#    p - Mixed materials
#    r - Three-dimensional artifact or naturally occurring object
#    t - Manuscript language material
    'a'.

#07 - Bibliographic level
#
#    a - Monographic component part
#    b - Serial component part
#    c - Collection
#    d - Subunit
#    i - Integrating resource
#    m - Monograph/Item
#    s - Serial
    ($flags->{isComponentPart} ? 'a' : 'm').

#08 - Type of control
#
#    # - No specified type
#    a - Archival
    '#'.

#09 - Character coding scheme
#
#    # - MARC-8
#    a - UCS/Unicode
    'a'.

#10 - Indicator count
#
#    2 - Number of character positions used for indicators
    '2'.

#11 - Subfield code count
#
#    2 - Number of character positions used for a subfield code
    '2'.

#12-16 - Base address of data
#
#    [number] - Length of Leader and Directory
    '00555'.

#17 - Encoding level
#
#    # - Full level
#    1 - Full level, material not examined
#    2 - Less-than-full level, material not examined
#    3 - Abbreviated level
#    4 - Core level
#    5 - Partial (preliminary) level
#    7 - Minimal level
#    8 - Prepublication level
#    u - Unknown
#    z - Not applicable
    'z'.

#18 - Descriptive cataloging form
#
#    # - Non-ISBD
#    a - AACR 2
#    c - ISBD punctuation omitted
#    i - ISBD punctuation included
#    n - Non-ISBD punctuation omitted
#    u - Unknown
    'u'.

#19 - Multipart resource record level
#
#    # - Not specified or not applicable
#    a - Set
#    b - Part with independent title
#    c - Part with dependent title
    '#'.

#20 - Length of the length-of-field portion
#
#    4 - Number of characters in the length-of-field portion of a Directory entry
    '4'.

#21 - Length of the starting-character-position portion
#
#    5 - Number of characters in the starting-character-position portion of a Directory entry 
    '5'.

#22 - Length of the implementation-defined portion
#
#    0 - Number of characters in the implementation-defined portion of a Directory entry
    '0'.

#23 - Undefined
#
#    0 - Undefined
    '0'.
  '';
}

sub _build008($s, $flags) {
  $flags->{SaveDate} =~ /\d\d(\d\d)-(\d\d)-(\d\d)/;
  $flags->{dateEnteredOnFile} = ($1 ? $1 : 00).($2 ? $2 : 00).($3 ? $3 : 00);
  return
#Character Positions 
#00-05 - Date entered on file
    $flags->{dateEnteredOnFile}.
#06 - Type of date/Publication status

#    b - No dates given; B.C. date involved
#    c - Continuing resource currently published
#    d - Continuing resource ceased publication
#    e - Detailed date
#    i - Inclusive dates of collection
#    k - Range of years of bulk of collection
#    m - Multiple dates
#    n - Dates unknown
#    p - Date of distribution/release/issue and production/recording session when different 
#    q - Questionable date
#    r - Reprint/reissue date and original date
#    s - Single known date/probable date
#    t - Publication date and copyright date
#    u - Continuing resource status unknown
#    | - No attempt to code
    '|'.

#07-10 - Date 1
#
#    1-9 - Date digit
#    # - Date element is not applicable
#    u - Date element is totally or partially unknown
#    |||| - No attempt to code
    '||||'.

#11-14 - Date 2
#
#    1-9 - Date digit
#    # - Date element is not applicable
#    u - Date element is totally or partially unknown
#    |||| - No attempt to code
    '||||'.

#15-17 - Place of publication, production, or execution
#
#    xx# - No place, unknown, or undetermined
#    vp# - Various places
#    [aaa] - Three-character alphabetic code
#    [aa#] - Two-character alphabetic code
    'xx#'.

#18-34 - Material specific coded elements
    '|||||||||||||||||'.

#35-37 - Language
#
#    ### - No information provided
#    zxx - No linguistic content
#    mul - Multiple languages
#    sgn - Sign languages
#    und - Undetermined
#    [aaa] - Three-character alphabetic code
    '###'.

#38 - Modified record
#
#    # - Not modified
#    d - Dashed-on information omitted
#    o - Completely romanized/printed cards romanized
#    r - Completely romanized/printed cards in script
#    s - Shortened
#    x - Missing characters
#    | - No attempt to code
    '|'.

#39 - Cataloging source
#
#    # - National bibliographic agency
#    c - Cooperative cataloging program
#    d - Other
#    u - Unknown
#    | - No attempt to code 
    '|'.
  '';
}

# Trim all UTF-8 control characters except newline
# https://www.compart.com/en/unicode/category/Cc
our $re_sanitator = qr/
\x{0000} | # <Null> (NUL)
\x{0001} | # <Start of Heading> (SOH)
\x{0002} | # <Start of Text> (STX)
\x{0003} | # <End of Text> (ETX)
\x{0004} | # <End of Transmission> (EOT)
\x{0005} | # <Enquiry> (ENQ)
\x{0006} | # <Acknowledge> (ACK)
\x{0007} | # <Alert> (BEL)
\x{0008} | # <Backspace> (BS)
\x{0009} | # <Character Tabulation> (HT, TAB)
#\x{000A} | # <End of Line> (EOL, LF, NL)
\x{000B} | # <Line Tabulation> (VT)
\x{000C} | # <Form Feed> (FF)
\x{000D} | # <Carriage Return> (CR)
\x{000E} | # <Locking-Shift One> (SO)
\x{000F} | # <Locking-Shift Zero> (SI)
\x{0010} | # <Data Link Escape> (DLE)
\x{0011} | # <Device Control One> (DC1)
\x{0012} | # <Device Control Two> (DC2)
\x{0013} | # <Device Control Three> (DC3)
\x{0014} | # <Device Control Four> (DC4)
\x{0015} | # <Negative Acknowledge> (NAK)
\x{0016} | # <Synchronous Idle> (SYN)
\x{0017} | # <End of Transmission Block> (ETB)
\x{0018} | # <Cancel> (CAN)
\x{0019} | # <End of Medium> (EOM)
\x{001A} | # <Substitute> (SUB)
\x{001B} | # <Escape> (ESC)
\x{001C} | # <File Separator> (FS)
\x{001D} | # <Group Separator> (GS)
\x{001E} | # <Information Separator Two> (RS)
\x{001F} | # <Information Separator One> (US)
\x{007F} | # <Delete> (DEL)
\x{0080} | # <Padding Character> (PAD)
\x{0081} | # <High Octet Preset> (HOP)
\x{0082} | # <Break Permitted Here> (BPH)
\x{0083} | # <No Break Here> (NBH)
\x{0084} | # <Index> (IND)
\x{0085} | # <Next Line> (NEL)
\x{0086} | # <Start of Selected Area> (SSA)
\x{0087} | # <End of Selected Area> (ESA)
\x{0088} | # <Character Tabulation Set> (HTS)
\x{0089} | # <Character Tabulation with Justification> (HTJ)
\x{008A} | # <Line Tabulation Set> (VTS)
\x{008B} | # <Partial Line Down> (PLD)
\x{008C} | # <Partial Line Backward> (PLU)
\x{008D} | # <Reverse Index> (RI)
\x{008E} | # <Single Shift Two> (SS2)
\x{008F} | # <Single Shift Three> (SS3)
\x{0090} | # <Device Control String> (DCS)
\x{0091} | # <Private Use One> (PU1)
\x{0092} | # <Private Use Two> (PU2)
\x{0093} | # <Set Transmit State> (STS)
\x{0094} | # <Cancel Character> (CCH)
\x{0095} | # <Message Waiting> (MW)
\x{0096} | # <Start of Guarded Area> (SPA)
\x{0097} | # <End of Guarded Area> (EPA)
\x{0098} | # <Start of String> (SOS)
\x{0099} | # <Single Graphic Character Introducer> (SGC)
\x{009A} | # <Single Character Introducer> (SCI)
\x{009B} | # <Control Sequence Introducer> (CSI)
\x{009C} | # <String Terminator> (ST)
\x{009D} | # <Operating System Command> (OSC)
\x{009E} | # <Privacy Message> (PM)
\x{009F}   # <Application Program Command> (APC)
/x;

=head2 _ss

Sanitate sensibly.
Drop all control characters that are not needed here.

=cut

sub _ss($text) {
  $text =~ s/$re_sanitator//gsm;
  $text =~ s/^\s+|\s+$//gsm; #Trim leading/tailing whitespace
  return $text;
}

=head2 _si

Sanitate an indicator

=cut

sub _si($i) {
  if ($i =~ /^[0-9 |#]$/) {
    return _ss($i);
  }
  else {
    $log->warn("Bad indicator '".sprintf("%X", $i)."'");
  }
}

return 1;
