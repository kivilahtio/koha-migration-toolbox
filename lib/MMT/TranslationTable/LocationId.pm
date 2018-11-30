package MMT::TranslationTable::LocationId;

use MMT::Pragmas;

#External modules

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::ATranslationTable;
use base qw(MMT::ATranslationTable);

#Exceptions

=head1 NAME

MMT::TranslationTable::LocationId - map voyager.location_id to Koha

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/location_id.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub branchLoc($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  return {
    branch => uc($tableParams->[0]),
    location => uc($tableParams->[1]),
    collectionCode => $tableParams->[2],
    sub_location => $tableParams->[3],
    itemtype => $tableParams->[4],
    notforloan => $tableParams->[5],
  };
}

=head2 statisticsLibrary

Custom handling for the Finnish Library of Statistics and information service

Mapping location and circulation specific values based on publication year and call number

=cut

sub statisticsLibrary($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  return branchLoc(@_) unless (ref($kohaObject) eq 'MMT::Koha::Item' || ref($kohaObject) eq 'MMT::Koha::Holding'); #Fall back to the standard translator when necessary.

  my $publicationDate = $builder->{BibText}->get($kohaObject->{biblionumber});
  $publicationDate = $publicationDate->[0]->{begin_pub_date} if $publicationDate;
  my $frequencyIncrement = $builder->{BibSubFrequency}->get($kohaObject->{biblionumber});
  $frequencyIncrement = $frequencyIncrement->[0]->{freq_increment} if $frequencyIncrement;
  my $frequencyIncrementType = $builder->{BibSubFrequency}->get($kohaObject->{biblionumber});
  $frequencyIncrementType = $frequencyIncrementType->[0]->{freq_calc_type} if $frequencyIncrementType;
  my $callNumber = $builder->{MFHDMaster}->get($kohaObject->{holding_id});
  $callNumber = $callNumber->[0]->{display_call_no} if $callNumber;

  my ($location, $itemtype) = _statisticsLibrary(
    $publicationDate,
    $frequencyIncrement,
    $frequencyIncrementType,
    $callNumber,
  );

  return {
    branch         => uc($tableParams->[0]),
    location       => uc($location || $tableParams->[1]),
    collectionCode => $tableParams->[2],
    sub_location   => $tableParams->[3],
    itemtype       => $itemtype || $tableParams->[4],
    notforloan     => $tableParams->[5],
  };
}

