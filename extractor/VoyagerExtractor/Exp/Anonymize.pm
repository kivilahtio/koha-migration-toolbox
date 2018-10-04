# This file is part of koha-migration-toolbox
#
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with koha-migration-toolbox; if not, see <http://www.gnu.org/licenses>.
#

package Exp::Anonymize;

#Pragmas
use warnings;
use strict;
use utf8;

#External modules
use Carp;
use POSIX;

=head2 NAME

Exp::Anonymize

=head2 DESCRIPTION

Anonymization subroutines. Dispatched via anonymize() using the given anonymization rules.

P.S. There are probably 1 000 000 other anonymization modules out there, but since
nvolk from NatLibFi already implemented these, I might just as well repackage them.

=cut

=head2 anonymize

Dispatch the anonymization subroutines for anonymizable data per the anonymization rules.

=cut

sub anonymize($$$) {
  my ($cols, $anonRules, $columnToIndexLookup) = @_;
  return unless ($anonRules);

  for my $anonymizableColumnName (keys %$anonRules) {
    my $i = $columnToIndexLookup->{$anonymizableColumnName};
    next unless $cols->[$i];

    my $anonOperation = $anonRules->{$anonymizableColumnName};
    my $anonSub = __PACKAGE__->can('__'.$anonOperation);
    unless ($anonSub) {
      warn "No such anonymization subroutine '__$anonOperation' for anonymization operation '$anonOperation'";
      next;
    }

    $cols->[$i] = $anonSub->($cols->[$i]);
  }
}

=head3 _anonymize_scramble

Turns each character into something else within the same character class.

=cut

sub __scramble($) {
  my $newText = '';
  while ( $_[0] ) {
    if ( $_[0] =~ s/^\d// ) {
      $newText .= int(rand(10));
    }
    elsif ( $_[0] =~ s/^(\s+|[;.\-,:])// ) {
      $newText .= $1;
    }
    elsif ( $_[0] =~ s/^\p{Ll}// ) {
      $newText .= chr(97+int(rand(25)));
    }
    elsif ( $_[0] =~ s/^\p{Lu}// ) {
      $newText .= chr(65+int(rand(25)));
    }
    elsif ( $_[0] =~ s/^(.)// ) {
      $newText .= $1;
    }
    if ( $newText eq $_[0] ) {
      $_[0] = 'ABORT';
    }
  }
  return $newText;
}
sub __surname($) {
  return 'Meikäläinen';
}
sub __firstName($) {
  return 'Tuisku';
}
sub __ssn($) {
  if (my $ssn = createSsnIfSsn($_[0])) {
    $_[0] = $ssn;
  }
  else {
    $_[0] =~ s/\d/1/gsm;
  }

  return $_[0];
}
sub __date($) {
  $_[0] =~ s/\d/1/gsm;
  return $_[0];
}
sub __phone($) {
  my $newPhone = '';
  if ( $_[0] =~ s/^(\+?\d{3})// ) {
    $newPhone = $1;
  }
  while ( $_[0] ) {
    if ( $_[0] =~ s/^\d// ) {
      $newPhone .= int(rand(10));
    }
    elsif ( $_[0] =~ s/^(.)// ) {
      $newPhone .= $1;
    }
  }
  return $newPhone;
}

sub checkIsValidFinnishSSN {
  my ($value) = @_;
  return undef unless ($value =~ /^(\d\d)(\d\d)(\d\d)([+-A])(\d{3})([A-Z0-9])$/);
  return undef unless (1 <= $1 && $1 <= 31);
  return undef unless (1 <= $2 && $2 <= 12); # This is not DateTime but this is fast and good enough.
  return undef unless (0 <= $3 && $3 <= 99);
  return undef unless $6 eq _getSsnChecksum($1, $2, $3, $5);
  return ($1, $2, $3, $4, $5, $6);
}
# This is needed to to make the anonymized ssns pass validators and not throw so much warnings later on in the toolchain.
sub createSsnIfSsn {
  my ($d, $m, $y, $p4, $p5, $chk) = checkIsValidFinnishSSN($_[0]);
  if ($d) { #Is valid ssn, so anonymize it by randomizing it but still making sure it is valid
    $d =  sprintf("%02d", POSIX::floor(rand(30)+1.5));
    $m =  sprintf("%02d", POSIX::floor(rand(11)+1.5));
    $y =  sprintf("%02d", POSIX::floor(rand(98)+1.5));
    $p5 = sprintf("%03d", POSIX::floor(rand(889)+1.5));
    my $chk = _getSsnChecksum($d, $m, $y, $p5);
    return $d.$m.$y.$p4.$p5.$chk;
  }
  return undef;
}
# From Hetula
my @ssnValidCheckKeys = (0..9,qw(A B C D E F H J K L M N P R S T U V W X Y));
sub _getSsnChecksum {
  my ($day, $month, $year, $checkNumber) = @_;

  my $checkNumberSum = sprintf("%02d%02d%02d%03d", $day, $month, $year, $checkNumber);
  my $checkNumberIndex = $checkNumberSum % 31;
  return $ssnValidCheckKeys[$checkNumberIndex];
}


return 1;
