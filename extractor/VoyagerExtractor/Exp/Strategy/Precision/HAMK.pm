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

package Exp::Strategy::Precision::HAMK;

#Pragmas
use warnings;
use strict;
use utf8; #This file and all Strings within are utf8-encoded
binmode( STDOUT, ":encoding(UTF-8)" );
binmode( STDIN,  ":encoding(UTF-8)" );
$|=1;

use Data::Dumper;

=head2 NAME

Exp::Strategy::Precision::HAMK - Precisely export what is needed for HAMK. (Except MARC)

=head2 DESCRIPTION

Export all kinds of data from Voyager using the given precision SQL.

=cut

my $nowYear = 1900 + (localtime)[5];
my $boundBibsStartId = 2000000;

our %queries = (
  "00-bib_sub_frequency.csv" => {
    uniqueKey => 0,
    sql =>
      "SELECT    line_item.bib_id, frequency.freq_increment, frequency.freq_calc_type            \n".
      "FROM      line_item                                                                       \n".
      "LEFT JOIN subscription ON (subscription.line_item_id = line_item.line_item_id)            \n".
      "LEFT JOIN component ON (component.subscription_id = subscription.subscription_id)         \n".
      "LEFT JOIN component_pattern ON (component_pattern.component_id = component.component_id)  \n".
      "LEFT JOIN frequency ON (frequency.frequency_code = component_pattern.frequency_code)      \n".
      "WHERE     line_item.line_item_id = ( SELECT MAX(flatli.line_item_id)                      \n". #There might be biblios with subscriptions with multiple different frequencies.
      "                                     FROM   line_item flatli                              \n". #Flatten such duplicate frequencies to pick the value from the newest order.
      "                                     WHERE  flatli.bib_id = line_item.bib_id              \n".
      "                                   )                                                      \n".
      "",
  },
  "00-bib_text.csv" => {
    uniqueKey => 0,
    sql =>
      "SELECT    bib_text.bib_id, bib_text.begin_pub_date                  \n".
      "FROM      bib_text                                                  \n".
      "",
  },
  "00-mfhd_master.csv" => {
    uniqueKey => 0,
    sql =>
      "SELECT    mfhd_master.mfhd_id, mfhd_master.display_call_no                                 \n".
      "FROM      mfhd_master                                                                      \n".
      "",
  },
  "00c-bound_bibs-bib_to_parent.csv" => {
    uniqueKey => -1,
    columnNames => ['bib_item.bound_bib_id', 'bib_item.bound_parent_bib_id'], #Cannot parse the extractable column names or aliases for this SQL reasonably without using external SQL parsing libraries.
    sql =>
      "SELECT    bound_bib_ids,                                                                   \n".
      "          (SELECT MAX(bib_id) FROM bib_master) + 10000 +                                   \n". # - Reserve bib_ids for the soon-to-be-created bound bib parent records.
      "              ROW_NUMBER() OVER (ORDER BY bound_bib_ids                                    \n". #   Pick the latest used bib_id in the DB, add a safety buffer of 10000
      "          ) as new_parent_bib_id                                                           \n". #   and add 1 for each deduplicated biblio group.
      "FROM      (SELECT    LISTAGG(bib_item.bib_id, ',') WITHIN GROUP (ORDER BY bib_item.bib_id) \n". # - GROUP_CONCAT bib_ids that share the same item,
      "                         as bound_bib_ids                                                  \n". #   this returns duplicate bib_id-group-rows for each bound item
      "           FROM      bib_item                                                              \n".
      "           LEFT JOIN ( SELECT   bib_item.item_id, COUNT(bib_item.bib_id) as bibs_count     \n". # - Select the count of linked biblios for this item
      "                       FROM     bib_item                                                   \n".
      "                       GROUP BY bib_item.item_id                                           \n".
      "                     ) multi_bibious ON (multi_bibious.item_id = bib_item.item_id)         \n".
      "           WHERE     multi_bibious.bibs_count > 1                                          \n". # - Only include items/bibs that are bound
      "           GROUP BY  bib_item.item_id                                                      \n". # - First layer of flattening, concatenate all bib_id's this item links to
      "          )                                                                                \n".
      "GROUP BY bound_bib_ids                                                                     \n". # - Flatten duplicate bib_id-groups, now we have a group of bibs that need a parent bound record only once for all items they have
      "",
    postprocessor => sub {
      my ($row) = @_;
      my @bib_ids = split(',',$row->[0]);         # Split the bound_bib_ids-list
      @bib_ids = map {[$_, $row->[1]]} @bib_ids;  # Make new rows from each bib_id and append the reserved bound parent record bib_id
      return \@bib_ids;
    },
  },
  "00-suppress_in_opac_map.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => -1,
    sql =>
      "SELECT    bib_master.bib_id, NULL as mfhd_id, NULL as location_id,  \n".
      "          bib_master.suppress_in_opac                               \n".
      "FROM      bib_master                                                \n".
      "WHERE     suppress_in_opac = 'Y'                                    \n".
      "                                                                    \n".
      "UNION                                                               \n".
      "                                                                    \n".
      "SELECT    NULL as bib_id, mfhd_master.mfhd_id, NULL as location_id, \n".
      "          mfhd_master.suppress_in_opac                              \n".
      "FROM      mfhd_master                                               \n".
      "WHERE     suppress_in_opac = 'Y'                                    \n".
      "                                                                    \n".
      "UNION                                                               \n".
      "                                                                    \n".
      "SELECT    NULL as bib_id, NULL as mfhd_id, location.location_id,    \n".
      "          location.suppress_in_opac                                 \n".
      "FROM      location                                                  \n".
      "WHERE     suppress_in_opac = 'Y'                                    \n",
  },
  "02-items.csv" => {
    uniqueKey => 0,
    sql =>
      "SELECT    item.item_id,                                                                          \n".
      "          bib_item.bib_id, bibi.add_date, multi_bibious.bibs_count,                              \n".
      "          mfhd_item.mfhd_id, multi_holdacious.holdings_count,                                    \n".
      "          item_vw.barcode, item.perm_location, item.temp_location,                               \n".
      "          item.item_type_id, item.temp_item_type_id,                                             \n".
      "          mfhd_item_conversion.enumeration, mfhd_item_conversion.chronology,                     \n".
      "          item_vw.historical_charges,                                                            \n".
      "          item_vw.call_no, item_vw.call_no_type,                                                 \n".
      "          item.price, item.copy_number, item.pieces                                              \n".
      "FROM      item_vw                                                                                \n".
      "LEFT JOIN item               ON (item_vw.item_id = item.item_id)                                 \n".
      "LEFT JOIN ( SELECT   mfhd_item.item_id, MIN(mfhd_item.mfhd_id) as mfhd_id                        \n". #Of all the Holdings records attached to this Item, pick the oldest one.
      "            FROM     mfhd_item                                                                   \n".
      "            GROUP BY mfhd_item.item_id                                                           \n".
      "          ) mfhd_item        ON (mfhd_item.item_id = item_vw.item_id)                            \n".
      "LEFT JOIN ( SELECT   mfhd_item.item_id, COUNT(mfhd_item.mfhd_id) as holdings_count               \n". # Select the count of related holdings for this item, this is a strong indication that we are working with bound records. Such Items are dealt with elsewhere.
      "            FROM     mfhd_item                                                                   \n".
      "            GROUP BY mfhd_item.item_id                                                           \n".
      "          ) multi_holdacious ON (multi_holdacious.item_id = item_vw.item_id)                     \n".
      "LEFT JOIN ( SELECT   bib_item.item_id, MIN(bib_item.bib_id) as bib_id                            \n". #Of all the Bibliographic records attached to this Item, pick the oldest one.
      "            FROM     bib_item                                                                    \n".
      "            GROUP BY bib_item.item_id                                                            \n".
      "          ) bib_item         ON (bib_item.item_id = item_vw.item_id)                             \n".
      "LEFT JOIN bib_item bibi      ON (bibi.bib_id  = bib_item.bib_id AND                              \n". # We must first choose the bib_id we want to include here, then choose information related to the bib. It is either an extra join or a single deeply nested subqueries join
      "                                 bibi.item_id = item_vw.item_id)                                 \n".
      "LEFT JOIN ( SELECT   bib_item.item_id, COUNT(bib_item.bib_id) as bibs_count                      \n". # Select the count of related biblios for this item, this is a strong indication that we are working with bound records. Such Items are dealt with elsewhere.
      "            FROM     bib_item                                                                    \n".
      "            GROUP BY bib_item.item_id                                                            \n".
      "          ) multi_bibious ON (multi_bibious.item_id = item_vw.item_id)                           \n".
      "LEFT JOIN ( SELECT mfhd_item.item_id, mfhd_item.chron as chronology,                             \n".
      "                   mfhd_item.item_enum as enumeration                                            \n".
      "            FROM mfhd_item                                                                       \n".
      "          ) mfhd_item_conversion ON (mfhd_item_conversion.item_id = item_vw.item_id)                                 \n".
      "",
  },
  "02-items_last_borrow_date.csv" => { #This needs to be separate from the 02-items.csv, because otherwise Oracle drops Item-rows with last_borrow_date == NULL, even if charge_date is NULL in both the comparator and the comparatee.
    uniqueKey => 0,
    sql =>
      #
      # Pick last checkin location normally from the old issues table.
      #
      "SELECT item_id, max(last_borrow_date) as last_borrow_date FROM                                \n".
      "(                                                                                             \n".
      "SELECT    circ_trans_archive.item_id, max(circ_trans_archive.charge_date) as last_borrow_date \n".
      "FROM      circ_trans_archive                                                                  \n".
      "LEFT JOIN item ON (circ_trans_archive.item_id = item.item_id)                                 \n".
      "WHERE     circ_trans_archive.charge_date IS NOT NULL                                          \n".
      "      AND item.item_id IS NOT NULL                                                            \n".
      "GROUP BY  circ_trans_archive.item_id                                                          \n".
      "                                                                                              \n".
      "UNION                                                                                         \n".
      "                                                                                              \n".
      #
      # Voyager doesn't add a circ_trans_archive-row when the item which is "IN TRANSIT ON HOLD" arrives to the pickup location.
      # One must know to infer that such Items that are waiting for pickup must naturally be in the correct pickup location.
      #
      "SELECT    hold_recall_items.item_id, hold_recall_items.hold_recall_status_date as last_borrow_date \n".
      "FROM      hold_recall_items                                                                        \n".
      "WHERE     hold_recall_items.hold_recall_status = 2    \n". # 2 = 'Pending'. In Voyager-speak this is a hold which is waiting for pickup.
      "                                                      \n".
      ")                                                                                             \n".
      "GROUP BY item_id                                                                              \n".
      "ORDER BY  item_id ASC                                                                         \n".
      "",
  },
  "02a-item_notes.csv" => {
    uniqueKey => -1, #One Item can have multiple item_notes and there is no unique key in the item_notes table
    anonymize => {"item_note" => "scramble"},
    sql =>
      "SELECT    item_note.item_id, item_note.item_note, item_note.item_note_type, item_note_type.note_desc
       FROM      item_note
       LEFT JOIN item_note_type ON (item_note_type.note_type = item_note.item_note_type)",
  },
  "02-item_status.csv" => {
    uniqueKey => -1, #Each Item can have multiple afflictions
    sql =>
      "SELECT    item_status.item_id, item_status.item_status, item_status_type.item_status_desc, \n".
      "          item_status.item_status_date \n".
      "FROM      item_status \n".
      "JOIN      item_status_type ON (item_status.item_status = item_status_type.item_status_type) \n".
      "ORDER BY  item_status.item_id ASC ",
  },
  "02b-item_stats.csv" => { #Statistical item tags
    uniqueKey => -1, #One Item can have many statistical categories
    sql =>
      "SELECT    item_stats.item_id, item_stats.item_stat_id, item_stat_code.item_stat_code
       FROM      item_stats
       JOIN      item_stat_code ON (item_stats.item_stat_id = item_stat_code.item_stat_id)
       ORDER BY  item_stats.date_applied ASC", #Sort order is important so we can know which row is the newest one
  },
  "03-transfers.csv" => {
    uniqueKey => 0,
    sql =>
      # (In Transit On Hold) - Transfers for reserve fulfillment
      "
      SELECT item.item_id, item_status.item_status,
             item_status.item_status_date, circ_trans_archive.discharge_date,
             circ_trans_archive.discharge_location,
             hold_recall.pickup_location as to_location,
             NULL AS call_slip_id
      FROM   item
      LEFT JOIN item_status       ON item_status.item_id        = item.item_id
      LEFT JOIN circ_trans_archive ON circ_trans_archive.item_id = item.item_id
      LEFT JOIN hold_recall_items ON hold_recall_items.item_id  = item.item_id
      LEFT JOIN hold_recall       ON hold_recall.hold_recall_id = hold_recall_items.hold_recall_id
      WHERE  item_status.item_status = 10
         AND hold_recall_items.hold_recall_status > 1
         AND ( TRUNC(circ_trans_archive.discharge_date) = TRUNC(item_status.item_status_date)
               OR
               circ_trans_archive.circ_transaction_id = (SELECT MAX(circ_transaction_id) FROM circ_trans_archive WHERE item_id = item.item_id)
               OR
               circ_trans_archive.circ_transaction_id IS NULL
             )

      UNION
      ".
      # (In Transit Discharged) - Transfers for check-ins travelling home
      "
      SELECT item.item_id, item_status.item_status,
             item_status.item_status_date, circ_trans_archive.discharge_date,
             circ_trans_archive.discharge_location,
             item.perm_location as to_location,
             NULL AS call_slip_id
      FROM   item
      LEFT JOIN item_status        ON item_status.item_id        = item.item_id
      LEFT JOIN circ_trans_archive ON circ_trans_archive.item_id = item.item_id
      WHERE  item_status.item_status = 9
         AND ( TRUNC(circ_trans_archive.discharge_date) = TRUNC(item_status.item_status_date)
               OR
               circ_trans_archive.circ_transaction_id = (SELECT MAX(circ_transaction_id) FROM circ_trans_archive WHERE item_id = item.item_id)
               OR
               circ_trans_archive.circ_transaction_id IS NULL
             )

      UNION
      ".
      # (In Transit) - Transfers ???
      "
      SELECT item.item_id, item_status.item_status,
             item_status.item_status_date, circ_trans_archive.discharge_date,
             circ_trans_archive.discharge_location,
             item.perm_location as to_location,
             NULL AS call_slip_id
      FROM   item
      LEFT JOIN item_status       ON item_status.item_id        = item.item_id
      LEFT JOIN circ_trans_archive ON circ_trans_archive.item_id = item.item_id
      WHERE  item_status.item_status = 8
         AND ( TRUNC(circ_trans_archive.discharge_date) = TRUNC(item_status.item_status_date)
               OR
               circ_trans_archive.circ_transaction_id = (SELECT MAX(circ_transaction_id) FROM circ_trans_archive WHERE item_id = item.item_id)
               OR
               circ_trans_archive.circ_transaction_id IS NULL
             )
      ",
  },
  "05-patron_addresses.csv" => {
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
    uniqueKey => 0,
    anonymize => {last_name => "surname",    first_name => "firstName",
                  middle_name => "scramble", institution_id => "ssn",
                  patron_pin => "scramble",  birth_date => "date"},
    sql =>
      "SELECT    patron.patron_id,
                 patron.last_name, patron.first_name, patron.middle_name, patron.title,
                 patron.create_date, patron.expire_date, patron.home_location,
                 patron.registration_date,
                 patron.patron_pin,
                 patron.institution_id, patron.birth_date
       FROM      patron
       ORDER BY  patron.patron_id",
  },
  "09-patron_notes.csv" => {
    uniqueKey => 0,
    anonymize => {note => 'scramble'},
    sql =>
      "SELECT    patron_notes.patron_note_id,                                                       \n".
      "          patron_notes.patron_id, patron_notes.note, patron_notes.note_type,                 \n".
      "          patron_notes.modify_date                                                           \n". #Modify date is used by some other external tooling. Do not remove it.
      "FROM      patron_notes                                                                       \n".
      "ORDER BY  patron_notes.patron_id, patron_notes.modify_date                                   \n".
      "",
  },
  "10-patron_phones.csv" => {
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
    uniqueKey => -1, #One patron can have many afflictions
    sql =>
      "SELECT    patron_stats.patron_id, patron_stats.patron_stat_id, patron_stat_code.patron_stat_code, patron_stats.date_applied
       FROM      patron_stats
       LEFT JOIN patron_stat_code ON (patron_stat_code.patron_stat_id = patron_stats.patron_stat_id)",
  },
  "12-current_circ.csv" => {
    uniqueKey => 0,
    sql =>
      "SELECT    circ_transactions.circ_transaction_id,                                       \n".
      "          circ_transactions.patron_id, patron_barcode.patron_barcode,                  \n".
      "          circ_transactions.item_id, item_barcode.item_barcode,                        \n".
      "          circ_transactions.charge_date, circ_transactions.current_due_date,           \n".
      "          circ_transactions.renewal_count, circ_transactions.charge_location,          \n".
      "          item_barcode.barcode_status, patron_barcode.barcode_status                   \n". #barcode statuses are not needed, but are helpful in debugging and understanding duplications
      "FROM      circ_transactions                                                            \n".
      "JOIN      patron             ON (circ_transactions.patron_id=patron.patron_id)         \n".
      "LEFT JOIN patron_barcode     ON (circ_transactions.patron_id=patron_barcode.patron_id) \n".
      "LEFT JOIN item_barcode       ON (circ_transactions.item_id=item_barcode.item_id)       \n".
      "WHERE     item_barcode.item_barcode = (                                                \n". #Pick only one barcode
      "              SELECT ib_union.item_barcode FROM (                                      \n". #Preferably the active one
      "                  SELECT   ib.item_barcode                                             \n".
      "                  FROM     item_barcode ib                                             \n".
      "                  WHERE    ib.item_id = circ_transactions.item_id                      \n".
      "                     AND   ib.barcode_status = 1                                       \n".
      "                  UNION                                                                \n".
      "                  SELECT   ib.item_barcode                                             \n". #But if unavailable pick the most recent one
      "                  FROM     item_barcode ib                                             \n".
      "                  WHERE    ib.item_id = circ_transactions.item_id                      \n".
      "                     AND   ib.item_id != (                                             \n". #the same item can have barcodes with multiple statuses,
      "                               SELECT ib2.item_id                                      \n". #including 1 == 'Available'
      "                               FROM   item_barcode ib2                                 \n". #Make sure we include alternative statuses only
      "                               WHERE  ib2.item_id = circ_transactions.item_id          \n". #if no barcode is 'Available'
      "                                  AND ib2.barcode_status = 1                           \n". #without this, barcodes having multiple statuses cause duplicate rows
      "                           )                                                           \n".
      "                  FETCH FIRST 1 ROWS ONLY                                              \n".
      "              ) ib_union                                                               \n".
      "              FETCH FIRST 1 ROWS ONLY                                                  \n".
      "          )                                                                            \n".
      "      AND patron_barcode.patron_barcode = (                                            \n". #Pick only one barcode
      "              SELECT pb_union.patron_barcode FROM (                                    \n". #Preferably the active one
      "                  SELECT   pb.patron_barcode                                           \n".
      "                  FROM     patron_barcode pb                                           \n".
      "                  WHERE    pb.patron_id = circ_transactions.patron_id                  \n".
      "                     AND   pb.barcode_status = 1                                       \n".
      "                  UNION                                                                \n".
      "                  SELECT   pb.patron_barcode                                           \n". #But if unavailable pick the most recent one
      "                  FROM     patron_barcode pb                                           \n".
      "                  WHERE    pb.patron_id = circ_transactions.patron_id                  \n".
      "                     AND   pb.patron_id != (                                           \n". #the same patron can have barcodes with multiple statuses,
      "                               SELECT pb2.patron_id                                    \n". #including 1 == 'Available'.
      "                               FROM   patron_barcode pb2                               \n". #Make sure we include alternative statuses only
      "                               WHERE  pb2.patron_id = circ_transactions.patron_id      \n". #if no barcode is 'Available'.
      "                                  AND pb2.barcode_status = 1                           \n". #Without this, barcodes having multiple statuses cause duplicate rows.
      "                           )                                                           \n". #However - There is nothing I can do, if the Patron has the same
      "                  FETCH FIRST 1 ROWS ONLY                                              \n". #barcode with different statuses, as those cannot be distinguished.
      "              ) pb_union                                                               \n". #These duplicates are caught by the deduplication mechanism
      "              FETCH FIRST 1 ROWS ONLY                                                  \n". #and cause deduplication warnings.
      "          )                                                                            \n".
      "                                                                                       \n",
  },
  "12a-current_circ_last_renew_date.csv" => { #Same as 02-items_last_borrow_date.csv
    uniqueKey => 0,
    sql =>
      "SELECT    renew_transactions.circ_transaction_id, max(renew_transactions.renew_date) as last_renew_date \n".
      "FROM      renew_transactions \n".
      "WHERE     renew_transactions.renew_date IS NOT NULL \n".
      "GROUP BY  renew_transactions.circ_transaction_id \n".
      "ORDER BY  renew_transactions.circ_transaction_id ASC \n",
  },
  "14-fines.csv" => {
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
    uniqueKey => [0, 1], #Check later that each component has only one location for received items.
    sql =>
      "SELECT    issues_received.component_id, issues_received.location_id
       FROM      issues_received
       GROUP BY  issues_received.component_id, issues_received.location_id
       ORDER BY  issues_received.component_id ASC, issues_received.location_id ASC",
  },

  #Migrate only the serial numbers (predicted or received) up until the end of the current year. As the Koha's serials-module takes over then.
  #TODO: Cannot know how many physical serial magazines are expected to be received for non-received serial numbers.
  #      So serial issues that need to be received after going live, need to be added as supplements as there is only one item/magazine in Koha subscription ready to be received.
  "21-ser_issues.csv" => {
    #uniqueKey => [0, 1, 3], #as item_id can be null or 0, this causes a lot of false positive warnings, so just disable uniqueness checks.
    uniqueKey => -1,
    sql =>
      "SELECT    serial_issues.issue_id, serial_issues.component_id,
                 line_item.bib_id, issues_received.item_id,
                 serial_issues.enumchron, serial_issues.lvl1, serial_issues.lvl2, serial_issues.lvl3,
                 serial_issues.lvl4, serial_issues.lvl5, serial_issues.lvl6, serial_issues.alt_lvl1,
                 serial_issues.alt_lvl2, serial_issues.chron1, serial_issues.chron2, serial_issues.chron3,
                 serial_issues.chron4, serial_issues.alt_chron,
                 serial_issues.expected_date, serial_issues.receipt_date, serial_issues.received,

                 issues_received.location_id as received_location_id, issues_received.receipt_date as received_receipt_date,
                 issues_received.opac_suppressed, issues_received.note as received_note, issues_received.collapsed
       FROM      serial_issues
       LEFT JOIN component       ON (component.component_id = serial_issues.component_id)
       LEFT JOIN subscription    ON (subscription.subscription_id = component.subscription_id)
       LEFT JOIN line_item       ON (subscription.line_item_id = line_item.line_item_id)
       LEFT JOIN issues_received ON (issues_received.issue_id = serial_issues.issue_id AND issues_received.component_id = serial_issues.component_id)
       WHERE     EXTRACT(YEAR FROM serial_issues.expected_date) <= $nowYear
       ORDER BY  serial_issues.component_id ASC, serial_issues.issue_id ASC",
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
    # Multiple holds with the same primary key? This is a parallel hold which is fulfillable by any of the reserved items.
    # TODO: This feature is something that needs to be implemented in Koha first. For the time being, let the extractor complain about it so we wont forget.
    # TODO: Apparently Voyager implements parallel hold queus via this mechanism, where the hold is targeted to items available via one of the parallel hold queues.
    uniqueKey => 0,
    sql =>
      # SELECT Item-level holds.
      # hold_recall.hold_recall_type can be either 'H' = Hold or 'R' = Recall. This is further validated in the transformer. Currently these have no impact as their exact behaviour is unknown.
      #
      "SELECT * FROM                                                                                                                        \n".
      "(                                                                                                                                    \n".
      "  SELECT    hold_recall.hold_recall_id,                                                                                              \n".
      "            hold_recall.bib_id, hold_recall.patron_id, hold_recall_items.item_id,                                                    \n".
      "            hold_recall.request_level, hold_recall_items.queue_position,                                                             \n".
      "            hold_recall_status.hr_status_desc, hold_recall_items.hold_recall_status, hold_recall.hold_recall_type,                   \n".
      "            hold_recall.create_date, hold_recall.expire_date, hold_recall.pickup_location,                                           \n".
      "            hold_recall_items.hold_recall_status_date, NULL AS linked_hold_or_circ                                                   \n".
      "  FROM      hold_recall                                                                                                              \n".
      "  LEFT JOIN hold_recall_items  on (hold_recall_items.hold_recall_id = hold_recall.hold_recall_id)                                    \n".
      "  LEFT JOIN hold_recall_status on (hold_recall_status.hr_status_type = hold_recall_items.hold_recall_status)                         \n".
      "  WHERE     hold_recall.request_level = 'C'                                                                                          \n". # C stands for "Cunning stunts"
#      "  ORDER BY  hold_recall.hold_recall_id, hold_recall_items.item_id, hold_recall_items.queue_position                                  \n".
#      "",
#    sql =>
      "  UNION ALL                                                                                                                          \n".
      "                                                                                                                                     \n".
      # SELECT (T)itle-level holds. They have multiple hold_recall_item-rows, each pointing to all items that can be used to satisfy the hold.
      # For some reason, individual hold_recall_item-rows within a Title-level hold can have inconsistent queue_positions.
      # These are converted to Koha as bibliographic level holds, satisfiable by any item.
      #
      # Apparently it is possible to have holds for biblios which have no available items. This is checked in the transformation phase with proper validation errors.
      #
      # When a Title-level hold is caught and waiting for pickup, the status is 'Pending' and all the other hold_recall_items-rows aside the Item in the shelf are removed.
      # So caught Title-level holds have only one hold_recall_item-row.
      #
      "  SELECT    hold_recall.hold_recall_id,                                                                                              \n".
      "            hold_recall.bib_id, hold_recall.patron_id, hold_recall_items.item_id,                                                    \n".
      "            hold_recall.request_level, hold_recall_items.queue_position,                                                             \n".
      "            hold_recall_status.hr_status_desc, hold_recall_items.hold_recall_status, hold_recall.hold_recall_type,                   \n".
      "            hold_recall.create_date, hold_recall.expire_date, hold_recall.pickup_location,                                           \n".
      "            hold_recall_items.hold_recall_status_date, NULL AS linked_hold_or_circ                                                   \n".
      "  FROM      hold_recall                                                                                                              \n".
      "  LEFT JOIN ( SELECT   hold_recall_items.hold_recall_id, MIN(hold_recall_items.item_id) AS item_id,                                  \n". #In MariaDB/MySQL one would simply GROUP BY queue_position instead of 7 rows of SQL, but now there are less unintended side-effects. Give and take.
      "                       hold_recall_items.queue_position, hold_recall_items.hold_recall_status,                                       \n".
      "                       hold_recall_items.hold_recall_status_date                                                                     \n".
      "              FROM     hold_recall_items                                                                                             \n".
      "              WHERE    hold_recall_items.queue_position = ( SELECT MIN(hri.queue_position)                                           \n".
      "                                                            FROM   hold_recall_items hri                                             \n".
      "                                                            WHERE  hri.hold_recall_id = hold_recall_items.hold_recall_id             \n".
      "                                                          )                                                                          \n".
      "              GROUP BY hold_recall_items.hold_recall_id, hold_recall_items.queue_position, hold_recall_items.hold_recall_status,     \n".
      "                       hold_recall_items.hold_recall_status_date                                                                     \n".
      "            ) hold_recall_items ON (hold_recall_items.hold_recall_id = hold_recall.hold_recall_id)                                   \n".
      "  LEFT JOIN hold_recall_status on (hold_recall_status.hr_status_type = hold_recall_items.hold_recall_status)                         \n".
      "  WHERE     hold_recall.request_level = 'T'                                                                                          \n". # T stands for Title-level hold
#      "  ORDER BY  hold_recall.hold_recall_id, hold_recall_items.queue_position                                                             \n".
#      "",
#    sql =>
      "  UNION ALL                                                                                                                          \n".
      "                                                                                                                                     \n".
      # Turn call_slip -requests into compatible hold_recall-entries
      #
      # When the call_slip -requests becomes Fulfilled, a hold_recall-row is generated.
      # When the specific Item is checked out to the specific Patron, the Fulfilled-status remains, but the hold_recall is closed.
      #
      "  SELECT    call_slip.call_slip_id,                                                                                                  \n". #call_slip_id might collide with hold_recall_id. If this is the case, add 1000000 here.
      "            call_slip.bib_id, call_slip.patron_id, call_slip.item_id,                                                                \n".
      "            'C' AS request_level, 1 AS queue_position,                                                                               \n".
      "            call_slip_status_type.status_desc AS hr_status_desc, call_slip.status AS hold_recall_status, 'CS' AS hold_recall_type,   \n".
      "            call_slip.date_requested AS create_date, NULL AS expire_date, call_slip.pickup_location_id AS pickup_location,           \n".
      "            call_slip.status_date AS hold_recall_status_date,                                                                        \n".
      "            CASE                                                                                                                     \n".
      "              WHEN hold_recall.hold_recall_id IS NOT NULL            THEN 'Hold:'||hold_recall.hold_recall_id                        \n". # linked_hold_or_circ tells the call_slip -hold if there is an attached hold already, so we don't create duplicate holds.
      "              WHEN circ_transactions.circ_transaction_id IS NOT NULL THEN 'Circ:'||circ_transactions.circ_transaction_id             \n". #   if there are circulations, but no hold, then this call slip has resolved it's hold-related functionality
      "              ELSE NULL                                                                                                              \n".
      "            END AS linked_hold_or_circ                                                                                               \n".
      "  FROM      call_slip                                                                                                                \n".
      "  LEFT JOIN call_slip_status_type ON (call_slip.status       = call_slip_status_type.status_type)                                    \n".
      "  LEFT JOIN hold_recall           ON (call_slip.call_slip_id = hold_recall.call_slip_id)                                             \n".
      "  LEFT JOIN circ_transactions     ON (call_slip.patron_id = circ_transactions.patron_id AND                                          \n". # There is no direct link between a hold_recall|call_slip, but we can be pretty certain that a combination of
      "                                      call_slip.item_id = circ_transactions.item_id                                                  \n". # having the same patron and item
      #"                                      AND TRUNC(call_slip.status_date) = TRUNC(circ_transactions.charge_date)                        \n". # (requiring the same checkout day is not necessary)
      "                                     )                                                                                               \n". # is a pretty strong quarantee that the attached circ_transaction satisfied the hold_recall.
#      "  ORDER BY  call_slip.call_slip_id, call_slip.item_id                                                                                \n".
#      "",
      ")                                                                                                                                    \n".
      "ORDER BY  hold_recall_id, queue_position, item_id                                                                                    \n".
      "",
    sql_get_all_holds_rows => #Legacy SQL, just for reference to help debug future issues
      "SELECT    hold_recall.hold_recall_id,                                                                                                \n".
      "          hold_recall.bib_id, hold_recall.patron_id, hold_recall_items.item_id as item_id,                                           \n".
      "          hold_recall.request_level, hold_recall_items.queue_position,                                                               \n".
      "          hold_recall_status.hr_status_desc, hold_recall_items.hold_recall_status, hold_recall.hold_recall_type,                     \n".
      "          hold_recall.create_date, hold_recall.expire_date, hold_recall.pickup_location                                              \n".
      "          hold_recall_items.hold_recall_status_date                                                                                  \n".
      "FROM      hold_recall                                                                                                                \n".
      "LEFT JOIN hold_recall_items  on (hold_recall_items.hold_recall_id = hold_recall.hold_recall_id)                                      \n".
      "LEFT JOIN hold_recall_status on (hold_recall_status.hr_status_type = hold_recall_items.hold_recall_status)                           \n".
      "ORDER BY  hold_recall.hold_recall_id, hold_recall_items.item_id, hold_recall_items.queue_position                                    \n".
      "",
  },
);

1;
