package MMT::PrettyLib2Koha::Biblio::MaterialTypeRepair;

use Modern::Perl;
use utf8;
use Try::Tiny;

use MMT::Pragmas;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use MMT::PrettyLib2Koha::Biblio::MARC21CodeListForCountries;
use MMT::PrettyLib2Koha::Biblio::MARC21CodeListForLanguages;

=head2 TAKEN FROM

https://github.com/KohaSuomi/OrigoMMTPerl/blob/master/MMT/Biblios/MaterialTypeRepair.pm

=head2 SYNOPSIS

Enforce MARC21 Record's leader and control field contents to match a itemtype.

=cut

my $statistics;

#DUPLICATION WARNING!
#KohaLoader/bulkMARCFrameworkImport.pl needs updated changes from here!
my %frameworks = (
  AA => {
    code => 'AA',
    description => 'Äänikirja',
    leader => '     nim a22     zu 4500',
    f007   => 'sd f||g|||m|||',
    f008   => '||||||n||||    xx#||||| ||||||f  |    ||',
  },
  AR => {
    code => 'AR',
    description => 'Artikkeli',
    leader => '     naa a22     zu 4500',
    f007   => 'ta',
    f008   => '||||||n||||    xx#|||||||||| ||||||   ||',
  },
  AT => {
    code => 'AT',
    description => 'ATK-tallenne',
    leader => '     nmm a22     zu 4500',
    f007   => 'cd ||||||||',
    f008   => '||||||n||||    xx#|||||||||| ||||f|   ||',
  },
  CD => {
    code => 'CD',
    description => 'CD-äänilevy',
    leader => '     njm a22     zu 4500',
    f007   => 'sd f||g|||m|||',
    f008   => '      n||||    xx#||nn  ||||||   |     |',
  },
  DI => {
    code => 'DI',
    description => 'Dia',
    leader => '     ngm a22     zu 4500',
    f007   => 'g| ||||||',
    f008   => '      n        xx#|||       |    d|   ||',
  },
  DV => {
    code => 'DV',
    description => 'DVD, videotallenne',
    leader => '     ngm a22     zu 4500',
    f007   => 'vd cvaiz|',
    f008   => '      n        xx#|||       |    v|   ||',
  },
  EA => {
    code => 'EA',
    description => 'Elektroninen aineisto',
    leader => '     nmm a22     zu 4500',
    f007   => 'cr |||||||||||',
    f008   => '      n        xx#||||      |||| ||   ||',
  },
  EJ => {
    code => 'EJ',
    description => 'Elektroninen kausijulkaisu',
    leader => '     nas a22     zu 4500',
    f007   => 'cr#|||||||||||',
    f008   => '      n        xx#|||||o|||| |###|     |',
  },
  EK => {
    code => 'EK',
    description => 'E-Kirja',
    leader => '     nam a22     zu 4500',
    f007   => 'cr |||||||||||',
    f008   => '      n        xx#|||| o    |||| ||   ||',
  },
  ES => {
    code => 'ES',
    description => 'Esine',
    leader => '     nrm a22     zu 4500',
    f007   => 'z|',
    f008   => '      n||||||||xx#|||||     ||   rn|||||',
  },
  KA => {
    code => 'KA',
    description => 'Kausijulkaisu/Sarjajulkaisu',
    leader => '     nas a22     zu 4500',
    f008   => '      n        xx#||||| |||| 00| 0     |',
    componentPart => 's',
  },
  KN => 'KI', # Kansio
  KI => {
    code => 'KI',
    description => 'Kirja',
    leader => '     nam a22     zu 4500',
    f008   => '||||||n||||    xx#|||||||||| ||||||   ||',
  },
  KM => 'KI', # Konemanuaali
  KO => 'KI', # Kokousjulkaisu
  KR => {
    code => 'KR',
    description => 'Kartta',
    leader => '     nem a22     zu 4500',
    f007   => 'a| ca|||',
    f008   => '      n        xx#||||| |||| 00|       |',
  },
  KV => 'KI', # Kalvot
  LA => {
    code => 'LA',
    description => 'Lautapeli',
    leader => '     nrm a22     zu 4500',
    f007   => 'zu',
    f008   => '      n        xx#||| |      |   g|   ||',
  },
  MA => 'KI', # Määräys
  MO => 'KI', # Moniste
  MM => 'AT', # Multimedia
  MV => {
    code => 'MV',
    description => 'Moniviestin',
    leader => '     nom a22     zu 4500',
    f007   => 'ou',
    f008   => '||||||n||||    xx#|||       |    b||||||',
  },
  NU => {
    code => 'NU',
    description => 'Nuotti',
    leader => '     ncm a22     zu 4500',
    f007   => 'qu',
    f008   => '||||||n||||    xx#||||||||||||||||||||||',
  },
  OM => 'KI', # Oppimateriaali
  OP => 'KI', # Opinnäytetyö
  RA => 'KI', # Raportti
  PP => 'KI', # Pienpainate
  SA => 'KA', # Sarjajulkaisu
  SO => 'KI', # Sopimus
  SR => {
    code => 'SR',
    description => 'Äänite',
    leader => '     njm a22     zu 4500',
    f007   => 'sd f||g|||m|||',
    f008   => '      n||||    xx#||nn  ||||||   |     |',
  },
  ST => 'KI', # Standardi
  TK => 'KN', # Tuotekansio
  TU => 'OP', # Tutkimus
  VI => {
    code => 'VI',
    description => 'Video (VHS)',
    leader => '     ngm a22     zu 4500',
    f007   => 'vf |ba|||',
    f008   => '||||||n||||    xx#|||||||||| ||||v|   ||',
  },
  VA => {
    code => 'VA',
    description => 'Valokuva',
    leader => '     nkm#a22     zu#4500',
    f007   => 'k|#||#',
    f008   => '      n        xx#||| |     ||   |||||||',
  },
);
#DUPLICATION WARNING!
#KohaLoader/bulkMARCFrameworkImport.pl needs updated changes from here!
sub getFrameworkDetails {
  my ($frameworkCode, $biblionumber, $depth_) = @_;
  $depth_ = 0 unless $depth_;

  if ($depth_ > 5) {
    $log->warn("biblionumber='$biblionumber': Too deep recursion looking for frameworkCode, last key '$frameworkCode'!");
    return {};
  }
  unless ($frameworks{$frameworkCode}) {
    return {};
  }
  if (ref $frameworks{$frameworkCode} ne 'HASH') {
    return getFrameworkDetails($frameworks{$frameworkCode}, $biblionumber, $depth_+1);
  }
  return $frameworks{$frameworkCode};
}

