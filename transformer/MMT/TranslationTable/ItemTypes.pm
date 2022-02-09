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
    elsif ($an =~ /^Kansio/i) { $it = 'KN' } # Kansio
    elsif ($an =~ /^ka/i)   { $it = 'KA' } # Kasetti
    elsif ($an =~ /^dvd/i)  { $it = 'DV' } # DVD-levy
    elsif ($an =~ /^es/i)   { $it = 'ES' } # Esine
    elsif ($an =~ /^(?:har|hv|j|kl|kmo|kon)/i) { $it = 'ES' }
    elsif ($an =~ /^ki/i)   { $it = 'KI' } # Kirja
    elsif ($an =~ /^lp/i)   { MMT::Exception::Delete::Silently->throw($s->logId()."' LP-items are removed."); } #Feature #95
    elsif ($an =~ /^opin/i) { $it = 'OP' } # Opinnäytetyö
    elsif ($an =~ /^vid/i)  { MMT::Exception::Delete::Silently->throw($s->logId()."' Video-items are silently set to die"); } # Videot poistetaan
  }

  unless ($it) {
    $it = $tableParams->[0];
  }

  $kohaObject->{homebranch} = 'JOE_ARK' if ($it eq 'OP');

  return $it if $it;

  $log->warn($kohaObject->logId()." has unknown item type! Cannot parse AcqNum='$an'.");

  return undef;
}

sub PV_hopea_itypes($s, $kohaObject, $prettyObject, $builder, $itype, $tableParams, $transParams) {
  my $kohaItype = "";
  my $period = $prettyObject->{Period} // 0;
  $period =~ s/[^0-9]+//g;
  $period = 0 unless $period;

  if   ($period == 28) { $kohaItype = 'PV28'; } # 28 vrk vain PV – period 28 
  elsif($period == 360) { $kohaItype = 'PV360'; } # 1 vuoden vain PV – period 360 
  elsif($period == 0) { $kohaItype = 'PV0'; } # Käsikirja (ei lainata) – period 0  
  elsif($period == 999) { $kohaItype = 'PV999'; } # Virkakäyttö ikuinen – period 999 

  else{ $log->warn($kohaObject->logId()." - Unknown PV_hopea_itypes() with \$period='$period'"); $kohaItype = 'KONVERSIO'; }

  return $kohaItype;
}

# The default mapping table used internally by PrettyLib, used by Biblio/MaterialTypeRepair to get the itemtype of the translation of itypes is interrupted by translation tables
our %PL_defaultTitleTypes = (
#0:  KI # Kirja
0 => 'KI',
#1:  CD # CD-levy
1 => 'CD',
#2:  NU # Nuotti
2 => 'NU',
#3:  KA # Kausijulkaisu
3 => 'KA',
#4:  RA # Raportti
4 => 'RA',
#5:  VI # Videotallenne
5 => 'VI',
#6:  DI # Dia
6 => 'DI',
#7:  AR # Artikkeli
7 => 'AR',
#8:  ES # Esine
8 => 'ES',
#9:  OP # Opinnäytetyö
9 => 'OP',
#10: AT # ATK-tallenne
10 => 'AT',
#11: KO # Kokousjulkaisu
11 => 'KO',
#12: ST # Standardi
12 => 'ST',
#13: KR # Kartta
13 => 'KR',
#14: PA # Patentti
14 => 'PA',
#15: TU # Tutkimus
15 => 'TU',
#16: SO # Sopimus
16 => 'SO',
#17: MA # Määräys
17 => 'MA',
#18: PI # Pistekirjoitus
18 => 'PI',
#19: IS # Iso tekstinen
19 => 'IS',
#20: AA # Äänikirja
20 => 'AA',
#21: KV # Kalvot
21 => 'KV',
#23: TK # Tuotekansio
23 => 'TK',
#24: VA # Valokuva
24 => 'VA',
#25: OM # Oppimateriaali
25 => 'OM',
#26: EA # Elektroninen aineisto
26 => 'EA',
#27: MM # Multimedia
27 => 'MM',
#28: VK # Vuosikertomus
28 => 'VK',
#29: PP # Pienpainate
29 => 'PP',
#30: MO # Moniste
30 => 'MO',
#31: TI # Tilastojulkaisu
31 => 'TI',
#32: SA # Sarjajulkaisu
32 => 'SA',
#33: KM # Konemanuuali
33 => 'KM',
#34: EK # E-Kirja
34 => 'EK',
);

return 1;
