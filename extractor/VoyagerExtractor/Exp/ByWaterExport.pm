#!/opt/CSCperl/current/bin/perl

use strict;
use warnings;
use DBI;

use Exp::Config;

#use YAML::XS qw/LoadFile/;
$|=1;

our $anonymize = 1;

sub nv_to_utf8($) {
  my $val = $_[0];
  my $orig_val = $val;
  my $printed = 0;
  use bytes;
  my $str = '';
  my $is_record = 0;
  if ( $orig_val =~ /^[0-9]{5}[acdnp]....22/ ) { # marc-tietue vissiin
    $is_record = 1;
    # Koko ei saa muuttua...
  }
  else {
    # Eivät mene tietueisiin, joten ei koolla niin väliä
    $val =~ s/\xC3/Ã/g;
    $val =~ s/\xC4/Ä/g;
    $val =~ s/\xC5/Å/g;
    $val =~ s/\xC9/É/g;
    $val =~ s/\xD6/Ö/g;
    $val =~ s/\xE4/ä/g;
    $val =~ s/\xE5/å/g;
    $val =~ s/\xF6/ö/g;
    $val =~ s/\xFC/ü/g;
  }
  
  while ( length($val) ) {
    my $hit = 0;
    while ( $val =~ s/^([\000-\177]+)//s ||
	    $val =~ s/^([\300-\337][\200-\277])//s ||
	    $val =~ s/^([\340-\357][\200-\277]{2})//s ||
	    $val =~ s/^([\360-\367][\200-\277]{3})//s ) {
      $str .= $1;
      $hit = 1;
    }
    if ( !$hit ) {
      my $c = substr($val, 0, 1); # skip first char
      print STDERR "SKIP '$c'";
      if ( $is_record ) { # marc-tietue vissiin
	$str .= '?'; # Säilytä koko...
      }
      if ( !$printed ) {
	print STDERR " in '$orig_val'\n";
	$printed = 1;
      }
      print STDERR "\n";
      $val = substr($val, 1); # skip first char
    }
  }

  no bytes;
  return $str;
}

sub nv_is_utf8($) { # po. is_utf8
  use bytes;
  my ($val, $msg ) = @_;
  my $original_val = $val;
  my $i = 1;
  while ( $i ) {
    $i = 0;
    if ( $val =~ s/^[\000-\177]+//s ||
         $val =~ s/^([\300-\337][\200-\277])//s ||
         $val =~ s/^([\340-\357][\200-\277]{2})+//s ||
         $val =~ s/^([\360-\367][\200-\277]{3})+//s ) {
       $i=1;
    }
  }
  no bytes;
  if ( $val eq '' ) {
    return 1;
  }
#  #if ( $val !~ /^([\000-\177\304\326\344\366])+$/s ) {
#  my $reval = $val;
#  $reval =~ s/[\000-177]//g;
#  unless ( $reval =~ /^[\304\326\344\366]+$/ ) {
#    $i = ord($val);
#    my $c = chr($i);
#    #print STDERR "$msg: UTF8 Failed: '$c'/$i/'$val'\n$original_val\n";
#
#  }
  return 0;
}

use Exp::Config;
my $config = $Exp::Config::config;


our $host = $config->{host};
our $username = $config->{username};
our $password = $config->{password};
our $sid = $config->{sid};
our $port = $config->{port};

my $dbh = DBI->connect("dbi:Oracle:host=$host;sid=$sid;port=$port;", $username, $password ) || die "Could no connect: $DBI::errstr";


my $query = "SELECT patron_barcode.patron_barcode,patron.institution_id,circ_transactions.patron_id,
                    item_barcode.item_barcode,
                    circ_transactions.charge_date,circ_transactions.current_due_date,
                    circ_transactions.renewal_count
               FROM circ_transactions
               JOIN patron ON (circ_transactions.patron_id=patron.patron_id)
          LEFT JOIN patron_barcode ON (circ_transactions.patron_id=patron_barcode.patron_id)
          LEFT JOIN item_barcode ON (circ_transactions.item_id=item_barcode.item_id)
              WHERE patron_barcode.barcode_status = 1 AND patron_barcode.patron_barcode IS NOT NULL
                AND item_barcode.barcode_status = 1";

