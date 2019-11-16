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

#EGDATA-116
## Initializing anonymous sanitation functions
my ($leader, $f007, $f008, $componentPart) = (undef, undef, undef, 'a');

sub AA { # Äänikirja
    $leader = '     nim a22     zu 4500';
    $f007   = 'sd f||g|||m|||';
    $f008   = '||||||s||||    fi ||||| ||||||f  | fin|c';
}
sub AR { # Artikkeli
    $leader = '     naa a22     zu 4500';
    $f007   = 'ta';
    $f008   = '||||||s||||    xxd|||||||||| ||||||   |c';
}
sub AT { # ATK-tallenne
    $leader = '     nmm a22     zu 4500';
    $f007   = 'cd ||||||||';
    $f008   = '||||||s||||    fi |||||||||| ||||f|fin|c';
}
sub CD { # CD-äänilevy
    $leader = '     njm a22     zu 4500';
    $f007   = 'sd f||g|||m|||';
    $f008   = '      s||||    xxu||nn  ||||||   | eng c';
}
sub DI { # Dia
    $leader = '     ngm a22     zu 4500';
    $f007   = 'g| ||||||';
    $f008   = '      s        fi |||       |    d|fin|c';
}
sub DV { # DVD, videotallenne
    $leader = '     ngm a22     zu 4500';
    $f007   = 'vd cvaiz|';
    $f008   = '      s        fi |||       |    v|fin|c';
}
sub EA { # Elektroninen aineisto
    EK()
}
sub EK { # E-Kirja
    $leader = '     nam a22     zu 4500';
    $f007   = 'cr |||||||||||';
    $f008   = '      s           |||| o    |||| ||   |c';
}
sub ES { # Esine
    $leader = '     nrm a22     zu 4500';
    $f007   = 'z|';
    $f008   = '      b        xxd||||| |||| 00| 0    ||';
}
sub KA { # Kausijulkaisu/Sarjajulkaisu
    $leader = '     nas a22     zu 4500';
    $f008   = '191104b        xxu||||| |||| 00| 0 fin d';
	$componentPart = 's';
}
sub KI { # Kirja
    $leader = '     nam a22     zu 4500';
    $f008   = '||||||s||||    fi |||||||||| ||||f|fin|c';
}
sub KR { # Kartta
    $leader = '     nem a22     zu 4500';
    $f007   = 'a| ca|||';
    $f008   = '      s           ||||| |||| 00|       c';
}
sub LA { # Lautapeli
    $leader = '     nrm a22     zu 4500';
    $f007   = 'zu';
    $f008   = '      s        fi ||| |      |   g|fin|c';
}
sub MO {
    KI()
}
sub MV { # Moniviestin
    $leader = '     nom a22     zu 4500';
    $f007   = 'ou';
    $f008   = '||||||s||||    xxd|||       |    b||||||';
}
sub NU { # Nuotti
    $leader = '     ncm a22     zu 4500';
    $f007   = 'qu';
    $f008   = '||||||s||||    fi |||||||||||||||||||||c';
};
sub OP { # Opinnäytetyö
    KI()
}
sub PP { # Pienpainate
    KI()
}
sub SR { # Äänite
    $leader = '     njm a22     zu 4500';
    $f007   = 'sd f||g|||m|||';
    $f008   = '      s||||    xxu||nn  ||||||   | fin c';
}
sub ST { # Standardi
    KI()
}
sub VI { # Video (VHS)
    $leader = '     ngm a22     zu 4500';
    $f007   = 'vf |ba|||';
    $f008   = '||||||s||||    xxd|||||||||| ||||v|   |c';
}

sub forceControlFields {
    my ($s, $o, $b) = @_;
    my ($r, $itemType) = ($s->{record}, $s->{record}->getUnrepeatableSubfield('942', 'c')->content());

    ($leader, $f007, $f008, $componentPart) = (undef, undef, undef, 'a');

    if    ($itemType eq 'KI') { KI() } # PrettyLib 0 => KI
    elsif ($itemType eq 'CD') { SR() } # PrettyLib 1 => CD
    elsif ($itemType eq 'NU') { NU() } # PrettyLib 2 => NU
    elsif ($itemType eq 'KA') { KA() } # PrettyLib 3 => KA
    elsif ($itemType eq 'ES') { ES() } # PrettyLib 8 => ES
    elsif ($itemType eq 'DV') { DV() } # PrettyLib ? => DV
    elsif ($itemType eq 'KN') { KI() } # PrettyLib ? => KI # Kansio to Book
    elsif ($itemType eq 'OP') { KI() } # PrettyLib ? => KI # Opinnäytetyö to Book
    else {
        $log->warn($s->logId()." Unknown itemtype '$itemType' to force control fields and leader. Defaulting to KI");
        KI();
    }

    # Set the publication date to 008
    my $pd = $r->publicationDate();
    $f008 = substr($f008,7,4,substr($pd,0,4)) if ($pd);

    if ($leader) {
        $leader = characterReplace($leader, 7, $componentPart) if ($r->isComponentPart());
        $r->leader( $leader );
    }
    $r->addUnrepeatableSubfield('007', '0', $f007) if ($f007);
    $r->addUnrepeatableSubfield('008', '0', $f008) if ($f008);
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