#Separate the core logic so it can be tested from another data source,
# see 't/21-stat.fi-location-mappings.t'
# see 'Holdings transformation'
sub _statisticsLibrary($publicationYear, $subscriptionFrequencyIncrement, $subscriptionFrequencyIncrementType, $callNumber) {
  my $subscriptionFrequencyIncrementInDays = (not(defined($subscriptionFrequencyIncrementType)) or $subscriptionFrequencyIncrementType eq '') ? undef :
                                             ($subscriptionFrequencyIncrementType eq 'y') ? 365 * $subscriptionFrequencyIncrement :
                                             ($subscriptionFrequencyIncrementType eq 'm') ? 12  * $subscriptionFrequencyIncrement :
                                             ($subscriptionFrequencyIncrementType eq 'd') ? 1   * $subscriptionFrequencyIncrement :
                                             die "Unknown \$subscriptionFrequencyIncrementType '$subscriptionFrequencyIncrementType'";

  $publicationYear =~ s/[?un]/0/g; #For the purposes of this comparison, treat unknown decades/years as 0
  $publicationYear = 1000 unless $publicationYear; #default all material which doesn't have a publication year to the storage locations

  my ($location, $itemtype);

  #Mapping starts here
  if    ($callNumber =~ m! mk !) { #Mikrokortit -> 2. kerroksen varastossa, lukulaite 1. krs asiakastiloissa
    $location = '2.K';
    $itemtype = 'MC';
  }
  elsif ($callNumber =~ m!^Arkisto TE !) { #Erikoiskokoelma, Lutherin aineisto
    $location = 'VARA';
  }
  elsif ($callNumber =~ m!^Aik ! || $callNumber =~ m!\(Aik\)!) { #Lehdet. Kuluva ja kaksi edellistä vuotta lehtihyllyissä, sitä vanhemmat varastossa (*-lehdet kaikki lehtihyllyissä) 1. krs
    #2018-11-30 painovuosierottelu koskee nykyisin enää vain monoja, eli Tietokirjat, joiden signum on numeroalkuinen (1-3 numeroa)
    $location = 'VARA';
    $itemtype = 'SR';
  }
  elsif ($callNumber =~ m!^FI R !) { #Kotimaisia tilastoja painovuodesta riippumatta, REF
    $location = 'LUK';
  }
  elsif ($callNumber =~ m!^FI !) {
    #2018-11-30 FI-alkuiset signumit listassa: MUUTOS SIJAINTIIN. Niiden kaikkien sijainti pitää olla VARB (eikä 2.K kuten osassa on)
    $location = 'VARB';
  }
  elsif ($callNumber =~ m!INT \d+\.\d+ !) { #INT-alkuiset +blankko+numeroita, joissa piste välissä (kuten INT 2.5) on aina VARS
    $location = 'VARS';
  }
  elsif ($callNumber =~ m!^INT !) { #Kansainväliset (kv) tilastot hyllyluokittain 2005- => Lainataan (2.K)
    #2018-11-30 painovuosierottelu koskee nykyisin enää vain monoja, eli Tietokirjat, joiden signum on numeroalkuinen (1-3 numeroa)
    $location = 'VARS';
  }
  elsif ($callNumber =~ m!^R \d{1,3}(?:/\d+)? !) { #Hakuteokset avohyllyssä
    $location = 'LUK';
  }
  elsif ($callNumber =~ m!^K \d{1,3}(?:/\d+)? !) { #2018-11-30 kun hyllyluokan alussa on yksi K-kirjain -  K+blankko+numeroita (numeroita voi olla 1-3 kpl) - kuten K 36 Sosiaali- ja terveysministeriön - paikka on silloin aina VARB
    #Varastoihin menevät ... Kaikissa tietokirjoissa paikkamerkintä K (K 330)  #Varastoon siirrettäessä alkuperäisen hyllyluokkatunnuksen eteen on lisätty kirjain ”K”
    $location = 'VARB';
  }
  elsif ($callNumber =~ m!^\d{1,3} !) { #painovuosierottelu koskee nykyisin enää vain monoja, eli Tietokirjat, joiden signum on numeroalkuinen (1-3 numeroa), kuten 02 Hupaniittu (painovuosi 2012) joka menee 2.K. Kun siis hyllyluokka alkaa numerolla (numeroita voi olla 1-3 kpl peräkkäin) – kuten 001 Hesmondhalgh
    #paikka voi olla joko VARB tai 2.K. riippuen painovuodesta (2010- 2.K.  ja sitä vanhemmat VARB). Tämä ei näy olevan aina oikein listassa.
    $location = '2.K' if $publicationYear >= 2010;
    $location = 'VARB' unless $location;
  }
  elsif ($callNumber =~ m!^(?:IS|NO|SE) !) { #Islanti, Norjan vuosikirjat, Ruotsi
    $location = 'VARS';
  }
  elsif ($callNumber =~ m!^RUSSICA !) { #RUSSICA menee aina VARA
    $location = 'VARA';
  }
  elsif ($callNumber =~ m!^[A-Z]{2} !) { #2018-11-30 Ideana pitäisi olla siis, että kaikki muut kaksikirjaimiset signumit (paitsi ei IS, NO, SE, jotka menee VARS, ja FI joka menee VARB) menevät VARA. Näitä 2-kirjaimisia maakoodeja on runsas 30.
    $location = 'VARA';
  }
  else {
    $location = 'KONVERSIO';
  }

  return ($location, $itemtype);
}

return 1;
