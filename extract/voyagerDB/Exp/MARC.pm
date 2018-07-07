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

package Exp::MARC;

#Pragmas
use warnings;
use strict;

#External modules
use Carp;

=head2 NAME

Exp::MARC

=head2 DESCRIPTION

Export Bibliographic, Authorities and MFHD MARC records as raw ISO

=cut

use Exp::Config;
use Exp::DB;
use Exp::Util;

sub exportBiblios($) {
  _processRow(Exp::Config::exportPath('biblios.mrc'),
              'select * from BIB_DATA order by BIB_ID, SEQNUM');
}

sub exportAuth() {
  _processRow(Exp::Config::exportPath('authorities.mrc'),
              'select * from AUTH_DATA order by AUTH_ID, SEQNUM');
}

sub exportMFHD() {
  _processRow(Exp::Config::exportPath('mfhd.mrc'),
              'select * from MFHD_DATA order by MFHD_ID, SEQNUM');
}


sub _processRow($$) {
  my ($outFilePath, $sql) = @_;

  open(my $FH, '>:raw', $outFilePath) or confess("Opening file '$outFilePath' failed: ".$!);

  my $dbh = Exp::DB::dbh();
  my $sth = $dbh->prepare($sql) || confess($dbh->errstr);
  $sth->execute() || confess($dbh->errstr);


  my @row;
  my $record = '';
  my $prev_id = 0;
  while ( ((@row) = $sth->fetchrow_array) ) {
    if ( $row[1] == 1 ) {
      _output_record($FH, $prev_id, $record);
      $record = $row[2];
    }
    else {
      $record .= $row[2];
    }
    $prev_id = $row[0];
  }
  $sth->finish();
  _output_record($FH, $prev_id, $record);
  close($FH);
}

sub _output_record($$$) {
  my ( $FH, $id, $record ) = @_;
  if ( length($record) ) {
    if ( !Exp::Util::isUtf8($record) ) {
      print STDERR "$id\tWarning\tRecord contains non-UTF-8 characters\n";
      $record = Exp::Util::toUtf8($record);
    }
    print $FH $record, "\n";
  }
}

return 1;
