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
  $s->{holding_id} = $holding_id; #Make sure the id is set, so further logging can be done.

  my $bib_id = MMT::MARC::Regex->controlfield($xmlPtr, '004');
  unless ($bib_id) {
    MMT::Exception::Delete->throw(error => "Missing field 004 with record:\n$$xmlPtr\n!!");
  }
  $s->{biblionumber} = $bib_id; #This might be useful for various translation tables

  MMT::MARC::Regex->controlfield($xmlPtr, '003', MMT::Config::organizationISILCode(), {after => '001'});

  transform852($s, $xmlPtr, $b);

  isSuppressInOPAC($s, $xmlPtr, $b, $holding_id);

  linkBoundRecord($s, $xmlPtr, $b);

  return $holding_id;
}

=head2 Transforms the given MARC Holdings Record to Koha

 @param {MMT::Koha::Holding}
 @param {Reference to a String} MARCXML
 @param {MMT::TBuilder}
 @returns {undef} The given Field reference is mutated in-place

=cut

sub transform852($s, $xmlPtr, $b) {
  # Force ISIL-code to 852$a
  MMT::Config::organizationISILCode() or die "MMT::Config::organizationISILCode() is undefined! Set it in the config/main.yml";
  MMT::MARC::Regex->subfield($xmlPtr, '852', 'a', MMT::Config::organizationISILCode(), {first => 1}) or MMT::Exception::Delete->throw(error => "Unable to set the 852\$a for record:\n$$xmlPtr");

  # Transform 852$b using the location transformation table, set relevant subfields
  my $sfb = MMT::MARC::Regex->subfield($xmlPtr, '852', 'b');
  unless ($sfb) {
    $log->warn($s->logId().' - Missing 852$b. Cannot translate locations.');
  }
  else {
    my $blcsin = $b->{LocationId}->translateByCode($s, undef, $b, $sfb);
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

=head2 linkBoundRecord

Link this Holding under the bound bib's parent record.
Executes only if this Holding is a bound record.
Bound parent record is transparently created if missing in the Loader, because due to the Perl's multi-threading nature of share-nothing, communicating the creation
of the bound parent bib is very difficult and communicating between processes is extra slow.
It is much easier to just spam the DB during loading to check if the bound parent record already exists or not.

=cut

sub linkBoundRecord($s, $xmlPtr, $b) {
  my $biblionumber = MMT::MARC::Regex->controlfield($xmlPtr, '004');
  my $boundParent = $b->{BoundBibParent}->get($biblionumber);
  return unless $boundParent;

  $boundParent = $boundParent->[0]->{bound_parent_bib_id};
  die($s->logId()." - Bound parent biblionumber '$boundParent' is not a valid digit?") unless ($boundParent =~ /^\d+$/);

  $log->info($s->logId()." is a part of a bound record. Linking it under the reserved bound parent record biblionumber '$boundParent'");
  MMT::MARC::Regex->controlfield($xmlPtr, '004', $boundParent);
}

return 1;
