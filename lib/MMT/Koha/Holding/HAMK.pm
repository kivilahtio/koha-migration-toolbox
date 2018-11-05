package MMT::Koha::Holding::HAMK;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::MARC::Regex;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::Koha::Holding::HAMK - Transform holdings the HAMK-way

=head1 HISTORY

This has been implemented using the MMT::Marc::Record -implementation sometime before 2018-11-05.
If there is a need to revert back there.

=cut

=head2 transform

Transforms the given MARC Holdings Record to Koha.
Sets the id-attribute of the MMT::Koha::Holdings-record ASAP, so it can be accurately logged.

 @param {MMT::Koha::Holding}
 @param {Reference to a String} MARCXML
 @param {MMT::TBuilder} Builder-object containing all the translation- and lookup-tables
 @returns {undef} The given Record reference is mutated in-place

=cut

sub transform($s, $xmlPtr, $b) {
  my $holding_id = MMT::MARC::Regex->controlfield($xmlPtr, '001');
  unless ($holding_id) {
    MMT::Exception::Delete->throw(error => "Missing field 001 with record:\n$$xmlPtr\n!!");
  }
  $s->{id} = $holding_id; #Make sure the id is set, so further logging can be done.

  my $bib_id = MMT::MARC::Regex->controlfield($xmlPtr, '004');
  unless ($bib_id) {
    MMT::Exception::Delete->throw(error => "Missing field 004 with record:\n$$xmlPtr\n!!");
  }

  MMT::MARC::Regex->controlfield($xmlPtr, '003', 'FI-Hamk', {after => '001'});

  transform852($s, $xmlPtr, $b);

  isSuppressInOPAC($s, $xmlPtr, $b, $holding_id);

  return $holding_id;
}

=head2 Transforms the given MARC Holdings Record to Koha

 @param {MMT::Koha::Holding}
 @param {Reference to a String} MARCXML
 @param {MMT::TBuilder}
 @returns {undef} The given Field reference is mutated in-place

=cut

sub transform852($s, $xmlPtr, $b) {
  # Force ISIL-code 'FI-Hamk' to 852$a
  MMT::MARC::Regex->subfield($xmlPtr, '852', 'a', 'FI-Hamk', {first => 1}) or MMT::Exception::Delete->throw(error => "Unable to set the 852\$a for record:\n$$xmlPtr");

  # Transform 852$b using the location transformation table, set relevant subfields
  my $sfb = MMT::MARC::Regex->subfield($xmlPtr, '852', 'b');
  unless ($sfb) {
    $log->warn($s->logId().' - Missing 852$b. Cannot translate locations.');
  }
  else {
    my $blcsin = $b->{LocationId}->translate($s, undef, $b, $sfb);
    # Put branch to the first instance of $b
    MMT::MARC::Regex->subfield($xmlPtr, '852', 'b', $blcsin->{branch}, {after => 'a'});
    # Put permanent_location to the first instance of $c
    MMT::MARC::Regex->subfield($xmlPtr, '852', 'c', $blcsin->{location}, {after => 'b'});
    # Put ccode to $g
    MMT::MARC::Regex->subfield($xmlPtr, '852', 'g', $blcsin->{collectionCode}, {after => 'c'});
  }

  # Don't touch the call number portions

  # Set the country code, just to be a completionist
  MMT::MARC::Regex->subfield($xmlPtr, '852', 'n', 'fi', {last => 1});
}

=head2 isSuppressInOPAC

Sets the 942$n if the holding record is suppressed in OPAC

=cut

sub isSuppressInOPAC($s, $xmlPtr, $b, $holding_id) {
                                       #Key for the info is built with bib_id.mfhd_id.location_id
  my $suppressInOpac = $b->{SuppressInOpacMap}->get('NULL'.$holding_id.'NULL');
  $suppressInOpac = $suppressInOpac->[0]->{suppress_in_opac} if $suppressInOpac;
  if ($suppressInOpac) {
    $log->debug($s->logId()." - Suppress in opac '$suppressInOpac'") if $log->is_debug();

    MMT::MARC::Regex->subfield($xmlPtr, '942', 'n', $suppressInOpac, {last => 1});
  }
}

return 1;
