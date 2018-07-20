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

package Exp::Strategy::MARC;

#Pragmas
use warnings;
use strict;

#External modules
use Carp;

#Local modules
use Exp::nvolk_marc21;

=head2 NAME

Exp::Strategy::MARC

=head2 DESCRIPTION

Export Bibliographic, Authorities and MFHD MARC records as raw ISO

=cut

use Exp::Config;
use Exp::DB;
use Exp::Util;

sub exportBiblios($) {
  _exportMARC(Exp::Config::exportPath('biblios.xml'),
              'select * from BIB_DATA order by BIB_ID, SEQNUM');
}

sub exportAuth() {
  _exportMARC(Exp::Config::exportPath('authorities.xml'),
              'select * from AUTH_DATA order by AUTH_ID, SEQNUM');
}

sub exportMFHD() {
  _exportMARC(Exp::Config::exportPath('mfhd.xml'),
              'select * from MFHD_DATA order by MFHD_ID, SEQNUM');
}

=head2 _exportMARC

Implements the export logic.
Can be hooked with a subroutine to do transformations before writing to disk.

 @param1 String, filepath where to write the data
 @param2 String, SQL statement to extract data with
 @param3 Subroutine, OPTIONAL, Executed after the MARC as ISO has been concatenated. Is used to write the data to disk.

=cut

sub _exportMARC($$$) {
  my ($outFilePath, $sql, $outputHook) = @_;

  open(my $FH, '>:raw', $outFilePath) or confess("Opening file '$outFilePath' failed: ".$!);

  my $dbh = Exp::DB::dbh();
  my $sth = $dbh->prepare($sql) || confess($dbh->errstr);
  $sth->execute() || confess($dbh->errstr);


  my @row;
  my $record = '';
  my $prev_id = 0;
  while ( ((@row) = $sth->fetchrow_array) ) {
    if ( $row[1] == 1 ) {
      ($outputHook) ? $outputHook->($FH, $prev_id, \$record) : _output_record($FH, $prev_id, \$record);
      $record = $row[2];
    }
    else {
      $record .= $row[2];
    }
    $prev_id = $row[0];
  }
  $sth->finish();
  ($outputHook) ? $outputHook->($FH, $prev_id, \$record) : _output_record($FH, $prev_id, \$record);
  close($FH);
}

sub _output_record($$$) {
  my ( $FH, $id, $record_ptr ) = @_;

  if ( length($$record_ptr) ) {
    if ( !Exp::Util::isUtf8($$record_ptr) ) {
      print STDERR "$id\tWarning\tRecord contains non-UTF-8 characters\n";
      $$record_ptr = Exp::Util::toUtf8($$record_ptr);
    }
    $$record_ptr = Exp::nvolk_marc21::nvolk_marc212oai_marc($$record_ptr);
    print $FH $$record_ptr, "\n";
  }
}

return 1;
