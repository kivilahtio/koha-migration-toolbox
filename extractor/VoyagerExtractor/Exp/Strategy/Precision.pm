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

Export all kinds of data from Voyager using precision SQL based on the ByWater Solutions' initial Voyager export tools.

=cut

my $anonymize = (defined $ENV{ANONYMIZE} && $ENV{ANONYMIZE} == 0) ? 0 : 1; #Default to anonymize confidential and personally identifiable information
warn "Not anonymizing!\n" unless $anonymize;

my %queries = (
  "02-items.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => 0,
    sql =>
      "SELECT    item.item_id,
                 bib_item.bib_id, bib_item.add_date,
                 item_vw.barcode, item.perm_location, item.temp_location, item.item_type_id, item.temp_item_type_id,
                 item_vw.enumeration, item_vw.chronology, item_vw.historical_charges, item_vw.call_no,
                 item_vw.call_no_type,
                 item.price, item.copy_number, item.pieces
       FROM      item_vw
       JOIN      item               ON (item_vw.item_id = item.item_id)
       JOIN      bib_item           ON (item_vw.item_id = bib_item.item_id)", #some items can have multiple bib_item-rows (multiple parent biblios). This is not cool.
  },
  "02-items_last_borrow_date.csv" => { #This needs to be separate from the 02-items.csv, because otherwise Oracle drops Item-rows with last_borrow_date == NULL, even if charge_date is NULL in both the comparator and the comparatee.
    encoding => "iso-8859-1",
    uniqueKey => 0,
    sql =>
      "SELECT    circ_trans_archive.item_id, max(circ_trans_archive.charge_date) as last_borrow_date \n".
      "FROM      circ_trans_archive \n".
      "LEFT JOIN item ON (circ_trans_archive.item_id = item.item_id) \n".
      "WHERE     circ_trans_archive.charge_date IS NOT NULL \n".
      "      AND item.item_id IS NOT NULL \n".
      "GROUP BY  circ_trans_archive.item_id \n".
      "ORDER BY  circ_trans_archive.item_id ASC \n",
  },
  "02a-item_notes.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => -1, #One Item can have multiple item_notes and there is no unique key in the item_notes table
    anonymize => {"item_note" => "scramble"},
    sql =>
      "SELECT    item_note.item_id, item_note.item_note, item_note.item_note_type, item_note_type.note_desc
       FROM      item_note
       LEFT JOIN item_note_type ON (item_note_type.note_type = item_note.item_note_type)",
  },
  "02-item_status.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => -1, #Each Item can have multiple afflictions
    sql =>
      "SELECT    item_status.item_id, item_status.item_status, item_status_type.item_status_desc, \n".
      "          item_status.item_status_date \n".
      "FROM      item_status \n".
      "JOIN      item_status_type ON (item_status.item_status = item_status_type.item_status_type) \n".
      "ORDER BY  item_status.item_id ASC ",
  },
  "02b-item_stats.csv" => { #Statistical item tags
    encoding => "iso-8859-1",
    uniqueKey => -1, #One Item can have many statistical categories
    sql =>
      "SELECT    item_stats.item_id, item_stat_code.item_stat_code
       FROM      item_stats
       JOIN      item_stat_code ON (item_stats.item_stat_id = item_stat_code.item_stat_id)
       ORDER BY  item_stats.date_applied ASC", #Sort order is important so we can know which row is the newest one
  },
  "05-patron_addresses.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => 0,
    anonymize => {address_line1 => "scramble", address_line2 => "scramble",
                  address_line3 => "scramble", address_line4 => "scramble",
                  address_line5 => "scramble", zip_postal    => "scramble",},
    sql =>
      "SELECT    patron_address.address_id, \n".
      "          patron_address.patron_id, \n".
      "          patron_address.address_type, address_type.address_desc, \n".
      "          patron_address.address_line1, patron_address.address_line2, patron_address.address_line3, patron_address.address_line4, \n".
      "          patron_address.address_line5, patron_address.city, patron_address.state_province, patron_address.zip_postal, patron_address.country \n".
      "FROM      patron_address \n".
      "LEFT JOIN address_type ON (address_type.address_type = patron_address.address_type) \n".
      "ORDER BY  patron_address.patron_id, patron_address.address_type \n",
  },
  "06-patron_barcode_groups.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => 0,
    sql =>
      "SELECT    patron_barcode.patron_barcode_id,
                 patron_barcode.patron_id, patron_barcode.patron_barcode,
                 patron_barcode.barcode_status, patron_barcode_status.barcode_status_desc, patron_barcode.barcode_status_date,
                 patron_barcode.patron_group_id
       FROM      patron_barcode
       LEFT JOIN patron_barcode_status ON (patron_barcode.barcode_status = patron_barcode_status.barcode_status_type)
       ORDER BY  patron_barcode.patron_id, patron_barcode.barcode_status_date DESC", #It is important to have the newest status first, so we always use the latest status && barcode for the Patron
  },
  "07-patron_names_dates.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => 0,
    anonymize => {last_name => "surname",    first_name => "firstName",
                  middle_name => "scramble", institution_id => "ssn",
                  patron_pin => "scramble",  birth_date => "date"},
    sql =>
      "SELECT    patron.patron_id,
                 patron.last_name, patron.first_name, patron.middle_name, patron.title,
                 patron.create_date, patron.expire_date, patron.institution_id,
                 patron.registration_date,
                 patron.patron_pin,
                 patron.institution_id, patron.birth_date
       FROM      patron
       ORDER BY  patron.patron_id",
  },
  "09-patron_notes.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => 0,
    anonymize => {note => 'scramble'},
    sql =>
      "SELECT    patron_notes.patron_note_id,
                 patron_notes.patron_id, patron_notes.note, patron_notes.note_type
       FROM      patron_notes 
       ORDER BY  patron_notes.patron_id,patron_notes.modify_date",
  },
  "10-patron_phones.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => 0,
    anonymize => {phone_number => 'phone'},
    sql =>
      "SELECT    patron_phone.patron_phone_id,
                 patron_address.patron_id, phone_type.phone_desc, patron_phone.phone_number
       FROM      patron_phone
       JOIN      patron_address ON (patron_phone.address_id=patron_address.address_id)
       JOIN      phone_type ON (patron_phone.phone_type=phone_type.phone_type)",
  },
  "11-patron_stat_codes.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => -1, #One patron can have many afflictions
    sql =>
      "SELECT    patron_stats.patron_id, patron_stats.patron_stat_id, patron_stat_code.patron_stat_code, patron_stats.date_applied
       FROM      patron_stats
       LEFT JOIN patron_stat_code ON (patron_stat_code.patron_stat_id = patron_stats.patron_stat_id)",
  },
  "12-current_circ.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => 0,
    sql =>
      "SELECT    circ_transactions.circ_transaction_id, \n".
      "          circ_transactions.patron_id, patron_barcode.patron_barcode, \n".
      "          circ_transactions.item_id, item_barcode.item_barcode, \n".
      "          circ_transactions.charge_date,circ_transactions.current_due_date, \n".
      "          circ_transactions.renewal_count, circ_transactions.charge_location \n".
      "FROM      circ_transactions \n".
      "JOIN      patron             ON (circ_transactions.patron_id=patron.patron_id) \n".
      "LEFT JOIN patron_barcode     ON (circ_transactions.patron_id=patron_barcode.patron_id) \n".
      "LEFT JOIN item_barcode       ON (circ_transactions.item_id=item_barcode.item_id) \n",
  },
  "12a-current_circ_last_renew_date.csv" => { #Same as 02-items_last_borrow_date.csv
    encoding => "iso-8859-1",
    uniqueKey => 0,
    sql =>
      "SELECT    renew_transactions.circ_transaction_id, max(renew_transactions.renew_date) as last_renew_date \n".
      "FROM      renew_transactions \n".
      "WHERE     renew_transactions.renew_date IS NOT NULL \n".
      "GROUP BY  renew_transactions.circ_transaction_id \n".
      "ORDER BY  renew_transactions.circ_transaction_id ASC \n",
  },
  "14-fines.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => 0,
    sql =>
      "SELECT    fine_fee.fine_fee_id, \n".
      "          patron.patron_id, item_vw.item_id, item_vw.barcode as item_barcode, \n". #Select instead the joined patron and item_vw -tables' primary keys, so we detect if those are missing.
      "          fine_fee.create_date, fine_fee.fine_fee_type, fine_fee.fine_fee_location, \n".
      "          fine_fee.fine_fee_amount, fine_fee.fine_fee_balance, \n".
      "          fine_fee.fine_fee_note \n".
      "FROM      fine_fee \n".
      "LEFT JOIN item_vw ON (item_vw.item_id = fine_fee.item_id) \n".
      "LEFT JOIN patron  ON (fine_fee.patron_id = patron.patron_id) \n".
      "WHERE     fine_fee.fine_fee_balance != 0 \n",
  },

  #Koha has a single subscription for each branch receiving serials.
  #Voyager has a single subscription which orders serials to multiple branches.
  #Need to clone Voyager subscriptions, one per branch to Koha.
  #issues_received has location_id. That is the only place with any location information.
  #ByWater scripts extract location from MFHD $852b but that doesn't reliably exist here?
  "20-subscriptions.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => [0, 1], #Whenever a subscription order has been continued, a new component with the same component_id is added.
    sql =>
      "SELECT    component.component_id, component_pattern.end_date,
                 subscription.subscription_id, line_item.bib_id,
                 subscription.start_date,
                 component.create_items
       FROM      component
       LEFT JOIN subscription      ON (component.subscription_id  = subscription.subscription_id)
       LEFT JOIN line_item         ON (subscription.line_item_id  = line_item.line_item_id)
       LEFT JOIN component_pattern ON (component.component_id     = component_pattern.component_id)
       LEFT JOIN serial_issues     ON (serial_issues.component_id = component.component_id)
       LEFT JOIN issues_received   ON (issues_received.issue_id   = serial_issues.issue_id)
       GROUP BY  subscription.subscription_id, line_item.bib_id, component.component_id,
                 subscription.start_date, component_pattern.end_date,
                 component.create_items
       ORDER BY  component.component_id ASC",
  },
  "20a-subscription_locations.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => [0, 1], #Check later that each component has only one location for received items.
    sql =>
      "SELECT    issues_received.component_id, issues_received.location_id
       FROM      issues_received
       GROUP BY  issues_received.component_id, issues_received.location_id
       ORDER BY  issues_received.component_id ASC, issues_received.location_id ASC",
  },

  #No data in the Voyager subscription about into which branches it orders serials?
  #Only received serials have location-information.
  #Currently ignore predictions, because migrating predictions most certainly will be very slow/tedious vs benefits.
  "21-ser_issues.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => [0, 1],
    sql =>
      "SELECT    serial_issues.issue_id, serial_issues.component_id,
                 line_item.bib_id,
                 serial_issues.enumchron, serial_issues.lvl1, serial_issues.lvl2, serial_issues.lvl3,
                 serial_issues.lvl4, serial_issues.lvl5, serial_issues.lvl6, serial_issues.alt_lvl1,
                 serial_issues.alt_lvl2, serial_issues.chron1, serial_issues.chron2, serial_issues.chron3,
                 serial_issues.chron4, serial_issues.alt_chron,
                 serial_issues.expected_date, serial_issues.receipt_date, serial_issues.received
       FROM      serial_issues
       LEFT JOIN component       ON (component.component_id = serial_issues.component_id)
       LEFT JOIN subscription    ON (subscription.subscription_id = component.subscription_id)
       LEFT JOIN line_item       ON (subscription.line_item_id = line_item.line_item_id)
       ORDER BY  serial_issues.issue_id ASC",
  },

  #Extract MFHD only for serials, so the location and subscription history can be extracted.
  #The "20a-subscription_locations.csv" seems to generate rather excellent results for HAMK, but not dropping this feature yet, since
  # ByWater must have had a good reason to implement it. Prolly this is needed for other Voyager libraries.
  "serials_mfhd.csv" => {
    encoding => "UTF-8",
    uniqueKey => -1,
    sql =>
      "SELECT 1", #Special processing for this one
  },
  "29-requests.csv" => {
    encoding => "iso-8859-1",
    #Multiple holds with the same primary key? This is a parallel hold which is fulfillable by any of the reserved items.
    #TODO: This feature is something that needs to be implemented in Koha first. For the time being, let the extractor complain about it so we wont forget.
    #TODO: Apparently Voyager implements parallel hold queus via this mechanism, where the hold is targeted to items available via one of the parallel hold queues.
    uniqueKey => 0,
    sql =>
      "SELECT    hold_recall.hold_recall_id,
                 hold_recall.bib_id, hold_recall.patron_id, hold_recall_items.item_id, hold_recall.request_level, hold_recall_items.queue_position,
                 hold_recall_status.hr_status_desc, hold_recall_items.hold_recall_status, hold_recall_items.hold_recall_status_date,
                 hold_recall.create_date, hold_recall.expire_date, hold_recall.pickup_location
       FROM      hold_recall
       JOIN      hold_recall_items  on (hold_recall_items.hold_recall_id = hold_recall.hold_recall_id)
       JOIN      hold_recall_status on (hold_recall_status.hr_status_type = hold_recall_items.hold_recall_status)
       ORDER BY  hold_recall_items.item_id, hold_recall_items.queue_position",
  },
);


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

