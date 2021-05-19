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
use warnings;
use strict;

#External modules
use Encode;
use Carp;
use DBI qw(:sql_types);
use DBD::ODBC;
use File::stat;
use Getopt::Long qw(:config no_ignore_case bundling);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use List::Util;

my $opExtract = 0;
my $opIntrospect = 0;
my $opShip = 0;
my $help = 0;
my $v = 0;
my $sql;
my $configPath = './config.perl';
my $workingDir;
my $logFile = 'extract.log';

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

  Scheduling via Windows Server Task Scheduler

    Trigger the following program

      cmd.exe

    with parameters

      /c perl C:\\Users\\hypernovamies\\extract.pl -v -e -s -w C:\\Users\\hypernovamies -c C:\\Users\\hypernovamies\\config.perl -l C:\\Users\\hypernovamies\\extract.log > C:\\Users\\hypernovamies\\extract.log2 2>&1

    Be aware, that all output is buffered. Logfiles are written only after the process exits.

  Logging

    The Windows Server scheduled tasks runner seems to hide the STDOUT/ERR of a running task.
    To circumvent this, all output is written by default to extract.log

ARGUMENTS

  -e, --extract           Exports all DB tables as is based on the config.perl -file. Optionally give the table name to export.
  -i, --introspect        Introspect all the known data sources from ODBC.
  -s, --ship              Send the database dumps to the configured ssh-server.
  -h, --help              Show this help
  -v, --verbose           Show debug information
  -q, --sql               Execute the given SQL and save it to extract.csv
  -c, --config            Path to the configuration file, defaults to config.perl
  -w, --workingDir        Set the given absolute path as the working directory for this process scope.
                          Useful to make sure the configured dynamic paths are detected in the proper context.
  -l, --logFile           Where to write the program logs

HELP
}

GetOptions(
    'e|extract:s'    => \$opExtract,
    's|ship'         => \$opShip,
    'i|introspect'   => \$opIntrospect,
    'h|help'         => \$help,
    'v|verbose'      => \$v,
    'q|sql:s'        => \$sql,
    'c|config:s'     => \$configPath,
    'w|workingDir:s' => \$workingDir,
    'l|logFile:s'    => \$logFile,
) or print_usage, exit 1;

if ($help) {
    print_usage;
    exit;
}
$opExtract = '1' if (defined($opExtract) && $opExtract eq '');


my $nl = ($^O =~ /linux/i) ? "\n" : "\r\n";

chdir($workingDir) if $workingDir;
open(my $LOG, '>', $logFile) or die("Unable to open logFile '$logFile' for writing!");
*STDOUT = $LOG;
*STDERR = $LOG;
print "Changed the working dir to '$workingDir'.$nl" if $workingDir and $v;

my $config = configure($configPath);
print "Using configuration:$nl".Data::Dumper::Dumper($config)."$nl" if $v;

my $dbh = DBI->connect("dbi:ODBC:DSN=".$config->{db_dsn}, $config->{db_username}, $config->{db_password}) || confess $@;
if ($dbh->{odbc_has_unicode}) {
  print "ODBC has unicode enabled$nl";
}
#$dbh->{odbc_utf8_on} = 0;
$dbh->{odbc_default_bind_type} = SQL_VARCHAR;
$dbh->{LongReadLen} = 80000;

my $encoding = $config->{export_encoding};
if ($encoding eq 'encoding(UTF-8)') {
  require utf8;
  utf8->import();
}


my @ignoredTables = ('PrettyLibFiles', 'PrettyCircFiles');

sub configure {
  my ($configPath) = @_;

  $configPath = './'.$configPath unless ($configPath =~ /^\w:\\/ or $configPath =~ /^[\/]/ or $configPath =~ /^\./);
  my $config = do "$configPath" || confess("Unable to read the configuration file '".$configPath."': ".($@ || $!));
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
        next if (($opExtract ne '1' && $opExtract ne $tableName) or ($opExtract eq '1' && grep {$_ eq $tableName} @ignoredTables));
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

  my $filePath = join('/', $config->{export_path}, $table->{TABLE_NAME}.'.csv');
  open(my $FH, ">:$encoding", $filePath) or die("Opening file '".$filePath."' for full export failed: $!");
  print "-Exporting table '".$table->{TABLE_NAME}."'$nl" if $v;

  my $sth = $dbh->column_info( $config->{db_catalog}, $config->{db_schema}, $table->{TABLE_NAME}, '%' ) || confess $dbh->errstr;
  my $columnInfos = $sth->fetchall_arrayref({}) || confess $dbh->errstr;
  my @columnNames = map {$_->{COLUMN_NAME}} @$columnInfos;
  print "-Found columns ".join(",", @columnNames)."$nl" if $v;
  print $FH join(",", @columnNames)."\n"; #Make the .csv header

  # Prepare to check the fetched rows against the counts expected
  my ($countOfRows, $maxId);
  eval { # Not all tables have Id-column
    $countOfRows = _executeSql($dbh, $config, "SELECT COUNT(Id) FROM "._absTableName($config, $table->{TABLE_NAME}));
    $countOfRows = $countOfRows->[0]->[0];
    $maxId = _executeSql($dbh, $config, "SELECT TOP 1 Id FROM "._absTableName($config, $table->{TABLE_NAME}).' ORDER BY Id DESC');
    $maxId = $maxId->[0]->[0];
  };
  if ($@) { die($@) unless ($@ =~ /SQL-42S22/); } #/Invalid column name 'Id'/

  my $rows = _executeSql($dbh, $config, "SELECT * FROM "._absTableName($config, $table->{TABLE_NAME}));
  $rows = [] unless $rows;

  if ($countOfRows && scalar(@$rows) != $countOfRows) { # Try to recover if we can.
    print "Fetching table '".$table->{TABLE_NAME}."' failed: Received only '".scalar(@$rows)."$countOfRows'. Trying chunked reading.";
    my ($fromId, $toId);
    ($dbh, $config, $table, $rows, $countOfRows, $maxId, $fromId, $toId) = _exportChunked($dbh, $config, $table, $countOfRows, $maxId, undef, undef);
  }

  if ($table->{TABLE_NAME} =~ /Customer$/i && $config->{bcrypt_customer_passwords}) {
    _bcryptCustomerPasswords($rows, \@columnNames);
  }

  _writeSql($dbh, $config, $FH, $rows);

  close $FH;
}

