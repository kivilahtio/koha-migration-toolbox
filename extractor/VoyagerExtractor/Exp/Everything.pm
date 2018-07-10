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

package MMT::Everything;

#Pragmas
use warnings;
use strict;

#External modules
use Carp;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

=head2 NAME

Exp::Everything

=head2 DESCRIPTION

Export everything exportable in the given DB

=cut

use Exp::DB;

sub printAllTableMetadata {
  my $dbh = Exp::DB::dbh();
  my $sth = $dbh->column_info( '%', $Exp::DB::config->{dbname}, '%', '%' ) || confess $dbh->errstr;
  my $t = $sth->fetchall_arrayref({}) || confess $dbh->errstr;

  for my $c (@$t) {
    print sprintf("%30s %30s %10s %10s\n", $c->{TABLE_NAME}, $c->{COLUMN_NAME}, $c->{TYPE_NAME}, $c->{COLUMN_SIZE});
  }
}

=head2 exportAllTables

Exports all tables as .csv-files to /tmp/$dbName.$tableName.csv

=cut

sub exportAllTables {
  my $dbh = Exp::DB::dbh();
  my $sth = $dbh->table_info( '%', $Exp::DB::config->{dbname}, '%', 'TABLE' ) || confess $dbh->errstr;
  my $tables = $sth->fetchall_arrayref({}) || confess $dbh->errstr;

  for my $tableInfo (@$tables) {
    my $tableName = $tableInfo->{TABLE_NAME};
    open(my $FH, ">:raw", '/tmp/'.$Exp::DB::config->{dbname}.'.'.$tableName.'.csv');
    warn "Exporting table $tableName\n";
    $sth = $dbh->column_info( '%', 'HAMEDB', $tableName, '%' ) || confess $dbh->errstr;
    my $columnInfos = $sth->fetchall_arrayref({}) || confess $dbh->errstr;
    my @columnNames = map {$_->{COLUMN_NAME}} @$columnInfos;
    warn "found columns ".join(",", @columnNames)."\n";

    print $FH join(",", @columnNames)."\n";
    $sth = $dbh->prepare("SELECT * FROM $tableName") || confess $dbh->errstr;
    $sth->execute() || confess $dbh->errstr;
    my $rows = $sth->fetchall_arrayref() || confess $dbh->errstr;
    for my $row (@$rows) {
      for (my $i=0 ; $i<@$row; $i++) {
        if (not defined $row->[$i]) {
          $row->[$i] = '';
        }
        else {
          $row->[$i] =~ s/("|\n|\r)/\\$1/gsm;
          $row->[$i] = '"'.$row->[$i].'"'
        }
      }
      print $FH join(",", @$row)."\n";
    }
    close $FH;
  }
}

return 1;