sub forceControlFields {
  $DB::single=1;
    my ($s, $o, $b) = @_;
    my ($r, $itemType) = ($s->{record}, $s->{record}->getUnrepeatableSubfield('942', 'c')->content());

    if (my $mother_id = $r->isComponentPart()) {
        my $mother = $b->{Titles}->get($mother_id);
        if ($mother) {
          $itemType = $MMT::TranslationTable::ItemTypes::PL_defaultTitleTypes{$mother->[0]->{TitleType}};
        }
    }

    # Translation tables might change the default itype mappings to something completely new. So reconcile here.
    my $fw = getFrameworkDetails($MMT::TranslationTable::ItemTypes::PL_defaultTitleTypes{$o->{TitleType}}, $s->{biblionumber});
    unless ($fw) {
        $log->warn($s->logId()." Unknown frameworkCode '".$MMT::TranslationTable::ItemTypes::PL_defaultTitleTypes{$o->{TitleType}}."' for TitleType='".$o->{TitleType}."'!");
        $fw = getFrameworkDetails($itemType, $s->{biblionumber});
    }
    unless ($fw) {
        $log->warn($s->logId()." Unknown frameworkCode '$itemType'! Defaulting to 'KI'.");
        $fw = getFrameworkDetails('KI', $s->{biblionumber});
    }
    my %fw = %$fw; #Clone the framework fields, to avoid mutating the global defaults.

  unless ($fw{leader}) {
    $log->error($s->logId." - Record is missing the template 'leader' for framework='".$fw{code}."'");
    $fw{leader} = '     nam a22     zu 4500';
  }
  unless ($fw{f008}) {
    $log->error($s->logId." - Record is missing the template 'f008' for framework='".$fw{code}."'");
    $fw{f008} = '||||||n||||    fi |||||||||| ||||||   ||';
  }
  unless ($fw{code}) {
    $log->error($s->logId." - Record is missing the template 'code' for framework='".$fw{code}."'");
    $fw{code} = 'KI';
  }

  if ($r->isComponentPart()) {
    substr($fw{leader}, 7, 1) = $fw{componentPart} || 'a';
  }
  $r->leader($fw{leader});
  $r->addUnrepeatableSubfield('007', '0', $fw{f007}) if ($fw{f007});
  $r->addUnrepeatableSubfield('008', '0', _build008($s, $o, $b, $fw{f008}));
  $r->addUnrepeatableSubfield('999', 'b', $fw{code});
}

