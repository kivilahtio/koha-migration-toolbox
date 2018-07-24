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
    sql =>
      "SELECT    item.item_id, bib_item.bib_id,bib_item.add_date,
                 item_vw.barcode,item.perm_location,item.temp_location,item.item_type_id,item.temp_item_type_id,
                 item_vw.enumeration,item_vw.chronology,item_vw.historical_charges,item_vw.call_no,
                 item_vw.call_no_type,
                 item.price,item.copy_number,item.pieces,
                 item_note.item_note, item_note.item_note_type
       FROM      item_vw
       JOIN      item        ON (item_vw.item_id = item.item_id)
       LEFT JOIN item_note   ON (item_vw.item_id = item_note.item_id)
       JOIN      bib_item    ON  (item_vw.item_id = bib_item.item_id)",
  },
  "02-item_status.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    item_status.item_id,item_status.item_status,item_status_type.item_status_desc
       FROM      item_status
       JOIN      item_status_type ON (item_status.item_status = item_status_type.item_status_type)",
  },
  "03-item_status_descriptions.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    item_status_type.item_status_type, item_status_type.item_status_desc
       FROM      item_status_type",
  },
  "04-barcode_statuses.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    item_vw.barcode,item_status.item_status
       FROM      item_vw 
       JOIN      item_status ON item_vw.item_id = item_status.item_id",
  },
  "05-patron_addresses.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    PATRON_ADDRESS.PATRON_ID, PATRON_ADDRESS.ADDRESS_TYPE, PATRON_ADDRESS.ADDRESS_LINE1, 
                 PATRON_ADDRESS.ADDRESS_LINE2, PATRON_ADDRESS.ADDRESS_LINE3, PATRON_ADDRESS.ADDRESS_LINE4, 
                 PATRON_ADDRESS.ADDRESS_LINE5, PATRON_ADDRESS.CITY, PATRON_ADDRESS.STATE_PROVINCE, 
                 PATRON_ADDRESS.ZIP_POSTAL, PATRON_ADDRESS.COUNTRY
       FROM      PATRON_ADDRESS
       ORDER BY  PATRON_ADDRESS.PATRON_ID, PATRON_ADDRESS.ADDRESS_TYPE",
  },
  "06-patron_groups.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    patron_barcode.patron_id, patron_barcode.patron_barcode, patron_barcode.barcode_status, 
                 patron_barcode.patron_group_id FROM patron_barcode
       WHERE     patron_barcode.patron_barcode IS NOT NULL
       ORDER BY  patron_barcode.patron_id",
  },
  "06a-patron_group_names.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    patron_group.patron_group_id,patron_group.patron_group_name
       FROM      patron_group",
  },
  "07-patron_names_dates.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    PATRON.PATRON_ID, PATRON.LAST_NAME, PATRON.FIRST_NAME, PATRON.MIDDLE_NAME, 
                 PATRON.CREATE_DATE, PATRON.EXPIRE_DATE, PATRON.INSTITUTION_ID,
                 PATRON.REGISTRATION_DATE,
                 PATRON.PATRON_PIN,
                 PATRON.INSTITUTION_ID, PATRON.BIRTH_DATE
       FROM      PATRON
       ORDER BY  PATRON.PATRON_ID",
  },
  "08-patron_groups_nulls.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    patron_barcode.patron_id, patron_barcode.patron_barcode, patron_barcode.barcode_status,
                 patron_barcode.patron_group_id FROM patron_barcode
       WHERE     patron_barcode.patron_barcode IS NULL
             AND patron_barcode.barcode_status=1",
  },
  "09-patron_notes.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    patron_notes.patron_id, patron_notes.note, patron_notes.note_type
       FROM      patron_notes 
       ORDER BY  patron_notes.patron_id,patron_notes.modify_date",
  },
  "10-patron_phones.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    patron_address.patron_id,
                 phone_type.phone_desc,
                 patron_phone.phone_number
       FROM      patron_phone
       JOIN      patron_address ON (patron_phone.address_id=patron_address.address_id)
       JOIN      phone_type ON (patron_phone.phone_type=phone_type.phone_type)",
  },
  "11-patron_stat_codes.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    patron_stats.patron_id,patron_stats.patron_stat_id,patron_stats.date_applied
       FROM      patron_stats",
  },
  "11a-patron_stat_desc.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    patron_stat_code.patron_stat_id,patron_stat_code.patron_stat_desc
       FROM      patron_stat_code",
  },
  "12-current_circ.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    patron_barcode.patron_barcode, circ_transactions.patron_id, circ_transactions.charge_location, circ_transactions.item_id,
                 item_barcode.item_barcode,
                 circ_transactions.charge_date,circ_transactions.current_due_date,
                 circ_transactions.renewal_count
       FROM      circ_transactions
       JOIN      patron ON (circ_transactions.patron_id=patron.patron_id)
       LEFT JOIN patron_barcode ON (circ_transactions.patron_id=patron_barcode.patron_id)
       LEFT JOIN item_barcode   ON (circ_transactions.item_id=item_barcode.item_id)
       WHERE     patron_barcode.barcode_status = 1
             AND patron_barcode.patron_barcode IS NOT NULL
             AND item_barcode.barcode_status = 1",
  },
  "13-last_borrow_dates.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    item_vw.barcode,max(charge_date)
       FROM      circ_trans_archive
       JOIN      item_vw ON (circ_trans_archive.item_id = item_vw.item_id)
       GROUP BY  item_vw.barcode",
  },
  "14-fines.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    patron_barcode.patron_barcode, fine_fee.patron_id,
                 item_barcode.item_barcode, fine_fee.item_id,
                 fine_fee.create_date, fine_fee.fine_fee_type, fine_fee.fine_fee_location,
                 fine_fee.fine_fee_amount, fine_fee.fine_fee_balance,
                 fine_fee.fine_fee_note
       FROM      fine_fee
       JOIN      patron ON (fine_fee.patron_id=patron.patron_id)
       LEFT JOIN patron_barcode ON (fine_fee.patron_id=patron_barcode.patron_id)
       LEFT JOIN item_barcode   ON (fine_fee.item_id=item_barcode.item_id)
       WHERE     patron_barcode.barcode_status = 1
             AND patron_barcode.patron_barcode IS NOT NULL
             AND item_barcode.barcode_status = 1
             AND fine_fee.fine_fee_balance != 0",
  },
  "17-fine_types.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    fine_fee_type.fine_fee_type,fine_fee_type.fine_fee_desc
       FROM      fine_fee_type",
  },
  "18-item_stats.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    item_stats.item_id,item_stat_code.item_stat_code
       FROM      item_stats
       JOIN      item_stat_code ON (item_stats.item_stat_id = item_stat_code.item_stat_id)",
  },

  #Koha has a single subscription for each branch receiving serials.
  #Voyager has a single subscription which orders serials to multiple branches.
  #Need to clone Voyager subscriptions, one per branch to Koha.
  #issues_received has location_id. That is the only place with any location information.
  #ByWater scripts extract location from MFHD $852b but that doesn't reliably exist here?
  "20-subscriptions.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    subscription.subscription_id, line_item.bib_id, component.component_id, subscription.start_date
       FROM      subscription
       LEFT JOIN line_item       ON (subscription.line_item_id = line_item.line_item_id)
       LEFT JOIN component       ON (component.subscription_id = subscription.subscription_id)
       LEFT JOIN serial_issues   ON (serial_issues.component_id = component.component_id)
       LEFT JOIN issues_received ON (issues_received.issue_id = serial_issues.issue_id)
       GROUP BY  subscription.subscription_id, line_item.bib_id, component.component_id, subscription.start_date",
  },

  #No data in the Voyager subscription about into which branches it orders serials?
  #Only received serials have location-information.
  #Currently ignore predictions, because migrating predictions most certainly will be very slow/tedious vs benefits.
  "21-ser_issues.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    issue_id, serial_issues.component_id, line_item.bib_id,
                 enumchron, lvl1, lvl2, lvl3, lvl4, lvl5, lvl6, alt_lvl1, alt_lvl2, chron1, chron2, chron3, chron4, alt_chron,
                 expected_date, receipt_date, received
       FROM      serial_issues
       LEFT JOIN component       ON (component.component_id = serial_issues.component_id)
       LEFT JOIN subscription    ON (subscription.subscription_id = component.subscription_id)
       LEFT JOIN line_item       ON (subscription.line_item_id = line_item.line_item_id)",
  },

  #Extract MFHD only for serials, so the location and subscription history can be extracted
  "serials_mfhd.csv" => {
    encoding => "UTF-8",
    sql =>
      "SELECT 1", #Special processing for this one
  },
  "29-requests.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    HOLD_RECALL.BIB_ID, HOLD_RECALL.PATRON_ID, HOLD_RECALL_ITEMS.ITEM_ID, HOLD_RECALL.REQUEST_LEVEL, HOLD_RECALL_ITEMS.QUEUE_POSITION,
                 HOLD_RECALL_STATUS.HR_STATUS_DESC, HOLD_RECALL_ITEMS.HOLD_RECALL_STATUS, HOLD_RECALL_ITEMS.HOLD_RECALL_STATUS_DATE,
                 HOLD_RECALL.CREATE_DATE, HOLD_RECALL.EXPIRE_DATE, HOLD_RECALL.PICKUP_LOCATION
       FROM      HOLD_RECALL
       JOIN      HOLD_RECALL_ITEMS  ON (HOLD_RECALL_ITEMS.HOLD_RECALL_ID = HOLD_RECALL.HOLD_RECALL_ID)
       JOIN      HOLD_RECALL_STATUS ON (HOLD_RECALL_STATUS.HR_STATUS_TYPE = HOLD_RECALL_ITEMS.HOLD_RECALL_STATUS)
       ORDER BY  HOLD_RECALL_ITEMS.ITEM_ID, HOLD_RECALL_ITEMS.QUEUE_POSITION",
  },
  "29a-locations.csv" => {
    encoding => "iso-8859-1",
    sql =>
      "SELECT    location.location_id, location.location_code, location.location_name
       FROM      location"
  },
);


