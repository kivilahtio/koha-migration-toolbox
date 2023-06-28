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
    $f008   = '||||||n||||    fi ||||| ||||||f  |    ||';
}
sub AR { # Artikkeli
    $leader = '     naa a22     zu 4500';
    $f007   = 'ta';
    $f008   = '||||||n||||    xxd|||||||||| ||||||   ||';
}
sub AT { # ATK-tallenne
    $leader = '     nmm a22     zu 4500';
    $f007   = 'cd ||||||||';
    $f008   = '||||||n||||    fi |||||||||| ||||f|   ||';
}
sub CD { # CD-äänilevy
    $leader = '     njm a22     zu 4500';
    $f007   = 'sd f||g|||m|||';
    $f008   = '      n||||    xxu||nn  ||||||   |     |';
}
sub DI { # Dia
    $leader = '     ngm a22     zu 4500';
    $f007   = 'g| ||||||';
    $f008   = '      n        fi |||       |    d|   ||';
}
sub DV { # DVD, videotallenne
    $leader = '     ngm a22     zu 4500';
    $f007   = 'vd cvaiz|';
    $f008   = '      n        fi |||       |    v|   ||';
}
sub EA { # Elektroninen aineisto
    $leader = '     nmm a22     zu 4500';
    $f007   = 'cr |||||||||||';
    $f008   = '      n           ||||      |||| ||   ||';
}
sub EJ { # Elektroninen kausijulkaisu
    $leader = '     nas a22     zu 4500';
    $f007   = 'cr#|||||||||||';
    $f008   = '      n        xxu|||||o|||| |###|     |';
}
sub EK { # E-Kirja
    $leader = '     nam a22     zu 4500';
    $f007   = 'cr |||||||||||';
    $f008   = '      n           |||| o    |||| ||   ||';
}
sub ES { # Esine
    $leader = '     nrm a22     zu 4500';
    $f007   = 'z|';
    $f008   = '      n        xxd||||| |||| 00| 0    ||';
}
sub KA { # Kausijulkaisu/Sarjajulkaisu
    $leader = '     nas a22     zu 4500';
    $f008   = '      n        xxu||||| |||| 00| 0     |';
    $componentPart = 's';
}
sub KN { # Kansio
    KI()
}
sub KI { # Kirja
    $leader = '     nam a22     zu 4500';
    $f008   = '||||||n||||    fi |||||||||| ||||||   ||';
}
sub KM { # Konemanuaali
    KI()
}
sub KO { # Kokousjulkaisu
    KI()
}
sub KR { # Kartta
    $leader = '     nem a22     zu 4500';
    $f007   = 'a| ca|||';
    $f008   = '      n           ||||| |||| 00|       |';
}
sub KV { # Kalvot
    KI()
}
sub LA { # Lautapeli
    $leader = '     nrm a22     zu 4500';
    $f007   = 'zu';
    $f008   = '      n        fi ||| |      |   g|   ||';
}
sub MA { # Määräys
    KI()
}
sub MO { # Moniste
    KI()
}
sub MM { # Multimedia
    AT()
}
sub MV { # Moniviestin
    $leader = '     nom a22     zu 4500';
    $f007   = 'ou';
    $f008   = '||||||n||||    xxd|||       |    b||||||';
}
sub NU { # Nuotti
    $leader = '     ncm a22     zu 4500';
    $f007   = 'qu';
    $f008   = '||||||n||||    fi ||||||||||||||||||||||';
};
sub OM { # Oppimateriaali
    KI()
}
sub OP { # Opinnäytetyö
    KI()
}
sub RA { # Raportti
    KI()
}
sub PP { # Pienpainate
    KI()
}
sub SA { # Sarjajulkaisu
    KA()
}
sub SO { # Sopimus
    KI()
}
sub SR { # Äänite
    $leader = '     njm a22     zu 4500';
    $f007   = 'sd f||g|||m|||';
    $f008   = '      n||||    xxu||nn  ||||||   |     |';
}
sub ST { # Standardi
    KI()
}
sub TK { # Tuotekansio
    KN()
}
sub TU { # Tutkimus
    OP()
}
sub VI { # Video (VHS)
    $leader = '     ngm a22     zu 4500';
    $f007   = 'vf |ba|||';
    $f008   = '||||||n||||    xxd|||||||||| ||||v|   ||';
}
sub VA { # Valokuva
    $leader = '     nkm#a22     zu#4500';
    $f007   = 'k|#||#';
    $f008   = '      n        fi ||| |     ||   |||||||';
}

sub forceControlFields {
    my ($s, $o, $b) = @_;
    my ($r, $itemType) = ($s->{record}, $s->{record}->getUnrepeatableSubfield('942', 'c')->content());

    ($leader, $f007, $f008, $componentPart) = (undef, undef, undef, 'a');

    if (my $mother_id = $r->isComponentPart()) {
        my $mother = $b->{Titles}->get($mother_id);
        if ($mother) {
          $itemType = $MMT::TranslationTable::ItemTypes::PL_defaultTitleTypes{$mother->[0]->{TitleType}};
        }
    }

    if    ($itemType eq 'KI') { KI() } # PrettyLib 0 => KI
    elsif ($itemType eq 'NU') { NU() } # PrettyLib 2 => NU
    elsif ($itemType eq 'KA') { KA() } # PrettyLib 3 => KA
    elsif ($itemType eq 'ES') { ES() } # PrettyLib 8 => ES
    elsif ($itemType eq 'DV') { DV() } # PrettyLib ? => DV
    else {
        eval {
            no strict 'refs';
            my $sub = __PACKAGE__->can($itemType);
            if ($sub) {
                $sub->();
            }
            else {
                # probably translation tables change the default itype mappings to something completely new. So reconcile here.
                my $standardItemtype = $MMT::TranslationTable::ItemTypes::PL_defaultTitleTypes{$o->{TitleType}};
                $sub = __PACKAGE__->can($standardItemtype);
                if ($sub) {
                    $sub->();
                } else {
                    $log->warn($s->logId()." Unknown itemtype '$standardItemtype' to force control fields and leader. Defaulting to KI");
                    KI();
                }
            }

        };
        if ($@ && ($@ =~ /Undefined subroutine/)) {
            $log->warn($s->logId()." Unknown itemtype '$itemType' to force control fields and leader. Defaulting to KI");
            KI();
        }
        elsif($@) {
            die $@;
        }
    }

    # Set the publication date to 008
    my $pd = $r->publicationDate();
    substr($f008,7,4) = substr($pd,0,4) if ($pd);

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

