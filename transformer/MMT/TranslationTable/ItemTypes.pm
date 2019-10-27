package MMT::TranslationTable::ItemTypes;

use MMT::Pragmas;

#External modules

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::ATranslationTable;
use base qw(MMT::ATranslationTable);

#Exceptions
use MMT::Exception::Delete::Silently;

=head1 NAME

MMT::TranslationTable::ItemTypes - map Voyager item types to koha.items.itype

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/itemtypes.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub example($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  return $tableParams->[0];
}

=head2 JNSKonsa_itypes

JNSKonsa picks the itemtype from the acquisitions number prefix.

 @RETURNS String, 'KONVERSIO' if itype cannot be inferred, otherwise the 2-letter uppercased itemtype.

=cut

my $K = 'KONVERSIO';
sub JNSKonsa_itypes($s, $kohaObject, $prettyObject, $builder, $originalValue, $tableParams, $transParams) {
  my $an = $prettyObject->{AcqNum};
  my $it;
  if ($an) {

    if    ($an =~ /^nu/i)   { $it = 'NU' } # Nuotti
    elsif ($an =~ /^cd/i)   { $it = 'CD' } # CD-Levy
    elsif ($an =~ /^ka/i)   { $it = 'KA' } # Kasetti
    elsif ($an =~ /^dvd/i)  { $it = 'DV' } # DVD-levy
    elsif ($an =~ /^es/i)   { $it = 'ES' } # Esine
    elsif ($an =~ /^(?:har|hv|j|kl|kmo|kon)/i) { $it = 'ES' }
    elsif ($an =~ /^Kansio/i) { $it = 'KN' } # Kansio
    elsif ($an =~ /^ki/i)   { $it = 'KI' } # Kirja
    elsif ($an =~ /^lp/i)   { $it = 'LP' } # LP:t viedään Kohaan tutkimista varten, tuotannossa poistetaan
    elsif ($an =~ /^opin/i) { $it = 'OP' } # Opinnäytetyö
    elsif ($an =~ /^vid/i)  { MMT::Exception::Delete::Silently->throw($s->logId()."' Video-items are silently set to die"); } # Videot poistetaan

  }

  unless ($it) {

    $it = $tableParams->[0];

  }

  return $it if $it;

  $log->warn($kohaObject->logId()." has unknown item type! Cannot parse AcqNum='$an'.");

  return undef;
}

return 1;
