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
  "00-suppress_in_opac_map.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => -1,
    sql =>
      "SELECT    bib_heading.bib_id, NULL as mfhd_id, NULL as location_id, \n".
      "          bib_heading.suppress_in_opac                              \n".
      "FROM      bib_heading                                               \n".
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
      "SELECT    item.item_id,
                 bib_item.bib_id, bib_item.add_date,
                 item_vw.barcode, item.perm_location, item.temp_location, item.item_type_id, item.temp_item_type_id,
                 item_vw.enumeration, item_vw.chronology, item_vw.historical_charges, item_vw.call_no,
                 item_vw.call_no_type,
                 item.price, item.copy_number, item.pieces
       FROM      item_vw
       JOIN      item               ON (item_vw.item_id = item.item_id)
       JOIN      bib_item           ON (item_vw.item_id = bib_item.item_id)
       JOIN      (
                  SELECT bib_item.item_id,
                  COUNT(item_id)
                  FROM bib_item
                  GROUP BY bib_item.item_id
                  HAVING COUNT(item_id) = 1) filtered_items ON (filtered_items.item_id = item.item_id)" #items with multiple bib_item-rows are related to bound bibs which are to be imported separately. 
  },
  "02-items_last_borrow_date.csv" => { #This needs to be separate from the 02-items.csv, because otherwise Oracle drops Item-rows with last_borrow_date == NULL, even if charge_date is NULL in both the comparator and the comparatee.
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

      UNION
      ".
    #sql =>
      # Call slips in transfer
      "                                                                                                                  \n".
      "SELECT    item.item_id, item_status.item_status,                                                                  \n".
      "          item_status.item_status_date, circ_trans_archive.discharge_date,                                        \n".
      "          circ_trans_archive.discharge_location,                                                                  \n". # call_slip.location_id might be a good substitute for this.
      "          call_slip.pickup_location_id as to_location,                                                            \n".
      "          call_slip.call_slip_id                                                                                  \n". # This is a call_slip request related transfer
      "FROM      call_slip                                                                                               \n".
      "LEFT JOIN call_slip_status_type ON (call_slip.status       = call_slip_status_type.status_type)                   \n".
      "LEFT JOIN hold_recall           ON (call_slip.call_slip_id = hold_recall.call_slip_id)                            \n".
      "LEFT JOIN circ_transactions     ON (call_slip.patron_id          = circ_transactions.patron_id AND                \n". # There is no direct link between a hold_recall|call_slip, but we can be pretty certain that a combination of
      "                                    call_slip.item_id            = circ_transactions.item_id AND                  \n". # having the same patron, item and checkout day
      "                                    TRUNC(call_slip.status_date) = TRUNC(circ_transactions.charge_date)           \n". # is a pretty strong quarantee that the attached circ_transaction satisifed the hold_recall.
      "                                   )                                                                              \n".
      "LEFT JOIN item                  ON (item.item_id               = call_slip.item_id)                               \n".
      "LEFT JOIN item_status           ON (item_status.item_id        = item.item_id)                                    \n".
      "LEFT JOIN item_status_type      ON (item_status.item_status    = item_status_type.item_status_type)               \n".
      "LEFT JOIN circ_trans_archive    ON (circ_trans_archive.item_id = item.item_id)                                    \n".
      "WHERE     ( TRUNC(circ_trans_archive.discharge_date) = TRUNC(item_status.item_status_date)                        \n". # Finding the last location where this Item has been checked in to.
      "            OR                                                                                                    \n".
      "            circ_trans_archive.circ_transaction_id = ( SELECT MAX(circ_transaction_id)                            \n".
      "                                                       FROM   circ_trans_archive                                  \n".
      "                                                       WHERE item_id = item.item_id                               \n".
      "                                                     )                                                            \n".
      "            OR                                                                                                    \n".
      "            circ_trans_archive.circ_transaction_id IS NULL                                                        \n".
      "          )                                                                                                       \n".
      "     AND  item_status.item_status = (SELECT MIN(item_status) FROM item_status WHERE item_id = item.item_id)       \n". # Simply flatten possible multiple item status rows. Item status is not important for call slip requested items that might be in transfer.
      "     AND  call_slip_status_type.status_desc = 'Filled'                                                            \n". # Only call slips that don't have an attached hold_recall yet
      "     AND  hold_recall.hold_recall_id IS NULL                                                                      \n". # and the requested item has not been checked out by the requestor
      "     AND  circ_transactions.circ_transaction_id IS NULL                                                           \n". # are in transfer.
      "                                                                                                                  \n".
      "ORDER BY  item_id                                                                                                 \n".
      "",
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
      "SELECT    patron_notes.patron_note_id,
                 patron_notes.patron_id, patron_notes.note, patron_notes.note_type, patron_notes.modify_date
       FROM      patron_notes 
       ORDER BY  patron_notes.patron_id,patron_notes.modify_date",
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

  #No data in the Voyager subscription about into which branches it orders serials?
  #Only received serials have location-information.
  #Currently ignore predictions, because migrating predictions most certainly will be very slow/tedious vs benefits.
  "21-ser_issues.csv" => {
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
      "                                      call_slip.item_id = circ_transactions.item_id AND                                              \n". # having the same patron, item and checkout day
      "                                      TRUNC(call_slip.status_date) = TRUNC(circ_transactions.charge_date)                            \n". # is a pretty strong quarantee that the attached circ_transaction satisifed the hold_recall.
      "                                     )                                                                                               \n".
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
  "30-bib_item.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => [0, 1],
    sql =>
      "SELECT bib_item.bib_id, bib_item.item_id, bib_item.add_date
       FROM bib_item
       ORDER BY bib_item.item_id"
  },

  "31-funds.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => [0],
    sql =>
      "SELECT fund.fund_id,
              ledger.ledger_name,
              fund.parent_fund,
              fund.fund_code,
              fund.fund_name,
              fund_type.fund_type_name,
              fund.original_allocation,
              fund.begin_date,
              fund.end_date,
              fund_note.fund_note
      FROM  fund
      JOIN  fund_note ON (fund.fund_id = fund_note.fund_id)
      JOIN  fund_type ON (fund.fund_type = fund_type.fund_type_id)
      JOIN  ledger    ON (fund.ledger_id = ledger.ledger_id)
      ORDER BY fund.fund_id, ledger_ledger_name"
  },
  "32-fundledger.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => [0],
    sql =>
      "SELECT fundledger_vw.fundline,
              fundledger_vw.fiscal_period_id,
              fundledger_vw.fiscal_period_name,
              fundledger_vw.fiscal_period_start,
              fundledger_vw.fiscal_period_end,
              fundledger_vw.ledger_id,
              fundledger_vw.ledger_name,
              fundledger_vw.policy_name,
              fundledger_vw.fund_category,
              fundledger_vw.fund_id,
              fundledger_vw.fund_name,
              fundledger_vw.parent_fund_id,
              fundledger_vw.parent_fund,
              fundledger_vw.institution_fund_id,
              fundledger_vw.begin_date,
              fundledger_vw.end_date,
              fundledger_vw.current_allocation,
              fundledger_vw.original_allocation,
              fundledger_vw.cash_balance,
              fundledger_vw.free_balance,
              fundledger_vw.expenditures,
              fundledger_vw.commitments,
              fundledger_vw.commit_pending,
              fundledger_vw.expend_pending,
              fund_note.fund_note
      FROM  fundledger_vw
      JOIN  fund_note ON (fundledger_vw.fund_id = fund_note.fund_id AND fundledger_vw.ledger_id = fund_note.ledger_id )
      ORDER BY fundledger_vw.ledger_name,fundledger_vw.fund_name"
  },
  "33-purchase_orders.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => [0],
    sql =>
      "SELECT purchase_order.po_number,
              line_item_funds.fund_id,
              fund.fund_name,
              line_item_funds.amount,
              line_item_funds.amount,
              vendor.vendor_code,
              line_item.create_date,
              line_item.line_price,
              bib_text.bib_id,
              bib_text.title_brief,
              vendor.vendor_type,
              purchase_order.po_status,
              purchase_order.po_type,
              purchase_order.currency_code,
              purchase_order.conversion_rate,
              currency_conversion.decimals,
              line_item_copy_status.location_id
      FROM    bib_text,
              line_item_funds,
              fund,
              line_item,
              line_item_copy_status,
              purchase_order,
              vendor,
              currency_conversion
      WHERE   (line_item_funds.fund_id = fund.fund_id) and
              (line_item_funds.ledger_id = fund.ledger_id) and
              (line_item_funds.copy_id = line_item_copy_status.copy_id) and
              (line_item.line_item_id = line_item_copy_status_line_item_id) and
              (vendor.vendor_id = purchase_order.vendor_id) and
              (bib_text.bib_id = line_item.bib_id) and
              (purchase_order.po_id = line_item.po_id) and
              (purchase_order.currency_code = currency_conversion.currency_code)
              ORDER BY purchase_order.po_id"
  },
  "34-line_items.csv" => {
    encoding => "iso-8859-1",
    uniqueKey => [0],
    sql =>
      "SELECT DISTINCT line_item.line_item_id,
              line_item.po_id,
              line_item.bib_id,
              line_item_type.line_item_type_desc,
              line_item.line_item_number,
              line_item.piece_identifier,
              line_item.unit_price,
              line_item.line_price,
              line_item.print_std_num,
              line_item.quantity,
              line_item.prepay_amount,
              line_item.rush,
              line_item.claim_interval,
              line_item.cancel_interval,
              line_item.donor,
              line_item.requestor,
              line_item.vendor_title_num,
              line_item.vendor_ref_qual,
              line_item.vendor_ref_num,
              line_item.create_date,
              line_item.update_date,
              line_item.edi_ref,
              line_item.standard_num,
              line_item_notes.po_id,
              line_item_notes.print_note,
              line_item_notes.note,
              ledger.ledger_name,
              fund.fund_name,
              purchase_order.po_create_date
        FROM  line_item
        JOIN  line_item_type on (line_item_type.line_item_type = line_item.line_item_type)
        JOIN  line_item_notes on (line_item_notes.line_item_id = line_item.line_item_id)
        JOIN  line_item_copy on (line_item_copy.line_item_id = line_item.line_item_id)
        JOIN  ledger on (ledger.ledger_id = line_item_copy.use_ledger)
        JOIN  fund on (fund.fund_id = line_item_copy.use_fund)
        JOIN  purchase_order on (purchase_order.po_id = line_item.po_id)
        ORDER BY line_item.create_date DESC"
  }


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
    my $anonRules      = $queries{$filename}{anonymize};
    my $uniqueKeyIndex = $queries{$filename}{uniqueKey};
    %uniqueColumnVerifier = (); #Reset for every query

    if ($filename eq "serials_mfhd.csv") {
      extractSerialsMFHD($filename);
      next;
    }

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
}

return 1;