# F008 in PrettyLib seems to be in MARC21-format already.
sub decomposeF008 {
  my ($s, $o, $b) = @_;
  return undef unless ($o->{F008});

  #$log->trace($s->logId." - TitleType='".$o->{TitleType}."', F008='".$o->{F008}."'"); #Get a report of F008 usage patterns

  #Check F008
  unless ($o->{F008} =~ /^
      (?<tallennuspaiva>.{6})        #First four elements are the same for FinMARC and MARC21
      (?<aikaindikaattori>.{1})      #
      (?<julkaisuaika>.{8})          #
      (?<julkaisumaa>.{3})           #
      (?<materiaalikohtaiset>.{17})?
      (?<kieli>.{3})?                #MARC21
      (?<modifiedRecord>.{1})?       #
      (?<luetteloinninLahde>.{1})?   #
    $/x) {
    $log->warn($s->logId." - F008 yhteiset tiedot malformed '".$o->{F008}."'");
    return undef;
  }
  my %d = %+;

  unless ($d{tallennuspaiva} =~ /^[ |#]{6}|([0-9]{6})$/) {
    $log->warn($s->logId." - F008 tallennuspaiva malformed '$d{tallennuspaiva}'");
    $d{tallennuspaivaValid} = undef;
  }
  else {
    $d{tallennuspaivaValid} = $1 || undef;
  }

  unless ($d{aikaindikaattori} =~ /^[srmcdxq ]$/) {
    $log->warn($s->logId." - F008 aikaindikaattori malformed '$d{aikaindikaattori}'");
    $d{aikaindikaattoriValid} = undef;
  }
  else {
    $d{aikaindikaattoriValid} = $d{aikaindikaattori} || undef;
  }

  unless ($d{julkaisuaika} =~ /^
      [ |#]{4}|([0-9]{4})
      [ |#]{4}|([0-9]{4})
    $/x) {
    $log->warn($s->logId." - F008 julkaisuaika malformed '$d{julkaisuaika}'");
    $d{julkaisuaikaValid1} = undef;
    $d{julkaisuaikaValid2} = undef;
  }
  else {
    $d{julkaisuaikaValid1} = $1;
    $d{julkaisuaikaValid2} = $2;
  }

  if ($d{julkaisumaa} =~ /^([a-zA-Z]{2,3})[ |#]{0,1}$/) {
    if ($MMT::PrettyLib2Koha::Biblio::MARC21CodeListForCountries::clfc{lc($1)}) {
      $d{julkaisumaaValid} = lc($1);
    }
    else {
      my ($hotfix, $hotDescription) = MMT::PrettyLib2Koha::Biblio::MARC21CodeListForCountries::hotfix($1);
      $log->warn($s->logId." - F008 julkaisumaa is not a valid MARC21 2 or 3-character country code '$d{julkaisumaa}'.".($hotfix ? " Assuming '$hotfix'='$hotDescription' was meant instead." : ""));
      $d{julkaisumaaValid} = $hotfix || undef;
    }
  }
  elsif ($d{julkaisumaa} =~ /^[ |#]{1,3}$/) {  # Many F008 records are borken beyond recognition, so allow room for error
    $d{julkaisumaaValid} = undef;
  }
  else {
    $log->warn($s->logId." - F008 julkaisumaa malformed '$d{julkaisumaa}'");
    $d{julkaisumaaValid} = undef;
  }

  if ($d{kieli}) {
    if ($d{kieli} =~ /^[a-zA-Z]{3}$/) {
      if ($MMT::PrettyLib2Koha::Biblio::MARC21CodeListForLanguages::clfl{lc($d{kieli})}) {
        $d{kieliValid} = lc($d{kieli});
      }
      else {
        $log->warn($s->logId." - F008 kieli is not a valid MARC21 3-character language code '$d{kieli}'");
        $d{kieliValid} = undef;
      }
    }
    elsif ($d{kieli} =~ /^[ |#]{1,3}$/) { # Many F008 records are borken beyond recognition, so allow room for error
      $d{kieliValid} = undef;
    }
  }

  if ($d{modifiedRecord} && $d{modifiedRecord} !~ /^[#dorsx |]$/) {
    $d{modifiedRecord} = ' ';
    $log->warn($s->logId." - F008 'modifiedRecord'='$d{modifiedRecord}' is not one of '[#dorsx |]'! Using ' '.");
  }

  if ($d{luetteloinninLahde} && $d{luetteloinninLahde} !~ /^[#cdu |]$/) {
    $d{luetteloinninLahde} = ' ';
    $log->warn($s->logId." - F008 'luetteloinninLahde'='$d{luetteloinninLahde}' is not one of '[#cdu |]'! Using ' '.");
  }

  return \%d;
}

sub _build008($s, $o, $b, $f008Template) {
  $o->{SaveDate} =~ /\d\d(\d\d)-(\d\d)-(\d\d)/;
  $o->{dateEnteredOnFile} = ($1 ? $1 : 00).($2 ? $2 : 00).($3 ? $3 : 00);

  my $f008decomposed = decomposeF008($s, $o);

  my $language = ($f008decomposed->{kieliValid} ? $f008decomposed->{kieliValid} : ($s->{record}->language() ? $s->{record}->language() : '###'));
  unless ($MMT::PrettyLib2Koha::Biblio::MARC21CodeListForLanguages::clfl{lc($language)}) {
    $log->warn($s->logId." - F008 language is not a valid MARC21 3-character language code '$language'");
  }

  my $l = $f008Template;
## Character Positions 
#00-05 - Date entered on file
  substr($l, 0, 6) = $f008decomposed->{tallennuspaivaValid} || $o->{dateEnteredOnFile};
#06 - Type of date/Publication status
#
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
  substr($l, 6, 1) = ($f008decomposed->{aikaindikaattoriValid} ? ($f008decomposed->{aikaindikaattoriValid} eq ' ' ? 'c' : $f008decomposed->{aikaindikaattoriValid}) : '|');

#07-10 - Date 1
#
#    1-9 - Date digit
#    # - Date element is not applicable
#    u - Date element is totally or partially unknown
#    |||| - No attempt to code
  substr($l, 7, 4) = ($f008decomposed->{julkaisuaikaValid1} ? $f008decomposed->{julkaisuaikaValid1} : (getPublicationYear($o) ? getPublicationYear($o) : '||||'));

#11-14 - Date 2
#
#    1-9 - Date digit
#    # - Date element is not applicable
#    u - Date element is totally or partially unknown
#    |||| - No attempt to code
  substr($l, 11, 4) = ($f008decomposed->{julkaisuaikaValid2} ? $f008decomposed->{julkaisuaikaValid2} : '||||');

#15-17 - Place of publication, production, or execution
#
#    xx# - No place, unknown, or undetermined
#    vp# - Various places
#    [aaa] - Three-character alphabetic code
#    [aa#] - Two-character alphabetic code
  substr($l, 15, 3) = ($f008decomposed->{julkaisumaaValid} ? MMT::PrettyLib2Koha::Biblio::MARC21CodeListForCountries::F008_15padded($f008decomposed->{julkaisumaaValid}) : 'xx#');

#18-34 - Material specific coded elements
  #'|||||||||||||||||';

#35-37 - Language
#
#    ### - No information provided
#    zxx - No linguistic content
#    mul - Multiple languages
#    sgn - Sign languages
#    und - Undetermined
#    [aaa] - Three-character alphabetic code
  substr($l, 35, 3) = $language;

#38 - Modified record
#
#    # - Not modified
#    d - Dashed-on information omitted
#    o - Completely romanized/printed cards romanized
#    r - Completely romanized/printed cards in script
#    s - Shortened
#    x - Missing characters
#    | - No attempt to code
  substr($l, 38, 1) = ($f008decomposed->{modifiedRecord} ? $f008decomposed->{modifiedRecord} : '|');

#39 - Cataloging source
#
#    # - National bibliographic agency
#    c - Cooperative cataloging program
#    d - Other
#    u - Unknown
#    | - No attempt to code 
  substr($l, 39, 1) = ($f008decomposed->{luetteloinninLahde} ? $f008decomposed->{luetteloinninLahde} : '|');

  return $l;
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

=head3 Replace the character in the given position with the substitute string.

=item @Param1 the string scalar.
=item @param2 the location scalar starting from 0 which to substitute
=item @param3 the substitute string used to make the substitution

=cut

sub characterReplace {
	my $str = $_[0];
	$str =~ s/(?<=^.{$_[1]})./$_[2]/;
	return $str;
}



1;