my $chunkSize = 1000; # How large chunks we fetch initially, until digging down into smaller bits.

sub _exportChunked {
  my ($dbh, $config, $table, $rows, $countOfRows, $maxId, $fromId, $toId) = @_;
  $fromId = 0 if (not(defined($fromId)));
  $toId = _newChunkTarget($countOfRows, $maxId, $fromId, $toId, undef) if (not(defined($toId)));
  print "_exportChunked($dbh, $config, $table, $rows, $countOfRows, $maxId, $fromId, $toId)";

  my $expectedCount = _executeSql($dbh, $config, "SELECT COUNT(Id) FROM "._absTableName($config, $table->{TABLE_NAME})." WHERE Id >= '$fromId' AND Id < '$toId'");
  $expectedCount = $expectedCount->[0]->[0];
  my $newRows = _executeSql($dbh, $config, "SELECT * FROM "._absTableName($config, $table->{TABLE_NAME})." WHERE Id >= '$fromId' AND Id < '$toId'"); # Sorry SQL injection, just don't expose this code!
  $newRows = $newRows->[0]->[0];

  # Succeeded in getting what was expected
  if ($expectedCount == $newRows) {
    return ($dbh, $config, $table, $rows, $countOfRows, $maxId, $fromId, $toId) if ($toId > $maxId && $expectedCount == 0); # Exit the recursion here
    push(@$rows, @$newRows);
    return _exportChunked($dbh, $config, $table, $rows, $countOfRows, $maxId, $toId, undef); # Swith $toId as $fromId to continue looking for new rows.
  }
  else {
    print "Fetching table '".$table->{TABLE_NAME}."' failed: Received only '".scalar(@$newRows)."$expectedCount'. From '$fromId' to '$toId'. Collected '@$rows' rows.";
    $toId = _newChunkTarget($countOfRows, $maxId, $fromId, $toId, 'fail');
    return _exportChunked($dbh, $config, $table, $rows, $countOfRows, $maxId, $fromId, $toId);
  }
}

sub _newChunkTarget {
  my ($countOfRows, $maxId, $fromId, $toId, $failed) = @_;

  my $standardChunkIncrement = int($maxId / ($countOfRows / $chunkSize));
  unless ($failed) {
    return $fromId + $standardChunkIncrement;
  }
  else {
    return $fromId + (($toId - $fromId) / 2); # On each failed recursion, logarithmically dig deeper toward the failing record.
  }
}

sub _absTableName {
  my ($cfg, $tableName) = @_;
  return $cfg->{db_catalog}.'.'.$cfg->{db_schema}.'.'.$tableName;
}

sub exportSql {
  my ($dbh, $config, $sql) = @_;

  my $rows = _executeSql($dbh, $config, $sql);
  my $filePath = 'extract.csv';
  open(my $FH, ">:$encoding", $filePath) or die("Extracting SQL to '".$filePath."' failed: $!");
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

sub _bcryptCustomerPasswords {
  my ($rows, $columnNames) = @_;
  require Crypt::Eksblowfish::Bcrypt;
  my $pin_column_idx = List::Util::first {$columnNames->[$_] =~ /^PIN$/i} 0..@$columnNames;
  if (not(defined($pin_column_idx))) {
    warn("Column 'PIN' not found when encrypting Customer passwords?");
    return;
  }

  for my $r (@$rows) {
    if ($r->[$pin_column_idx]) {
      $r->[$pin_column_idx] = Crypt::Eksblowfish::Bcrypt::bcrypt(
        $r->[$pin_column_idx],
        '$2a'. #NUL appended
        '$0'.($config->{bcrypt_customer_passwords} || '2'). #cost of hashing
        '$'.Crypt::Eksblowfish::Bcrypt::en_base64(substr(rand(99999999)x2, 0, 16)) #salt
      )
    }
    else { # sorry users with password of 0
      $r->[$pin_column_idx] = '!';
    }
  }
}

sub ship {
  my ($config) = @_;

  my $cmd = $config->{pscp_filepath}.' -batch -unsafe -pw "'.$config->{ssh_pass}.'" -r '.$config->{export_path}.'/* '.$config->{ssh_user}.'@'.$config->{ssh_host}.':'.$config->{ssh_shipping_dir}.'/';
  print "Executing shipping command:$nl  $cmd$nl" if $v;
  qx($cmd);
}

hasPSCP($config) if $config->{pscp_filepath} or $opShip;
introspectTables($dbh, $config) if $opIntrospect or $opExtract;
exportSql($dbh, $config, $sql) if $sql;
ship($config) if $opShip;

print "No operation defined, see --help\n" unless $opShip || $opIntrospect || $opExtract || $sql;

