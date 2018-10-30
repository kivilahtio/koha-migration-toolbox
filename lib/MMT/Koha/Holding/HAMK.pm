package MMT::Koha::Holding::HAMK;

use MMT::Pragmas;

#External modules

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::Koha::Holding::HAMK - Transform holdings the HAMK-way

=cut

=head2 transform

Transforms the given MARC Holdings Record to Koha

 @param {MMT::Koha::Holding}
 @param {MMT::MARC::Record}
 @param {MMT::TBuilder} Builder-object containing all the translation- and lookup-tables
 @returns {undef} The given Record reference is mutated in-place

=cut

sub transform($s, $r, $b) {
  my $f852s = $r->fields('852');
  transform852($s, $r, $b, $_) for (@$f852s);

  isSuppressInOPAC($s, $r, $b);
}

=head2 Transforms the given MARC Holdings Record to Koha

 @param {MMT::Koha::Holding}
 @param {MMT::MARC::Record}
 @param {MMT::TBuilder}
 @param {MMT::MARC::Field} The Field 852 instance to mutate
 @returns {undef} The given Field reference is mutated in-place

=cut

sub transform852($s, $r, $b, $f) {

  # Force ISIL-code 'FI-Hamk' to 852$a
  my $sfa = $f->subfields('a');
  _deleteExcessSubfields($s, $r, $b, $sfa) if $sfa;
  $sfa ? $sfa->[0]->content('FI-Hamk') : $f->addSubfield('a', 'FI-Hamk', {first => 1});

  # Transform 852$b using the location transformation table, set relevant subfields
  my $sfb = $f->subfields('b');
  unless ($sfb) {
    $log->warn($s->logId().' - Missing 852$b. Cannot translate locations.');
  }
  else {
    _deleteExcessSubfields($s, $r, $b, $sfb) if $sfb; # It is ok to have multiple instances, but don't know what to do with those, since Voyager doesn't have so many location classifiers anyway.
    my $blcsin = $b->{LocationId}->translate($s, $r, $b, $sfb->[0]->content);
    # Put branch to the first instance of $b
    $sfb->[0]->content($blcsin->{branch});
    # Put permanent_location to the first instance of $c
    my $sfc = $f->subfields('c');
    _deleteExcessSubfields($s, $r, $b, $sfc) if $sfc; #It is ok to have multiple instances, but don't know what to do with those.
    $sfc ? $sfc->[0]->content($blcsin->{location}) : $f->addSubfield('c', $blcsin->{location}, {after => 'b'}) if $blcsin->{location};
    # Put sub_location to the second instance of $c
    $f->addSubfield('c', $blcsin->{sub_location}, {after => 'c'}) if $blcsin->{sub_location};
    # Put ccode to $g
    $f->addSubfield('g', $blcsin->{collectionCode}, {after => 'c'}) if $blcsin->{collectionCode};
  }

  # Don't touch the call number portions

  # Set the country code, just to be a completionist
  my $sfn = $f->subfields('n');
  _deleteExcessSubfields($s, $r, $b, $sfn) if $sfn;
  $sfn ? $sfn->[0]->content('fi') : $f->addSubfield('n', 'fi', {last => 1});
}

=head2 isSuppressInOPAC

Sets the 942$n if the holding record is suppressed in OPAC

=cut

sub isSuppressInOPAC($s, $r, $b) {
                                       #Key for the info is built with bib_id.mfhd_id.location_id
  my $suppressInOpac = $b->{SuppressInOpacMap}->get('NULL'.$r->docId().'NULL');
  if ($suppressInOpac) {
    $suppressInOpac = $suppressInOpac->[0]->{suppress_in_opac};
    $log->debug($s->logId()." - Suppress in opac '$suppressInOpac'") if $log->is_debug();

    my $f942s = $r->fields('942');
    my $f942 = $f942s ? $f942s->[0] : $r->addField('942');

    my $sfns = $f942->subfields('n');
    _deleteExcessSubfields($s, $r, $b, $sfns) if $sfns; #It is not ok to have multiple instances
    if ($sfns) {
      $sfns->[0]->content($suppressInOpac);
    }
    else {
      $f942->addSubfield('n', $suppressInOpac);
    }
  }
}

sub _deleteExcessSubfields($s, $r, $b, $sfs) {
  if (@$sfs > 1) {
    my $fieldCode = $sfs->[0]->parent->code;
    my $subfieldCode = $sfs->[0]->code;
    $log->warn($s->logId()." - Deleting excess $fieldCode\$$subfieldCode");
    $sfs->[$_]->parent->deleteSubfield($sfs->[$_]) for (1..((@$sfs-1)));
  }
}

return 1;
