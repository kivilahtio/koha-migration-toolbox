package MMT::Koha::Holding;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::Builder;
use MMT::MARC::Record;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::Koha::Holding - Transform holdings

=cut

=head2 build

 @param1 Voyager xml record
 @param2 Builder

=cut

sub build($s, $xmlPtr, $b) {
  $s->{r} = MMT::MARC::Record->newFromXml($xmlPtr);
  $s->{id} = $s->{r}->docId();

  #Dispatch using the configured transformation module.
  unless ($b->{holdingsTransformationModule}) {
    my $package = 'MMT::Koha::Holding::'.MMT::Config::holdingsTransformationModule;
    MMT::Builder::__dynaload($package);
    $b->{holdingsTransformationModule} = $package->can('transform');
    die "Couldn't find the transform()-subroutine from package '$package', using configuration: holdingsTransformationModule='".MMT::Config::holdingsTransformationModule."'." unless ($b->{holdingsTransformationModule});
  }
  $b->{holdingsTransformationModule}->($s, $s->{r}, $b);

  return $s;
}

sub logId($s) {
  return "Holding '".$s->id()."'";
}

sub id($s) {
  return $s->{id};
}

=head2 serialize

MARC serialization to MARCXML

COPYRIGHT Koha-Suomi Oy
Originally from https://github.com/KohaSuomi/OrigoMMTPerl

=cut

sub serialize($s) {
  my $r = $s->{r};

  my $fieldType;

  my @sb; #Initialize a new StringBuilder(TM) to collect all printable text for one huge IO operation.

  push @sb, '<record format="MARC21" type="Bibliographic" xmlns="http://www.loc.gov/MARC21/slim">'."\n";
  push @sb, '  <leader>'.$r->leader.'</leader>'."\n";

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

return 1;
