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

#Pragmas
use utf8;
use warnings;
use strict;
use open qw(:std :encoding(UTF-8));

#External modules
use Encode;
use Carp;
use DBI qw(:sql_types);
use DBD::ODBC;
use Getopt::Long qw(:config no_ignore_case bundling);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

=head2 NAME

extract.pl

=head2 DESCRIPTION

Export everything exportable in the given DB

=head2 USAGE

Put all the export configuration to file

    config.perl

next to this export script.
Then

    perl extract.pl --help

=cut

my $opExtract;
my $opIntrospect;
my $help;
my $v;
my $sql;

sub print_usage {
  (my $basename = $0) =~ s|.*/||;
  print <<USAGE;
$basename
  Exports all data from PrettyLib/Circ

Usage:
  -e, --extract           Exports all DB tables as is based on the config.perl -file.
  -i, --introspect        Introspect all the known data sources from ODBC.
  -h, --help              Show this help
  -v, --verbose           Show debug information
  -s, --sql               Execute the given SQL and save it to extract.csv

USAGE
}

GetOptions(
    'e|extract'     => \$opExtract,
    'i|introspect'  => \$opIntrospect,
    'h|help'        => \$help,
    'v|verbose'     => \$v,
    's|sql:s'       => \$sql,
) or print_usage, exit 1;

if ($help) {
    print_usage;
    exit;
}


my $nl = ($^O =~ /linux/i) ? "\n" : "\r\n";
my $config = do './config.perl' || confess("Unable to read the configuration file: ".($@ || $!));
my $dbh = DBI->connect("dbi:ODBC:DSN=".$config->{db_dsn}, $config->{db_username}, $config->{db_password}) || confess $@;
if ($dbh->{odbc_has_unicode}) {
  print "ODBC has unicode enabled$nl";
}
#$dbh->{odbc_utf8_on} = 0;
$dbh->{odbc_default_bind_type} = SQL_VARCHAR;
$dbh->{LongReadLen} = 8000;


sub introspectTables {
  my ($dbh, $config) = @_;

  my $sth = $dbh->table_info( $config->{db_catalog}||'%', $config->{db_schema}||'%', $config->{db_table}||'%', 'TABLE' ) || confess $dbh->errstr;
  my $tables = $sth->fetchall_arrayref({}) || confess $dbh->errstr;

  my $map = {};
  $map->{ $_->{'TABLE_CAT'} }->{ $_->{'TABLE_SCHEM'} }->{ $_->{TABLE_NAME} } = $_ for @$tables;

  for my $catalogName (sort keys %$map) {
    print "-Catalog: '$catalogName'$nl" if $v;
    my $schemas = $map->{$catalogName};
    for my $schemaName (sort keys %$schemas) {
      print "--Schema: '$schemaName'$nl" if $v;
      my $tables = $schemas->{$schemaName};
      for my $tableName (sort keys %$tables) {
        print "---Table: '$tableName'$nl" if $v;
        my $table = $tables->{$tableName};
        print "---Catalog: $catalogName, Schema: $schemaName, Table: $tableName, Type: ".$table->{TABLE_TYPE}."$nl" if $v;
        introspectColumns($dbh, $config, $table);

        printTableMetadata($dbh, $config, $table) if $v or $opIntrospect;
        exportTable($dbh, $config, $table) if $opExtract;
      }
    }
  }
}

sub introspectColumns {
  my ($dbh, $config, $table) = @_;

  my $sth = $dbh->column_info( $table->{TABLE_CAT}, $table->{TABLE_SCHEM}, $table->{TABLE_NAME}, '%' ) || confess $dbh->errstr;
  my $columns = $sth->fetchall_arrayref({}) || confess $dbh->errstr;

  my $map = {};
  $map->{ $_->{COLUMN_NAME} } = $_ for @$columns;

  $table->{COLUMNS} = $map;
}

sub printTableMetadata {
  my ($dbh, $config, $table) = @_;

  for my $columnName (sort keys %{$table->{COLUMNS}}) {
    my $c = $table->{COLUMNS}->{$columnName};
    print sprintf("%30s %30s %10s %10s$nl", $table->{TABLE_NAME}, $c->{COLUMN_NAME}, $c->{TYPE_NAME}, $c->{COLUMN_SIZE});
  }
}

sub exportTable {
  my ($dbh, $config, $table) = @_;

  my $encoding = "encoding(UTF-8)";

  my $filePath = join('/', $config->{export_path}, $table->{TABLE_NAME}.'.csv');
  open(my $FH, ">:$encoding", $filePath) or die("Opening file '".$filePath."' for full export failed: $!");
  print "-Exporting table '".$table->{TABLE_NAME}."'$nl" if $v;

  my $sth = $dbh->column_info( $config->{db_catalog}, $config->{db_schema}, $table->{TABLE_NAME}, '%' ) || confess $dbh->errstr;
  my $columnInfos = $sth->fetchall_arrayref({}) || confess $dbh->errstr;
  my @columnNames = map {$_->{COLUMN_NAME}} @$columnInfos;
  print "-Found columns ".join(",", @columnNames)."$nl" if $v;
  print $FH join(",", @columnNames)."$nl"; #Make the .csv header

  my $rows = _executeSql($dbh, $config, "SELECT * FROM ".$table->{TABLE_NAME});

  _writeSql($dbh, $config, $FH, $rows);

  close $FH;
}

sub exportSql {
  my ($dbh, $config, $sql) = @_;

  my $rows = _executeSql($dbh, $config, $sql);
  my $filePath = 'extract.csv';
  open(my $FH, '>:raw', $filePath) or die("Extracting SQL to '".$filePath."' failed: $!");
  _writeSql($dbh, $config, $FH, $rows);
  close($FH);
}

sub _executeSql {
  my ($dbh, $config, $sql) = @_;

  my $sth = $dbh->prepare($sql) || confess $dbh->errstr;
  $sth->execute() || confess $dbh->errstr;
  return $sth->fetchall_arrayref() || confess $dbh->errstr;
}

sub _writeSql {
  my ($dbh, $config, $FH, $rows) = @_;

  for my $row (@$rows) {
    for (my $i=0 ; $i<@$row; $i++) {
      if (not defined $row->[$i]) {
        $row->[$i] = '';
      }
      else {
        $row->[$i] =~ s/("|\n|\r)/\\$1/gsm;
        $row->[$i] = '"'.$row->[$i].'"'
      }
	  if ($config->{db_reverse_decoding}) {
	    # Some columns have rows that are UTF-8 flagged if they contain Unicode.
		# The encoding is naturally detected on the ass way up.
		# Revert the damages.
		# Make sure all strings have the utf8-flag off so Perl does some magic mumbo jumbo and spits out the diacritics correctly.
        if (Encode::is_utf8($row->[$i])) {
          #print $row->[$i]." is UTF8\nl";
		  $row->[$i] = Encode::encode("UTF-8", $row->[$i]);
		  Encode::_utf8_off($row->[$i]);
        }
        else {
          #print $row->[$i]." NOT UTF8\nl";
        }
      }
	}
    print $FH join(",", @$row)."$nl";
  }
}

introspectTables($dbh, $config) if $opIntrospect or $opExtract;
exportSql($dbh, $config, $sql) if $sql;

