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
  $_[0] =~ s/\d/1/gsm;
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

return 1;
