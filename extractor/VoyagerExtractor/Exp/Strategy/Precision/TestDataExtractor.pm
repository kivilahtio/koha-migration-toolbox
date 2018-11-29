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

package Exp::Strategy::Precision::TestDataExtractor;

#Pragmas
use warnings;
use strict;
use utf8; #This file and all Strings within are utf8-encoded
binmode( STDOUT, ":encoding(UTF-8)" );
binmode( STDIN,  ":encoding(UTF-8)" );
$|=1;

=head2 NAME

Exp::Strategy::Precision::TestDataExtractor - Extract data needed to run unit tests.

=head2 DESCRIPTION

Export all kinds of data from Voyager using the given precision SQL.

Needed to be ran only once to generate test context for test suites.
This is manually put to use in various MMT tests.

This has and MUST NOT directly have anything to do with a production data migration pipeline.

=cut

our %queries = (
  "21-stat.fi-location_mappings.csv" => { #Extracts data for the test cases in the similarly named test file.
    uniqueKey => -1,
    sql =>
      "SELECT    item_barcode.item_barcode, bib_text.begin_pub_date, mfhd_master.display_call_no,  \n".
      "          frequency.freq_increment, frequency.freq_calc_type                                \n".
      "FROM      mfhd_master                                                                       \n".
      "LEFT JOIN mfhd_item ON (mfhd_item.mfhd_id = mfhd_master.mfhd_id)                            \n".
      "LEFT JOIN item_barcode ON (item_barcode.item_id = mfhd_item.item_id)                        \n".
      "LEFT JOIN bib_item ON (bib_item.item_id = mfhd_item.item_id)                                \n".
      "LEFT JOIN bib_text ON (bib_text.bib_id = bib_item.bib_id)                                   \n".
      "LEFT JOIN line_item ON (line_item.bib_id = bib_item.bib_id)                                 \n".
      "LEFT JOIN subscription ON (subscription.line_item_id = line_item.line_item_id)              \n".
      "LEFT JOIN component ON (component.subscription_id = subscription.subscription_id)           \n".
      "LEFT JOIN component_pattern ON (component_pattern.component_id = component.component_id)    \n".
      "LEFT JOIN frequency ON (frequency.frequency_code = component_pattern.frequency_code)        \n".
      "WHERE     component.component_id = (                                                        \n".
      "              SELECT MAX(c.component_id) as component_id                                    \n". #Flatten multiple components
      "              FROM   component c                                                            \n".
      "              WHERE  c.subscription_id = subscription.subscription_id                       \n".
      "          )                                                                                 \n".
      "       OR component.component_id IS NULL                                                    \n".
      "",
  },
);

1;
