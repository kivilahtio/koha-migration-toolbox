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

package Exp::Strategy::Precision;

#Pragmas
use warnings;
use strict;
use utf8; #This file and all Strings within are utf8-encoded
binmode( STDOUT, ":encoding(UTF-8)" );
binmode( STDIN,  ":encoding(UTF-8)" );
$|=1;

#External modules
use Carp;
use DBI;

#Local modules
use Exp::nvolk_marc21;
use Exp::Config;
use Exp::DB;
use Exp::Encoding;
use Exp::Encoding::Repair;
use Exp::Anonymize;

=head2 NAME

Exp::Strategy::Precision - Precisely export what is needed. (Except MARC)

=head2 DESCRIPTION

Export all kinds of data from Voyager using the given precision SQL.

=cut

my $anonymize = (defined $ENV{ANONYMIZE} && $ENV{ANONYMIZE} == 0) ? 0 : 1; #Default to anonymize confidential and personally identifiable information
warn "Not anonymizing!\n" unless $anonymize;

sub extractSerialsMFHD($) {
  my ($filename) = @_;
  require Exp::nvolk_marc21;
  require Exp::Strategy::MARC;
  my $csvHeadersPrinted = 0;

  #Turn MFHD's into MARCXML, and then use a transformation hook to turn it into .csv instead!! Brilliant! What could go wrong...
  Exp::Strategy::MARC::_exportMARC(
    Exp::Config::exportPath($filename),
    "SELECT    mfhd_data.mfhd_id, mfhd_data.seqnum, mfhd_data.record_segment
     FROM      mfhd_data
     LEFT JOIN serials_vw ON (mfhd_data.mfhd_id = serials_vw.mfhd_id)
     WHERE     serials_vw.mfhd_id IS NOT NULL
     GROUP BY  mfhd_data.mfhd_id, mfhd_data.seqnum, mfhd_data.record_segment",
    sub { #Logic from https://github.com/GeekRuthie/koha-migration-toolbox/blob/master/migration/Voyager/serials_subscriptions_loader.pl#L122
      my ($FH, $id, $record_ptr) = @_;

      if ( $$record_ptr eq '' ) { return; }

      my $mfhd_id = '0';
      my $location = '0';
      my $holdings = ''; #Concatenate all individual holdings here for subscription histories
      eval {
        $mfhd_id  = Exp::nvolk_marc21::marc21_record_get_field($$record_ptr, '001', undef);
        $location = Exp::nvolk_marc21::marc21_record_get_field($$record_ptr, '852', 'b');

        my @holdingsFields = Exp::nvolk_marc21::marc21_record_get_fields($$record_ptr, '863', undef);
        my @holdings = map {Exp::nvolk_marc21::marc21_field_get_subfield($_, 'a')} @holdingsFields;
        $holdings = join(' ', @holdings);
      };
      warn $@ if ($@);

      $mfhd_id = '0' unless $mfhd_id;
      $location = '0' unless $location;
      $holdings = '' unless $holdings;
      unless ($csvHeadersPrinted) {
        $csvHeadersPrinted++;
        $$record_ptr = "mfhd_id,location,holdings\n".
                        "$mfhd_id,$location,\"$holdings\"";
      }
      else {
        $$record_ptr = "$mfhd_id,$location,\"$holdings\"";
      }
      print $FH $$record_ptr, "\n";
    }
  );
}

=head2 getColumnEncodings

Voyager has different encodings for each table. When tables are joined in a SELECT-query,
those encodings are not normalized in the DBD::Oracle-layer.
Each column must be decoded from the correct encoding, so they can be dealt with without mangling characters.

 @returns ARRAYRef, encoding for each column based on the table encoding of the joined column

P.S. I managed to install SQL::Statement without root permissions, but let's try to keep the extra module deps as small as possible.

=cut

sub getColumnEncodings($) {
  my ($cols) = @_;
  my @encodings;
  for (my $i=0 ; $i<@$cols ; $i++) {
    if($cols->[$i] =~ /(\w+)\.(\w+)/) {
      $encodings[$i] = Exp::Config::getTableEncoding($1);
    }
    else {
      warn "Couldn't parse the column definition '".$cols->[$i]."' to table and column names. Defaulting to 'iso-8859-1'";
      $encodings[$i] = 'iso-8859-1';
    }
  }
  return \@encodings;
}

