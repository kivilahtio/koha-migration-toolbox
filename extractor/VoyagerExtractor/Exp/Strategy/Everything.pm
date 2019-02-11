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

package Exp::Strategy::Everything;

#Pragmas
use warnings;
use strict;

#External modules
use Carp;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

=head2 NAME

Exp::Strategy::Everything

=head2 DESCRIPTION

Export everything exportable in the given DB

=cut

use Exp::DB;
use Exp::Config;

sub printAllTableMetadata {
  my $dbh = Exp::DB::dbh();
  my $sth = $dbh->column_info( '%', $Exp::DB::config->{schema}, '%', '%' ) || confess $dbh->errstr;
  my $t = $sth->fetchall_arrayref({}) || confess $dbh->errstr;

  for my $c (@$t) {
    print sprintf("%30s %30s %10s %10s\n", $c->{TABLE_NAME}, $c->{COLUMN_NAME}, $c->{TYPE_NAME}, $c->{COLUMN_SIZE});
  }
}

=head2 exportAllTables

Exports all tables as .csv-files to
(config.pl -> exportDir) . $tableName . (.csv)

 @param {ARRAYRef} List of table names to skip.

=cut

sub exportAllTables($) {
  my ($excludedTables) = @_;
  my $dbh = Exp::DB::dbh();
  my $sth = $dbh->table_info( '%', $Exp::DB::config->{schema}, '%', 'TABLE' ) || confess $dbh->errstr;
  my $tables = $sth->fetchall_arrayref({}) || confess $dbh->errstr;

  for my $tableInfo (@$tables) {
    if ($excludedTables && $tableInfo->{TABLE_NAME} =~ m!$excludedTables!i) { #Ignore case here because the Orcale table names are sporadically UC and lc in different contexts.
      warn "Skipping table '".$tableInfo->{TABLE_NAME}."' because it matches one of the given excluded tables '$excludedTables'";
      next;
    }
    eval {
      exportTable($tableInfo);
    };
    warn $@ if ($@);
  }

  print "Done exporting everything. Thank you for your patience!\n";
}

sub exportTable($) {
  my ($tableInfo) = @_;
  my $dbh = Exp::DB::dbh();

  my $tableName = $tableInfo->{TABLE_NAME};
  if ($tableName =~ /\$/) {
    warn "Table '$tableName' looks suspicious, skipping it.";
    next;
  }

  open(my $FH, ">:raw", Exp::Config::exportPath($tableName.'.csv')) or die("Opening file '".Exp::Config::exportPath($tableName.'.csv')."' for full export failed: $!");
  warn "Exporting table $tableName\n";
  my $sth = $dbh->column_info( '%', $Exp::DB::config->{schema}, $tableName, '%' ) || confess $dbh->errstr;
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

return 1;