my %queries = (
#   "01-bib_records.csv" => "SELECT BIB_DATA.RECORD_SEGMENT, BIB_DATA.BIB_ID, BIB_DATA.SEQNUM
#                            FROM BIB_DATA
#                            ORDER BY BIB_DATA.BIB_ID, BIB_DATA.SEQNUM",
   "02-items.csv"  => "SELECT item.item_id, bib_item.bib_id,bib_item.add_date,
                       item_vw.barcode,item.perm_location,item.temp_location,item.item_type_id,item.temp_item_type_id,
                       item_vw.enumeration,item_vw.chronology,item_vw.historical_charges,item_vw.call_no,
                       item_vw.call_no_type,
                       item.price,item.copy_number,item.pieces,
                       item_note.item_note, item_note.item_note_type
                       FROM   item_vw
                       JOIN   item        ON (item_vw.item_id = item.item_id)
                       LEFT JOIN   item_note   ON (item_vw.item_id = item_note.item_id)
                       JOIN   bib_item    ON  (item_vw.item_id = bib_item.item_id)",
   "02-item_status.csv" => "SELECT item_status.item_id,item_status.item_status,item_status_type.item_status_desc
                           FROM item_status JOIN item_status_type ON (item_status.item_status = item_status_type.item_status_type)",
   "03-item_status_descriptions.csv" => "SELECT item_status_type.item_status_type, item_status_type.item_status_desc
                                         FROM item_status_type",
   "04-barcode_statuses.csv" => "SELECT item_vw.barcode,item_status.item_status FROM item_vw 
                                 JOIN item_status ON item_vw.item_id = item_status.item_id",
   "05-patron_addresses.csv" => "SELECT PATRON_ADDRESS.PATRON_ID, PATRON_ADDRESS.ADDRESS_TYPE, PATRON_ADDRESS.ADDRESS_LINE1, 
                                 PATRON_ADDRESS.ADDRESS_LINE2, PATRON_ADDRESS.ADDRESS_LINE3, PATRON_ADDRESS.ADDRESS_LINE4, 
                                 PATRON_ADDRESS.ADDRESS_LINE5, PATRON_ADDRESS.CITY, PATRON_ADDRESS.STATE_PROVINCE, 
                                 PATRON_ADDRESS.ZIP_POSTAL, PATRON_ADDRESS.COUNTRY
                                 FROM PATRON_ADDRESS
                                 ORDER BY PATRON_ADDRESS.PATRON_ID, PATRON_ADDRESS.ADDRESS_TYPE",
   "06-patron_groups.csv"    => "SELECT patron_barcode.patron_id, patron_barcode.patron_barcode, patron_barcode.barcode_status, 
                                 patron_barcode.patron_group_id FROM patron_barcode
                                 WHERE patron_barcode.patron_barcode IS NOT NULL
                                 ORDER BY patron_barcode.patron_id",
   "06a-patron_group_names.csv" => "SELECT patron_group.patron_group_id,patron_group.patron_group_name FROM patron_group",

   "07-patron_names_dates.csv" => "SELECT PATRON.PATRON_ID, PATRON.LAST_NAME, PATRON.FIRST_NAME, PATRON.MIDDLE_NAME, 
                                   PATRON.CREATE_DATE, PATRON.EXPIRE_DATE, PATRON.INSTITUTION_ID,
                                   PATRON.REGISTRATION_DATE,
                                   PATRON.PATRON_PIN,
                                   PATRON.INSTITUTION_ID, PATRON.BIRTH_DATE
                                   FROM PATRON
                                   ORDER BY PATRON.PATRON_ID",
   "08-patron_groups_nulls.csv" => "SELECT patron_barcode.patron_id, patron_barcode.patron_barcode, patron_barcode.barcode_status,
                                    patron_barcode.patron_group_id FROM patron_barcode
                                    WHERE patron_barcode.patron_barcode IS NULL AND patron_barcode.barcode_status=1",
   "09-patron_notes.csv" => "SELECT patron_notes.patron_id, patron_notes.note, patron_notes.note_type FROM patron_notes 
                             order by patron_notes.patron_id,patron_notes.modify_date",
   "10-patron_phones.csv" => "SELECT patron_address.patron_id,
                              phone_type.phone_desc,
                              patron_phone.phone_number
                              FROM patron_phone
                              JOIN patron_address ON (patron_phone.address_id=patron_address.address_id)
                              JOIN phone_type ON (patron_phone.phone_type=phone_type.phone_type)",
   "11-patron_stat_codes.csv" => "SELECT patron_stats.patron_id,patron_stats.patron_stat_id,patron_stats.date_applied
                                  FROM patron_stats",
   "11a-patron_stat_desc.csv" => "SELECT patron_stat_code.patron_stat_id,patron_stat_code.patron_stat_desc
                                  FROM patron_stat_code",
   "12-current_circ.csv" => "SELECT patron_barcode.patron_barcode, circ_transactions.patron_id, circ_transactions.charge_location, circ_transactions.item_id,
                             item_barcode.item_barcode,
                             circ_transactions.charge_date,circ_transactions.current_due_date,
                             circ_transactions.renewal_count
                             FROM circ_transactions
                             JOIN patron ON (circ_transactions.patron_id=patron.patron_id)
                             LEFT JOIN patron_barcode ON (circ_transactions.patron_id=patron_barcode.patron_id)
                             LEFT JOIN item_barcode ON (circ_transactions.item_id=item_barcode.item_id)
                             WHERE patron_barcode.barcode_status = 1 AND patron_barcode.patron_barcode IS NOT NULL
                             AND item_barcode.barcode_status = 1",
   "13-last_borrow_dates.csv" => "SELECT item_vw.barcode,max(charge_date)
                                  FROM circ_trans_archive
                                  JOIN item_vw ON (circ_trans_archive.item_id = item_vw.item_id)
                                  GROUP BY item_vw.barcode",
   "14-fines.csv" => "SELECT patron_barcode.patron_barcode, fine_fee.patron_id,
                      item_barcode.item_barcode, fine_fee.item_id,
                      fine_fee.create_date, fine_fee.fine_fee_type, fine_fee.fine_fee_location,
                      fine_fee.fine_fee_amount, fine_fee.fine_fee_balance,
                      fine_fee.fine_fee_note
                      FROM fine_fee
                      JOIN patron ON (fine_fee.patron_id=patron.patron_id)
                      LEFT JOIN patron_barcode ON (fine_fee.patron_id=patron_barcode.patron_id)
                      LEFT JOIN item_barcode ON (fine_fee.item_id=item_barcode.item_id)
                      WHERE patron_barcode.barcode_status = 1 and patron_barcode.patron_barcode is not null
                      AND item_barcode.barcode_status = 1
                      AND fine_fee.fine_fee_balance != 0",
   "15-OPAC_book_lists.csv" => "SELECT saved_records_results.patron_id,saved_records_results.bib_id 
                                FROM saved_records_results",
#   "16-authorities.csv" => "SELECT AUTH_DATA.AUTH_ID, AUTH_DATA.RECORD_SEGMENT, AUTH_DATA.SEQNUM
#                            FROM AUTH_DATA
#                            ORDER BY AUTH_DATA.AUTH_ID, AUTH_DATA.SEQNUM",
   "17-fine_types.csv" => "SELECT fine_fee_type.fine_fee_type,fine_fee_type.fine_fee_desc FROM fine_fee_type",
   "18-item_stats.csv" => "SELECT item_stats.item_id,item_stat_code.item_stat_code
                           FROM item_stats JOIN item_stat_code ON (item_stats.item_stat_id = item_stat_code.item_stat_id)",
    # Allaolevista '*' aukirjoitettu
   "19-ser_component.csv" => "SELECT component_id, subscription_id, component_name, component_name_norm, unit_title, category, predict, next_issue_id, note, item_type_id, create_items, claim_interval FROM component",
   "20-ser_subsc.csv" => "SELECT subscription_id, line_item_id, start_date, subscription_length, length_type, renewal_date, auto_renewal, sici, normal_sici, upc, normal_upc, note FROM subscription",

   "21-ser_issues.csv" => "SELECT issue_id, component_id, enumchron, lvl1, lvl2, lvl3, lvl4, lvl5, lvl6, alt_lvl1, alt_lvl2, chron1, chron2, chron3, chron4, alt_chron, expected_date, receipt_date, received FROM serial_issues",

   "22-ser_claim.csv" => "SELECT claim_thread, issue_id, component_id, copy_id, location_id, claim_id, vendor_id, claim_type, claim_date, claim_count, override_claim_date, claim_status, op_id, note, edi_ref FROM serial_claim",

   "23-ser_vendor.csv" => "SELECT vendor_id, vendor_type, normal_vendor_type, vendor_code, normal_vendor_code, vendor_name, normal_vendor_name federal_tax_id, institution_id, default_currency, claim_interval, claim_count, cancel_interval, ship_via, create_date, create_opid, update_date, update_opid FROM vendor",

   "24-ser_vendaddr.csv" => "SELECT address_id, vendor_id, std_address_number, order_address, payment_address, return_address, claim_address, email_address, other_address, contact_name, contact_title, address_line1, address_line2, address_line3, address_line4, address_line5, city, state_province, zip_postal, country, modify_date, modify_operator_id FROM vendor_address",
   "25-ser_vendnote.csv" => "SELECT vendor_id, note FROM vendor_note",
   "26-ser_vendphone.csv" => "SELECT address_id, phone_type, phone_number, modify_date, modify_operator_id FROM vendor_phone",
   "27-ser_vw.csv" => "SELECT bib_id, mfhd_id, component_id, component_name, component_name_norm, predict, next_issue_id, note, issue_id, enumchron, expected_date, receipt_date, received from serials_vw",

   "28-ser_mfhd.csv" => "SELECT mfhd_data.mfhd_id, mfhd_data.seqnum, mfhd_data.record_segment
                         FROM mfhd_data 
                         LEFT JOIN serials_vw ON (mfhd_data.mfhd_id = serials_vw.mfhd_id) 
                         WHERE serials_vw.mfhd_id IS NOT NULL",
   "29-requests.csv" => "SELECT HOLD_RECALL.BIB_ID, HOLD_RECALL.PATRON_ID, HOLD_RECALL_ITEMS.ITEM_ID, HOLD_RECALL.REQUEST_LEVEL,
                         HOLD_RECALL_ITEMS.QUEUE_POSITION, HOLD_RECALL_STATUS.HR_STATUS_DESC, HOLD_RECALL_ITEMS.HOLD_RECALL_STATUS, HOLD_RECALL_ITEMS.HOLD_RECALL_STATUS_DATE,
                         HOLD_RECALL.CREATE_DATE, HOLD_RECALL.EXPIRE_DATE, HOLD_RECALL.PICKUP_LOCATION
                         FROM HOLD_RECALL
                         JOIN HOLD_RECALL_ITEMS ON (HOLD_RECALL_ITEMS.HOLD_RECALL_ID = HOLD_RECALL.HOLD_RECALL_ID)
                         JOIN HOLD_RECALL_STATUS ON (HOLD_RECALL_STATUS.HR_STATUS_TYPE = HOLD_RECALL_ITEMS.HOLD_RECALL_STATUS)
                         ORDER BY HOLD_RECALL_ITEMS.ITEM_ID, HOLD_RECALL_ITEMS.QUEUE_POSITION",
   "29a-locations.csv" => "SELECT location.location_id, location.location_code, location.location_name FROM location"
);