sub pickCorrectSubquery($$) {
  my ($statement, $queryName) = @_;

  my @selectStatements = $statement =~ /SELECT\s*(.+?)\s*FROM/gsm;

  my $mainSelectStatement; #There could be multiple subselects, so look for the best match
  my $cols;
  print "Found '".(scalar(@selectStatements)-1)."' subqueries. Finding the best match.\n" if (@selectStatements > 1);
  for my $stmt (@selectStatements) {
    if ($cols = extractQuerySelectColumns($stmt)) {
      $mainSelectStatement = $stmt;
      last;
    }
  }
  unless ($mainSelectStatement && ref($cols) eq 'ARRAY') {
    print "Couldn't parse a SELECT statement for query '$queryName'\n";
  }
  return ($mainSelectStatement, $cols);
}

=head2 extractQuerySelectColumns

 @returns ARRAYRef, The 'table.column' -entries in the SELECT-clause.

=cut

sub extractQuerySelectColumns($) {
  my ($query) = @_;
  my $header_row = $query;
  $header_row =~ s/\s+/\t/g;
  $header_row =~ s/,\t/,/g;
  $header_row =~ tr/A-Z/a-z/;
  $header_row =~ s/\w+\((.+?)\)/$1/;          #Trim column functions such as max()
  $header_row =~ s/\.\w+\s+AS\s+(\w+)/\.$1/gi; #Simplify column aliasing... renew_transactions.renew_date AS last_renew_date -> renew_transactions.last_renew_date
  $header_row =~ s/(\w+)\s+AS\s+(\w+)/$1\.$2/gi; #Simplify column aliasing... null AS last_renew_date -> null.last_renew_date
  return undef if $header_row eq '*';
  my @cols = split(',', $header_row);
  return \@cols;
}

sub createHeaderRow($) {
  my ($cols) = @_;
  my $header_row = join(',', @$cols);
  $header_row =~ s/[a-z_]+\.([a-z])/$1/g; #Trim the table definition prefix
  return $header_row.',DUPLICATE'; #DUPLICATE-column is added to every exported file. This signifies a unique key violation. This way post-analysis from the .csv-files is easier.
}

sub writeCsvRow($$) {
  my ($FH, $line) = @_;
  for my $k (0..scalar(@$line)-1) {
    if (defined($line->[$k])) {
      $line->[$k] =~ s/"/'/gsm;
      $line->[$k] =~ s/[\x00-\x08\x0B-\x1F]//gsm; #Trim "carriage return" and control characters that should no longer be here
      if ($line->[$k] =~ /,|\n/) {
        $line->[$k] = '"'.$line->[$k].'"';
      }
    }
    else {
      $line->[$k] = '';
    }
  }
  print $FH join(",", @$line)."\n";
}

=head2 deduplicateUniqueKey

Catch multiple unique keys here. Make sure the export queries work as expected and the complex joins and groupings
do not cause unintended duplication of source data.

 @param1 Integer, index of the unique key to deduplicate in the given columns.
                  or ARRAYRef of indexes if multiple keys
                  Deduplication is ignored if @param1 < 0
 @param2 ARRAYRef, column names from the extract query select portion
 @param3 ARRAYRef, columns of data from the extract query

=cut

