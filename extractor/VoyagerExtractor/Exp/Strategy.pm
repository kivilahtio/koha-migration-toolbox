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

package Exp::Strategy;

#Pragmas
use warnings;
use strict;

#External modules
use Carp;

#Local modules

=head2 NAME

Exp::Strategy - Package for different export/extract approaches

=head2 DESCRIPTION

This package encapsulates several different approaches/strategies to export data from Voyager.
It is a natural by-product of experimenting with different database access and analysis vectors and
brings together various extract scripts we have been using in the past.

See the Transform-phase script migrate.pl for what the current intended extract-flow is.

=cut

return 1;
