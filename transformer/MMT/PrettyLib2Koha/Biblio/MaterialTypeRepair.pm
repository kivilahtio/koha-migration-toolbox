package MMT::PrettyLib2Koha::Biblio::MaterialTypeRepair;

use Modern::Perl;
use utf8;
use Try::Tiny;

use MMT::Pragmas;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

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
    f008   => '||||||n||||    fi ||||| ||||||f  |    ||',
  },
  AR => {
    code => 'AR',
    description => 'Artikkeli',
    leader => '     naa a22     zu 4500',
    f007   => 'ta',
    f008   => '||||||n||||    xxd|||||||||| ||||||   ||',
  },
  AT => {
    code => 'AT',
    description => 'ATK-tallenne',
    leader => '     nmm a22     zu 4500',
    f007   => 'cd ||||||||',
    f008   => '||||||n||||    fi |||||||||| ||||f|   ||',
  },
  CD => {
    code => 'CD',
    description => 'CD-äänilevy',
    leader => '     njm a22     zu 4500',
    f007   => 'sd f||g|||m|||',
    f008   => '      n||||    xxu||nn  ||||||   |     |',
  },
  DI => {
    code => 'DI',
    description => 'Dia',
    leader => '     ngm a22     zu 4500',
    f007   => 'g| ||||||',
    f008   => '      n        fi |||       |    d|   ||',
  },
  DV => {
    code => 'DV',
    description => 'DVD, videotallenne',
    leader => '     ngm a22     zu 4500',
    f007   => 'vd cvaiz|',
    f008   => '      n        fi |||       |    v|   ||',
  },
  EA => {
    code => 'EA',
    description => 'Elektroninen aineisto',
    leader => '     nmm a22     zu 4500',
    f007   => 'cr |||||||||||',
    f008   => '      n           ||||      |||| ||   ||',
  },
  EJ => {
    code => 'EJ',
    description => 'Elektroninen kausijulkaisu',
    leader => '     nas a22     zu 4500',
    f007   => 'cr#|||||||||||',
    f008   => '      n        xxu|||||o|||| |###|     |',
  },
  EK => {
    code => 'EK',
    description => 'E-Kirja',
    leader => '     nam a22     zu 4500',
    f007   => 'cr |||||||||||',
    f008   => '      n           |||| o    |||| ||   ||',
  },
  ES => {
    code => 'ES',
    description => 'Esine',
    leader => '     nrm a22     zu 4500',
    f007   => 'z|',
    f008   => '      n||||||||xx |||||     ||   rn|||||',
  },
  KA => {
    code => 'KA',
    description => 'Kausijulkaisu/Sarjajulkaisu',
    leader => '     nas a22     zu 4500',
    f008   => '      n        xxu||||| |||| 00| 0     |',
    componentPart => 's',
  },
  KN => 'KI', # Kansio
  KI => {
    code => 'KI',
    description => 'Kirja',
    leader => '     nam a22     zu 4500',
    f008   => '||||||n||||    fi |||||||||| ||||||   ||',
  },
  KM => 'KI', # Konemanuaali
  KO => 'KI', # Kokousjulkaisu
  KR => {
    code => 'KR',
    description => 'Kartta',
    leader => '     nem a22     zu 4500',
    f007   => 'a| ca|||',
    f008   => '      n           ||||| |||| 00|       |',
  },
  KV => 'KI', # Kalvot
  LA => {
    code => 'LA',
    description => 'Lautapeli',
    leader => '     nrm a22     zu 4500',
    f007   => 'zu',
    f008   => '      n        fi ||| |      |   g|   ||',
  },
  MA => 'KI', # Määräys
  MO => 'KI', # Moniste
  MM => 'AT', # Multimedia
  MV => {
    code => 'MV',
    description => 'Moniviestin',
    leader => '     nom a22     zu 4500',
    f007   => 'ou',
    f008   => '||||||n||||    xxd|||       |    b||||||',
  },
  NU => {
    code => 'NU',
    description => 'Nuotti',
    leader => '     ncm a22     zu 4500',
    f007   => 'qu',
    f008   => '||||||n||||    fi ||||||||||||||||||||||',
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
    f008   => '      n||||    xxu||nn  ||||||   |     |',
  },
  ST => 'KI', # Standardi
  TK => 'KN', # Tuotekansio
  TU => 'OP', # Tutkimus
  VI => {
    code => 'VI',
    description => 'Video (VHS)',
    leader => '     ngm a22     zu 4500',
    f007   => 'vf |ba|||',
    f008   => '||||||n||||    xxd|||||||||| ||||v|   ||',
  },
  VA => {
    code => 'VA',
    description => 'Valokuva',
    leader => '     nkm#a22     zu#4500',
    f007   => 'k|#||#',
    f008   => '      n        fi ||| |     ||   |||||||',
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

    # Set the publication date to 008
    my $pd = $r->publicationDate();
    substr($fw->{f008},7,4) = substr($pd,0,4) if ($pd);

    if ($fw->{leader}) {
        $r->leader( characterReplace($fw->{leader}, 7, $fw->{componentPart} || 'a') ) if ($r->isComponentPart());
    }
    $r->addUnrepeatableSubfield('007', '0', $fw->{f007}) if ($fw->{f007});
    $r->addUnrepeatableSubfield('008', '0', $fw->{f008}) if ($fw->{f008});
    $r->addUnrepeatableSubfield('999', 'b', $fw->{code} || die $s->logId()." No framework code!");
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