my %uniqueColumnVerifier;
sub deduplicateUniqueKey($$$) {
  my ($uniqueKeyIndex, $columnNames, $columns) = @_;
  return if (not(ref($uniqueKeyIndex)) && $uniqueKeyIndex < 0);

  #Merge possible multiple unique indexes into one combined key
  my ($combinedId, $combinedColName);
  if (ref($uniqueKeyIndex) eq 'ARRAY') {
    $combinedId = join('-', map {$columns->[$_] // ''} @$uniqueKeyIndex);
    $combinedColName = join('-', map {$columnNames->[$_]} @$uniqueKeyIndex);
  }
  else {
    $combinedId      = $columns->[$uniqueKeyIndex];
    $combinedColName = $columnNames->[$uniqueKeyIndex];
  }

  if ($uniqueColumnVerifier{$combinedId}) {
    print "Unique key constraint violated! key='$combinedColName' => '$combinedId', violations='$uniqueColumnVerifier{$combinedId}'\n";
    push(@$columns, 'DUP!') if $columns->[-1] ne 'DUP!';
    $uniqueColumnVerifier{$combinedId}++;
  }
  else {
    $uniqueColumnVerifier{$combinedId} = 1;
  }
}

=head2 dynaLoadQueries

Dynamically load the required module for SQL queries.

=cut

sub dynaLoadQueries($) {
  my ($module) = @_;
  my $fullPackage = _fullPrecisionModulePackageName($module);

  my $queries = eval "\\\%${fullPackage}::queries"; #What I am trying to say is: return \%Exp::Strategy::Precision::HAMK::queries;
  die "Couldn't find the correct queries from module '$module'" unless ($queries);
  return $queries;
}

sub dynaLoadExtensions($) {
  my ($module) = @_;
  my $fullPackage = _fullPrecisionModulePackageName($module);
  if (my $sub = $fullPackage->can('extensions')) {
    warn "INFO: Running Extensions for module '$fullPackage'";
    $sub->();
  }
  else {
    warn "INFO: Module '$fullPackage' doesn't have any special extensions";
  }
}

sub _fullPrecisionModulePackageName($) {
  my $fullPackage = __PACKAGE__.'::'.$_[0];
  eval {
    (my $requirablePackageName = $fullPackage) =~ s|::|/|g; #While we're at it, make sure the package is loaded.
    require $requirablePackageName . '.pm';                 #require requires the file only once.
    #If there is no crash, the module exists and is whitelisted
  };
  die "Coudln't load the Precision extraction module '$_[0]': $@" if ($@);
  return $fullPackage;
}

sub extract($$$) {
  my ($precisionModule, $exclusionRegexp, $inclusionRegexp) = @_;

  my $queries = dynaLoadQueries($precisionModule);
  foreach my $filename (sort keys %$queries) {
    if ($inclusionRegexp && $filename !~ /$inclusionRegexp/) {                   #select the desired datasets to extract.
      print "Excluding filename='$filename' as it doesn't match the selection regexp=/$inclusionRegexp/\n";
      next;
    }
    if ($exclusionRegexp && $filename =~ /$exclusionRegexp/) {
      print "Excluding filename='$filename' as it matches the exclusion regexp=/$exclusionRegexp/\n";
      next;
    }
    doQuery($filename, $queries);
  }

  dynaLoadExtensions($precisionModule);
}

sub doQuery($$) {
  my ($filename, $queries) = @_;
  print "Extracting '$filename' with precision!\n";

  my $query          = $queries->{$filename}{sql};
  my $anonRules      = $queries->{$filename}{anonymize};
  my $uniqueKeyIndex = $queries->{$filename}{uniqueKey};
  %uniqueColumnVerifier = (); #Reset for every query

  if ($filename eq "serials_mfhd.csv") {
    extractSerialsMFHD($filename);
    next;
  }

  my $dbh = Exp::DB::dbh();
  my $sth=$dbh->prepare($query) || die("Preparing query '$filename' failed: ".$dbh->errstr);
  $sth->execute() || die("Executing query '$filename' failed: ".$dbh->errstr);

  my $i=0;
  open(my $out, ">:encoding(UTF-8)", Exp::Config::exportPath($filename)) or die("Can't open output file '".Exp::Config::exportPath($filename)."': $!");

  my ($subquery, $colNames) = pickCorrectSubquery($query, $filename);
  my $columnEncodings = getColumnEncodings($colNames); #Columns come from multiple tables via JOINs and can have distinct encodings.
  my %columnToIndexLookup; while(my ($i, $v) = each(@$colNames)) {$v =~ s/^.+\.//; $columnToIndexLookup{$v} = $i}
  #Lookup has the column names only, table names are trimmed

  print $out createHeaderRow($colNames)."\n";

  while (my @line = $sth->fetchrow_array()) {
    $i++;
    Exp::Encoding::decodeToPerlInternalEncoding(\@line, $columnEncodings);
    Exp::Encoding::Repair::repair($filename, \@line, \%columnToIndexLookup);

    deduplicateUniqueKey($uniqueKeyIndex, $colNames, \@line);

    Exp::Anonymize::anonymize(\@line, $anonRules, \%columnToIndexLookup) if ($anonymize);

    print "."    unless ($i % 10);
    print "\r$i          " unless ($i % 100);

    writeCsvRow($out, \@line);
  }

  close $out;
  print "\n\n$i records exported\n";
}

return 1;