=head2 extractQuerySelectColumns

 @returns ARRAYRef, The 'table.column' -entries in the SELECT-clause.

=cut

sub extractQuerySelectColumns($) {
  my ($query) = @_;
  my $header_row = $query;
  while ( $header_row =~ s/(select\s|,\s*)\s*convert\(([a-z0-9_]+),.*\)/$1$2/si ) {}
  $header_row =~ s/\s+/\t/g;
  $header_row =~ s/^\s*select\s+//i;
  $header_row =~ s/\tfrom\t.*//i;
  $header_row =~ s/,\t/,/g;
  $header_row =~ tr/A-Z/a-z/;
  $header_row =~ s/\w+\((.+?)\)/$1/;          #Trim column functions such as max()
  $header_row =~ s/\.\w+\s+as\s+(\w+)/\.$1/g; #Simplify column aliasing... renew_transactions.renew_date as last_renew_date -> renew_transactions.last_renew_date
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
      $line->[$k] =~ s/"/'/g;
      $line->[$k] =~ s/\r//gsm;
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

sub extract($) {
  my ($inclusionRegexp) = @_;
  my $dbh = Exp::DB::dbh();

  foreach my $filename (sort keys %queries) {
    unless (($inclusionRegexp && length $inclusionRegexp < 2) || #Check if the value is a boolean, to just extract all data.
            $filename =~ /$inclusionRegexp/) {                   #Or use it as a regexp to select the desired datasets to extract.
      print "Excluding filename='$filename' as it doesn't match the selection regexp=/$inclusionRegexp/\n";
      next;
    }
    print "Extracting '$filename' with precision!\n";

    my $query          = $queries{$filename}{sql};
    my $inputEncoding  = $queries{$filename}{encoding};
    my $anonRules      = $queries{$filename}{anonymize};
    my $uniqueKeyIndex = $queries{$filename}{uniqueKey};
    %uniqueColumnVerifier = (); #Reset for every query

    if ($filename eq "serials_mfhd.csv") {
      extractSerialsMFHD($filename);
      next;
    }

    my $sth=$dbh->prepare($query) || die("Preparing query '$query' failed: ".$dbh->errstr);
    $sth->execute() || die("Executing query '$query' failed: ".$dbh->errstr);

    my $i=0;
    open(my $out, ">:encoding(UTF-8)", Exp::Config::exportPath($filename)) or die("Can't open output file '".Exp::Config::exportPath($filename)."': $!");

    my $colNames = extractQuerySelectColumns($query);
    my $columnEncodings = getColumnEncodings($colNames); #Columns come from multiple tables via JOINs and can have distinct encodings.
    #Lookup has the column names only, table names are trimmed
    my %columnToIndexLookup; while(my ($i, $v) = each(@$colNames)) {$v =~ s/^.+\.//; $columnToIndexLookup{$v} = $i}

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
}

return 1;
