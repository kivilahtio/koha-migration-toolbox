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


# E-Kirja
sub EK {
	$leader = '     nam a22     4i 4500';
	$f007   = 'cr |||||||||||';
	$f008   = '      s           |||| o    |||| ||   |c';
}
# Kausijulkaisu/Sarjajulkaisu
sub KA {
    $leader = '     nam a22     5i 4500';
    $f008   = '191104b        xxu||||| |||| 00| 0 fin d';
	$componentPart = 's';
}

# Äänikirja
sub AU {
	$leader = '     nim a22     4i 4500';
	$f007   = 'sd f||g|||m|||';
	$f008   = '||||||s||||    fi ||||| ||||||f  | fin|c';
}

# Äänite
sub SR {
    $leader = '     njm a22     4i 4500';
    $f007   = 'sd f||g|||m|||';
    $f008   = '      s||||    xxu||nn  ||||||   | fin c';
}

# Kartta
sub KR {
	$leader = '     nem a22     4i 4500';
	$f007   = 'a| ca|||';
	$f008   = '      s           ||||| |||| 00|       c';
}

# Kirja
sub KI {
    $leader = '     nam a22     4i 4500';
    $f008   = '||||||s||||    fi |||||||||| ||||f|fin|c';
}

# Lautapeli
sub LA {
	$leader = '     nrm a22     4i 4500';
	$f007   = 'zu';
	$f008   = '      s        fi ||| |      |   g|fin|c';
}

# Esine
sub ES {
    $leader = '     nam a22     7a 4500';
    $f008   = '191104b        xxu||||| |||| 00| 0 fin d';
}

# Moniviestin
sub MO {
	$leader = '     nom';
	$f007   = 'ou';
	$f008   = '||||||s||||    fi |||       |    b||||||';
}

# Nuotti
sub NU {
    $leader = '     ncm a22     4i 4500';
    $f007   = 'qu';
    $f008   = '||||||s||||    fi |||||||||||||||||||||c';
};

# DVD, videotallenne
sub DV {
    $leader = '     ngm a22     4i 4500';
    $f007   = 'vd cvaiz|';
    $f008   = '      s        fi |||       |    v|fin|c';
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

