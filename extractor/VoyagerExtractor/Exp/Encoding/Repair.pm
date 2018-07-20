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

package Exp::Encoding::Repair;

#Pragmas
use warnings;
use strict;

#External modules
use Carp;

=head2 NAME

Exp::Encoding::Repair - Repair specific encoding issues in the source data

=head2 DESCRIPTION

=cut

use Exp::Config;

sub repair($$$) {
  my ($tableOrFilename, $cols, $columnToIndexLookup) = @_;
  my $repairs = Exp::Config::getTableRepairs($tableOrFilename);
  return unless $repairs;

  for my $repair (@$repairs) {
    my $repairableColumnName = $repair->[0];
    my $i = $columnToIndexLookup->{$repairableColumnName};
    next unless $cols->[$i];

    my $unicodeFrom = $repair->[1];
    my $unicodeTo = $repair->[2];
    if ($cols->[$i] =~ s/$unicodeFrom/$unicodeTo/gu) {
      print "Unicode fix at '$tableOrFilename->$repairableColumnName'. From '$unicodeFrom' to '$unicodeTo'\n" if $ENV{DEBUG};
    }
  }
}

return 1;