foreach my $key (sort keys %queries) {
  my $filename = $key ;
  my $query    = $queries{$key};

  print STDERR "$filename\n";
   
  my $header_row = $query;
  while ( $header_row =~ s/(select\s|,\s*)\s*convert\(([a-z0-9_]+),.*\)/$1$2/si ) {}
  $header_row =~ s/\s+/\t/g;
  $header_row =~ s/^\s*select\s+//i;
  $header_row =~ s/\tfrom\t.*//i;
  $header_row =~ s/,\t/,/g;
  $header_row =~ tr/A-Z/a-z/;
  $header_row =~ s/[a-z_]+\.([a-z])/$1/g;

  my $sth=$dbh->prepare($query) || die $dbh->errstr;
  $sth->execute() || die $dbh->errstr;

  my $i=0;
  #open my $out,">:encoding(UTF-8)",$filename || die "Can't open the output!";
  open my $out,">",$Exp::Config::config->{exportDir}.'/'.$filename || die "Can't open the output!";

  print $out "$header_row\n";

  while (my @line = $sth->fetchrow_array()) {
    $i++;

    use bytes;
    for ( my $j=0; $j <= $#line; $j++ ) {
      if ( defined($line[$j]) && !nv_is_utf8($line[$j]) ) {
        $line[$j] = nv_to_utf8($line[$j]);
      }
    }
    no bytes;

    if ( $anonymize ) {

      if ( $key eq "05-patron_addresses.csv" ) {
          # "SELECT PATRON_ADDRESS.PATRON_ID, PATRON_ADDRESS.ADDRESS_TYPE, PATRON_ADDRESS.ADDRESS_LINE1, 
          # PATRON_ADDRESS.ADDRESS_LINE2, PATRON_ADDRESS.ADDRESS_LINE3, PATRON_ADDRESS.ADDRESS_LINE4, 
          # PATRON_ADDRESS.ADDRESS_LINE5, PATRON_ADDRESS.CITY, PATRON_ADDRESS.STATE_PROVINCE, 
          # PATRON_ADDRESS.ZIP_POSTAL, PATRON_ADDRESS.COUNTRY
          if ( $line[1] eq '3' ) { # email
        $line[2] = 'etunimi.sukunimi@hamk.fi';
        # Nollaa muut kentat varmuuden vuoksi
        for ( my $k=3; $k <= $#line; $k++ ) {
            $line[$k] = '';
        }
          }
          else {
        if ( $line[2] ) { $line[2] = 'Katuosoite 1A'; }
        if ( $line[3] ) { $line[3] = 'Toinen osoiterivi'; }
        if ( $line[4] ) { $line[4] = 'Kolmas osoiterivi'; }
        if ( $line[5] ) { $line[5] = 'NeljC$s osoiterivi'; }
        if ( $line[6] ) { $line[6] = 'Viides osoiterivi'; }
        if ( $line[7] ) { $line[7] = 'HC$meenlinna'; }
        if ( $line[8] ) { $line[8] = 'HC$me'; }
        if ( $line[9] ) { $line[9] = '13100'; }
        if ( $line[10] ) { $line[10] = 'Suomi'; }
          }
      }
      if ( $key eq "07-patron_names_dates.csv" ) {
        # "SELECT PATRON.PATRON_ID, PATRON.LAST_NAME, PATRON.FIRST_NAME, PATRON.MIDDLE_NAME, 
        # PATRON.CREATE_DATE, PATRON.EXPIRE_DATE, PATRON.INSTITUTION_ID
        if ( $line[1] ) { $line[1] = 'Doe'; }
        if ( $line[2] ) {
          $line[2] = 'John';
          if ( $line[6] && $line[6] =~ /\-\d\d[02468].$/ ) {
            $line[2] = 'Jane';
          }
        }
        if ( $line[3] ) {
          my $tmp = $line[0]%25;
          $line[3] = chr($tmp+65).".";
        }
        if ( $line[6] ) {
          $line[6] =~ s/\d\d(\d).$/00${1}0/;
          my $tmp = '0104'.int(rand(30)+70);
          $line[6] =~ s/^....../$tmp/;
        }
        if ( $line[9] ) { #ssn aka institution_id
          $line[9] =~ s/\d/1/gsm;
        }
        if ( $line[10] ) { #BIRTH_DATE
          $line[10] =~ s/\d/1/gsm;
        }
      }

      if ( $key eq "09-patron_notes.csv" ) {
        # SELECT patron_notes.patron_id,patron_notes.note FROM patron_notes 
        my $new_note = '';
        my $old_line = $line[1];
        while ( $line[1] ) {
          if ( $line[1] =~ s/^\d// ) {
            $new_note .= int(rand(10));
          }
          elsif ( $line[1] =~ s/^(\s+|[;.\-,:])// ) {
            $new_note .= $1;
          }
          elsif ( $line[1] =~ s/^\p{Ll}// ) {
            $new_note .= chr(97+int(rand(25)));
          }
          elsif ( $line[1] =~ s/.// ) {
            $new_note .= chr(65+int(rand(25)));
          }
          if ( $old_line eq $line[1] ) {
            $line[1] = 'ABORT';
          }
        }
        $line[1] = $new_note;
      }

      if ( $key eq "10-patron_phones.csv" ) {
        # "SELECT patron_address.patron_id,
        # phone_type.phone_desc, patron_phone.phone_number
        my $new_note = '';
        if ( $line[2] =~ s/^(\+358|040|09|044|050)// ) {
          $new_note = $1;
        }
        while ( $line[2] ) {
          if ( $line[2] =~ s/^\d// ) {
            $new_note .= int(rand(10));
          }
          elsif ( $line[2] =~ s/^(.)// ) {
            $new_note .= $1;
          }
        }
        $line[2] = $new_note;
      }

      if ( $key eq "12-current_circ.csv" ) {
        # "SELECT patron_barcode.patron_barcode, patron.institution_id,circ_transactions.patron_id,
        # item_barcode.item_barcode,
        # circ_transactions.charge_date,circ_transactions.current_due_date,
        # circ_transactions.renewal_count

        if ( 0 && $line[1] ) { # tässä oli ennen patron.institution_id
          $line[1] =~ s/\d\d(\d).$/00${1}0/;
          my $tmp = '0104'.int(rand(30)+70);
          $line[1] =~ s/^....../$tmp/;
        }
      }
    }
    print "."    unless ($i % 10);
    print "\r$i" unless ($i % 100);
    for my $k (0..scalar(@line)-1) {
      if ($line[$k]) {
        $line[$k] =~ s/"/'/g;
        if ($line[$k] =~ /,/) {
          print {$out} '"'.$line[$k].'"';
        }
        else {
          print {$out} $line[$k];
        }
      }
      print {$out} ',';
    }
    print {$out} "\n";
  }

  close $out;
  print "\n\n$i records exported\n";
}

return 1;