sub extractSerialsMFHD($) {
  my ($filename) = @_;
  require Exp::nvolk_marc21;
  require Exp::MARC;
  my $csvHeadersPrinted = 0;

  #Turn MFHD's into MARCXML, and then use a transformation hook to turn it into .csv instead!! Brilliant! What could go wrong...
  Exp::MARC::_exportMARC(
    $filename,
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
        print "\n".join(" -- ", ($mfhd_id, $location, @holdingsFields))."\n";
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

#I managed to install SQL::Statement without root permissions, but let's try to keep the extra module deps as small as possible.
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

sub extractQuerySelectColumns($) {
  my ($query) = @_;
  my $header_row = $query;
  while ( $header_row =~ s/(select\s|,\s*)\s*convert\(([a-z0-9_]+),.*\)/$1$2/si ) {}
  $header_row =~ s/\s+/\t/g;
  $header_row =~ s/^\s*select\s+//i;
  $header_row =~ s/\tfrom\t.*//i;
  $header_row =~ s/,\t/,/g;
  $header_row =~ tr/A-Z/a-z/;
  my @cols = split(',', $header_row);
  return \@cols;
}

sub createHeaderRow($) {
  my ($cols) = @_;
  my $header_row = join(',', @$cols);
  $header_row =~ s/[a-z_]+\.([a-z])/$1/g; #Trim the table definition prefix
  return $header_row;
}

sub anonymize($$) {
  my ($filename, $line) = @_;
  if ( $filename eq "05-patron_addresses.csv" ) {
      # "SELECT PATRON_ADDRESS.PATRON_ID, PATRON_ADDRESS.ADDRESS_TYPE, PATRON_ADDRESS.ADDRESS_LINE1, 
      # PATRON_ADDRESS.ADDRESS_LINE2, PATRON_ADDRESS.ADDRESS_LINE3, PATRON_ADDRESS.ADDRESS_LINE4, 
      # PATRON_ADDRESS.ADDRESS_LINE5, PATRON_ADDRESS.CITY, PATRON_ADDRESS.STATE_PROVINCE, 
      # PATRON_ADDRESS.ZIP_POSTAL, PATRON_ADDRESS.COUNTRY
      if ( $line->[1] eq '3' ) { # email
        $line->[2] = 'etunimi.sukunimi@hamk.fi';
        # Nollaa muut kentat varmuuden vuoksi
        for ( my $k=3; $k < @$line; $k++ ) {
            $line->[$k] = '';
        }
      }
      else {
        if ( $line->[2] ) { $line->[2] = 'Katuosoite 1A'; }
        if ( $line->[3] ) { $line->[3] = 'Toinen osoiterivi'; }
        if ( $line->[4] ) { $line->[4] = 'Kolmas osoiterivi'; }
        if ( $line->[5] ) { $line->[5] = 'Neljäs osoiterivi'; }
        if ( $line->[6] ) { $line->[6] = 'Viides osoiterivi'; }
        if ( $line->[7] ) { $line->[7] = 'Hämeenlinna'; }
        #if ( $line->[8] ) { $line->[8] = 'Häme'; } #City is not personally identifiable and helps spot encoding issues
        if ( $line->[9] ) { $line->[9] = '13100'; }
        if ( $line->[10] ) { $line->[10] = 'Suomi'; }
      }
  }
  if ( $filename eq "07-patron_names_dates.csv" ) {
    # "SELECT PATRON.PATRON_ID, PATRON.LAST_NAME, PATRON.FIRST_NAME, PATRON.MIDDLE_NAME, 
    # PATRON.CREATE_DATE, PATRON.EXPIRE_DATE, PATRON.INSTITUTION_ID
    if ( $line->[1] ) { $line->[1] = 'Doe'; }
    if ( $line->[2] ) {
      $line->[2] = 'John';
      if ( $line->[6] && $line->[6] =~ /\-\d\d[02468].$/ ) {
        $line->[2] = 'Jane';
      }
    }
    if ( $line->[3] ) {
      my $tmp = $line->[0]%25;
      $line->[3] = chr($tmp+65).".";
    }
    if ( $line->[6] ) {
      $line->[6] =~ s/\d\d(\d).$/00${1}0/;
      my $tmp = '0104'.int(rand(30)+70);
      $line->[6] =~ s/^....../$tmp/;
    }
    if ( $line->[9] ) { #ssn aka institution_id
      $line->[9] =~ s/\d/1/gsm;
    }
    if ( $line->[10] ) { #BIRTH_DATE
      $line->[10] =~ s/\d/1/gsm;
    }
  }

  if ( $filename eq "09-patron_notes.csv" ) {
    # SELECT patron_notes.patron_id,patron_notes.note FROM patron_notes 
    my $new_note = '';
    my $old_line = $line->[1];
    while ( $line->[1] ) {
      if ( $line->[1] =~ s/^\d// ) {
        $new_note .= int(rand(10));
      }
      elsif ( $line->[1] =~ s/^(\s+|[;.\-,:])// ) {
        $new_note .= $1;
      }
      elsif ( $line->[1] =~ s/^\p{Ll}// ) {
        $new_note .= chr(97+int(rand(25)));
      }
      elsif ( $line->[1] =~ s/.// ) {
        $new_note .= chr(65+int(rand(25)));
      }
      if ( $old_line eq $line->[1] ) {
        $line->[1] = 'ABORT';
      }
    }
    $line->[1] = $new_note;
  }

  if ( $filename eq "10-patron_phones.csv" ) {
    # "SELECT patron_address.patron_id,
    # phone_type.phone_desc, patron_phone.phone_number
    my $new_note = '';
    if ( $line->[2] =~ s/^(\+358|040|09|044|050)// ) {
      $new_note = $1;
    }
    while ( $line->[2] ) {
      if ( $line->[2] =~ s/^\d// ) {
        $new_note .= int(rand(10));
      }
      elsif ( $line->[2] =~ s/^(.)// ) {
        $new_note .= $1;
      }
    }
    $line->[2] = $new_note;
  }

  if ( $filename eq "12-current_circ.csv" ) {
    # "SELECT patron_barcode.patron_barcode, patron.institution_id,circ_transactions.patron_id,
    # item_barcode.item_barcode,
    # circ_transactions.charge_date,circ_transactions.current_due_date,
    # circ_transactions.renewal_count

    if ( 0 && $line->[1] ) { # tässä oli ennen patron.institution_id
      $line->[1] =~ s/\d\d(\d).$/00${1}0/;
      my $tmp = '0104'.int(rand(30)+70);
      $line->[1] =~ s/^....../$tmp/;
    }
  }
}

sub writeCsvRow($$) {
  my ($FH, $line) = @_;
  for my $k (0..scalar(@$line)-1) {
    if ($line->[$k]) {
      $line->[$k] =~ s/"/'/g;
      if ($line->[$k] =~ /,/) {
        $line->[$k] = '"'.$line->[$k].'"';
      }
    }
    else {
      $line->[$k] = '';
    }
  }
  print $FH join(",", @$line)."\n";
}

sub extract() {
  my $dbh = Exp::DB::dbh();

  foreach my $filename (sort keys %queries) {
    my $query         = $queries{$filename}{sql};
    my $inputEncoding = $queries{$filename}{encoding};

    print "$filename\n";

    if ( $filename eq "serials_mfhd.csv") {
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

      anonymize($filename, \@line) if ($anonymize);

      print "."    unless ($i % 10);
      print "\r$i" unless ($i % 100);

      writeCsvRow($out, \@line);
    }

    close $out;
    print "\n\n$i records exported\n";
  }
}

return 1;
