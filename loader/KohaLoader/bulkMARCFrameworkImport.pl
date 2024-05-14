#!/usr/bin/perl

#Pragmas
use Modern::Perl;
use experimental 'smartmatch', 'signatures';
binmode( STDOUT, ":encoding(UTF-8)" );
binmode( STDIN,  ":encoding(UTF-8)" );
use utf8;
use Carp;
#$|=1; #Are hot filehandles necessary?

# External modules
use Getopt::Long;
use Log::Log4perl qw(:easy);
use Data::Dumper;

use C4::Context;
use Koha::BiblioFramework;
use Koha::BiblioFrameworks;
use Koha::MarcSubfieldStructures;

our $verbosity = 3;
my %args = (inputMarcFile =>                      ($ENV{MMT_DATA_SOURCE_DIR}//'.').'/biblios.marcxml',
#            workers =>           4
);

Getopt::Long::GetOptions(
  'file:s'              => \$args{inputMarcFile},
  'v:i'                 => \$verbosity,
  'version'             => sub { Getopt::Long::VersionMessage() },
  'h|help'              => sub {
  print <<HELP;

NAME
  $0 - Import MARC21 biblio frameworks

SYNOPSIS
  perl ./bulkMARCFrameworkImport.pl --file '/home/koha/biblios.marcxml' -v $verbosity

DESCRIPTION
  -Detects the used MARC21 frameworks from the given MARC collection and loads matching frameworks to Koha.
  --File MUST be in UTF-8
  --File MUST contain MARC21 bibliographic records

    --file filepath
          The MARC21XML file

    -v level
          Verbose output to the STDOUT,
          Defaults to $verbosity, 6 is max verbosity, 0 is fatal only.

    --version
          Print version info

HELP
  exit 0;
},
); #EO Getopt::Long::GetOptions()

require Bulk::Util; #Init logging && verbosity

Bulk::Util::logArgs(\%args);

unless ($args{inputMarcFile}) {
  die "--file is mandatory";
}

#DUPLICATION WARNING!
#PrettyLib2Koha/Biblio/MaterialTypeRepair.pm needs updated changes from here!
my %frameworks = (
  #PrettyLib
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
  #Some other ILS
  #...
);
#DUPLICATION WARNING!
#PrettyLib2Koha/Biblio/MaterialTypeRepair.pm needs updated changes from here!
sub getFrameworkDetails {
  my ($frameworkCode, $biblionumber, $depth_) = @_;
  $depth_ = 0 unless $depth_;

  if ($depth_ > 5) {
    warn("biblionumber='$biblionumber': Too deep recursion looking for frameworkCode, last key '$frameworkCode'!");
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

my %frameworkCodes;
my $i = 0;
my $start = time;

print "Collecting framework codes from $args{inputMarcFile}\n";
my $next = Bulk::Util::getMarcFileIterator($args{inputMarcFile});
while (my $recordXmlPtr = $next->()) {
  $i++;
  unless ($$recordXmlPtr =~ m|<datafield tag="999".+?<subfield code="b">(\w+)</subfield>.+?</datafield>|gsm) {
    warn "Missing Subfield 999\$b (frameworkCode) from record!\n$$recordXmlPtr\n\n";
    next;
  }
  $frameworkCodes{$1} = $frameworkCodes{$1} ? $frameworkCodes{$1}+1 : 1;
}
print "Collected codes from '$i' records in ".(time - $start)."s\n";

sub addMARCFramework {
    $DB::single=1;
  my ($frameworkCode) = @_;

  my $fw = getFrameworkDetails($frameworkCode);
  unless ($fw) {
    warn "Missing definition for framework '$frameworkCode'! Fix this in MaterialTypeRepair.pm!";
    return;
  }

  # copypaste from intranet/cgi-bin/admin/biblio_framework.pl
  # No proper accessors exist
  my $framework = Koha::BiblioFrameworks->find($fw->{code});
  unless ($framework) {
    $framework = Koha::BiblioFramework->new(
      { frameworkcode => $fw->{code},
        frameworktext => $fw->{description},
      }
    );
    eval { $framework->store; };
    if ($@) {warn $@;}
  }

  # copypaste from intranet/cgi-bin/admin/marc_subfields_structure.pl
  # No proper accessors exists
  #
  # the sub used to duplicate a framework from an existing one in MARC parameters tables.
  #
  sub duplicate_framework {
    my ($newframeworkcode,$oldframeworkcode) = @_;
    my $dbh = C4::Context->dbh;
    $dbh->do(q|INSERT IGNORE INTO marc_tag_structure (tagfield, liblibrarian, libopac, repeatable, mandatory, important, authorised_value, ind1_defaultvalue, ind2_defaultvalue, frameworkcode)
        SELECT tagfield,liblibrarian,libopac,repeatable,mandatory,important,authorised_value, ind1_defaultvalue, ind2_defaultvalue, ? from marc_tag_structure where frameworkcode=?|,
        undef, $newframeworkcode, $oldframeworkcode )
      or die $dbh->errstr;

    $dbh->do(q|INSERT IGNORE INTO marc_subfield_structure (frameworkcode,tagfield,tagsubfield,liblibrarian,libopac,repeatable,mandatory,important,kohafield,tab,authorised_value,authtypecode,value_builder,isurl,seealso,hidden,link,defaultvalue,maxlength)
        SELECT ?,tagfield,tagsubfield,liblibrarian,libopac,repeatable,mandatory,important,kohafield,tab,authorised_value,authtypecode,value_builder,isurl,seealso,hidden,link,defaultvalue,maxlength from marc_subfield_structure where frameworkcode=?|,
        undef, $newframeworkcode, $oldframeworkcode )
      or die $dbh->errstr;
  }
  duplicate_framework($fw->{code}, '');

  sub updateFrameworkControlField {
    my ($frameworkCode, $fieldNumber, $controlFieldContents) = @_;
    my $mss = Koha::MarcSubfieldStructures->find({tagfield => $fieldNumber, tagsubfield => '@', frameworkcode => $frameworkCode });
    if ($mss) {
      eval { $mss->update({
        defaultvalue => $controlFieldContents,
      }) };
      if ($@) {warn $@;}
    }
    else {
      warn "Framework='$frameworkCode' is missing field='$fieldNumber'!";
    }
  }
  updateFrameworkControlField($fw->{code}, '000', $fw->{leader}) if $fw->{leader};
  updateFrameworkControlField($fw->{code}, '001', $fw->{f001}) if $fw->{f001};
  updateFrameworkControlField($fw->{code}, '002', $fw->{f002}) if $fw->{f002};
  updateFrameworkControlField($fw->{code}, '003', $fw->{f003}) if $fw->{f003};
  updateFrameworkControlField($fw->{code}, '004', $fw->{f004}) if $fw->{f004};
  updateFrameworkControlField($fw->{code}, '005', $fw->{f005}) if $fw->{f005};
  updateFrameworkControlField($fw->{code}, '006', $fw->{f006}) if $fw->{f006};
  updateFrameworkControlField($fw->{code}, '007', $fw->{f007}) if $fw->{f007};
  updateFrameworkControlField($fw->{code}, '008', $fw->{f008}) if $fw->{f008};
  updateFrameworkControlField($fw->{code}, '009', $fw->{f009}) if $fw->{f009};
}
addMARCFramework($_) for keys %frameworkCodes;