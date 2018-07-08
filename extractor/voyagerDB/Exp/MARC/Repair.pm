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

package Exp::MARC::Repair;

#Pragmas
use warnings;
use strict;

#External modules
use Carp;

=head2 NAME

Exp::MARC::Repair

=head2 DESCRIPTION

While exporting bibs, do some repairs which would be really hard to do with .csv-files.
Do only things which require looking at other values in the Voyager DB here.

Usermarcon in the transformation phase does a much faster job.
Also do not shred biblio transformation logic to multiple submodules, but keep the change sources contained.

=cut

use Exp::Config;
use Exp::DB;
use Exp::Util;



return 1;
