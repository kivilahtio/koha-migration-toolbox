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
use File::stat;
use Getopt::Long qw(:config no_ignore_case bundling);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

my $opExtract;
my $opIntrospect;
my $opShip;
my $help;
my $v;
my $sql;
my $configPath = 'config.perl';
my $workingDir;

sub print_usage {
  (my $basename = $0) =~ s|.*/||;
  print <<HELP;
NAME $basename

DESCRIPTION

  Export everything exportable in the given DB as .csv-files named by the table
  names.

USAGE

  Configuration

    By default the export configuration is in file

      config.perl

    next to this export script.

    Make sure to carefully configure all fields and maintain the proper syntax. Do not remove ending commas etc.
    The config.perl-file needs to be valid Perl to be usable.

  Shipping files

    To scp (Secure copy remotely) the extracted table files to a remote server,
    you must manually install the PSCP-program from
    https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html
    By default the PSCP-program must reside in the same directory as this script.

  Running the extractor

    Then

      perl extract.pl --help

ARGUMENTS

  -e, --extract           Exports all DB tables as is based on the config.perl -file.
  -i, --introspect        Introspect all the known data sources from ODBC.
  -s, --ship              Send the database dumps to the configured ssh-server.
  -h, --help              Show this help
  -v, --verbose           Show debug information
  -q, --sql               Execute the given SQL and save it to extract.csv
  -c, --config            Path to the configuration file, defaults to config.perl
  -w, --workingDir        Set the given absolute path as the working directory for this process scope.
                          Useful to make sure the configured dynamic paths are detected in the proper context.

HELP
}

GetOptions(
    'e|extract'      => \$opExtract,
    's|ship'         => \$opShip,
    'i|introspect'   => \$opIntrospect,
    'h|help'         => \$help,
    'v|verbose'      => \$v,
    'q|sql:s'        => \$sql,
    'c|config:s'     => \$configPath,
    'w|workingDir:s' => \$workingDir,
) or print_usage, exit 1;

if ($help) {
    print_usage;
    exit;
}


my $nl = ($^O =~ /linux/i) ? "\n" : "\r\n";

chdir($workingDir) if $workingDir;
print "Changed the working dir to '$workingDir'.$nl" if $workingDir and $v;

my $config = configure($configPath);
print "Using configuration:$nl".Data::Dumper::Dumper($config)."$nl" if $v;

my $dbh = DBI->connect("dbi:ODBC:DSN=".$config->{db_dsn}, $config->{db_username}, $config->{db_password}) || confess $@;
if ($dbh->{odbc_has_unicode}) {
  print "ODBC has unicode enabled$nl";
}
#$dbh->{odbc_utf8_on} = 0;
$dbh->{odbc_default_bind_type} = SQL_VARCHAR;
$dbh->{LongReadLen} = 8000;


sub configure {
  my ($configPath) = @_;

  $configPath = './'.$configPath;# unless ($configPath =~ /^[\/]/ or $configPath =~ /^\./);
  my $config = do $configPath || confess("Unable to read the configuration file '".$configPath."': ".($@ || $!));
  return $config;
}

sub hasPSCP {
  my ($config) = @_;

  my $stats = File::stat::stat($config->{pscp_filepath}) or confess("Unable to find the PSCP-program from the configured path '".$config->{pscp_filepath}."'");
  confess("PSCP-program from the configured path '".$config->{pscp_filepath}."' with size '".$stats->size."' looks too small?") unless ($stats->size);
}

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
  print $FH join(",", @columnNames)."\n"; #Make the .csv header

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
        $row->[$i] =~ s/(\n|\r)/\\$1/gsm;
        $row->[$i] =~ s/"/""/gsm;
        $row->[$i] = '"'.$row->[$i].'"'
      }
	  if ($config->{db_reverse_decoding}) {
	    # Some rows have columns that are UTF-8 flagged if they contain Unicode.
		# The encoding is naturally detected on the ass way up and this inconsistent
		# flagging of Strings as UTF-8 causes issues with Perl trying to recover it using it's heuristics.
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
    print $FH join(",", @$row)."\n";
  }
}

sub ship {
  my ($config) = @_;

  my $cmd = $config->{pscp_filepath}.' -pw "'.$config->{ssh_pass}.'" -r '.$config->{export_path}.'/* '.$config->{ssh_user}.'@'.$config->{ssh_host}.':'.$config->{ssh_shipping_dir}.'/';
  print "Executing shipping command:$nl  $cmd$nl" if $v;
  qx($cmd);
}

hasPSCP($config) if $config->{pscp_filepath} or $opShip;
introspectTables($dbh, $config) if $opIntrospect or $opExtract;
exportSql($dbh, $config, $sql) if $sql;
ship($config) if $opShip;

