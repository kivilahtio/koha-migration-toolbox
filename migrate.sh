#!/bin/bash
#
# This script is just a helper wrapper for migrate.pl so one can run the whole shizang with one shebang.
#

#Override MMT_HOME to support multiple pipelines on one control/transformation machine
test ! -z $1 && MMT_HOME=$1

echo "MMT_HOME='$MMT_HOME'"
echo -e "Log output uses shell colouring. Remember to set your reader to accept the colour codes.\n \$> less -Rr <file>\n "

LOG_DIR="$MMT_HOME/logs"
MMT_HOME="$MMT_HOME" perl migrate.pl --extract         &> $LOG_DIR/01-extract.log
MMT_HOME="$MMT_HOME" perl migrate.pl --biblios         &> $LOG_DIR/02-biblios.log
MMT_HOME="$MMT_HOME" perl migrate.pl --holdings        &> $LOG_DIR/03-holdings.log
MMT_HOME="$MMT_HOME" perl migrate.pl --items           &> $LOG_DIR/04-items.log
MMT_HOME="$MMT_HOME" perl migrate.pl --patrons         &> $LOG_DIR/05-patrons.log
MMT_HOME="$MMT_HOME" perl migrate.pl --issues          &> $LOG_DIR/06-issues.log
MMT_HOME="$MMT_HOME" perl migrate.pl --fines           &> $LOG_DIR/07-fines.log
MMT_HOME="$MMT_HOME" perl migrate.pl --reserves        &> $LOG_DIR/08-reserves.log
MMT_HOME="$MMT_HOME" perl migrate.pl --serials         &> $LOG_DIR/09-serials.log
MMT_HOME="$MMT_HOME" perl migrate.pl --subscriptions   &> $LOG_DIR/10-subscriptions.log
MMT_HOME="$MMT_HOME" perl migrate.pl --branchtransfers &> $LOG_DIR/11-branchtransfers.log
MMT_HOME="$MMT_HOME" perl migrate.pl --load            &> $LOG_DIR/12-load.log

echo ""
echo "Data migration pipeline complete. Please carefully check all the logs in the log directory '$LOG_DIR'"
echo ""
echo "-------------------------"
echo "Post data migration tasks"
echo "-------------------------"
echo ""
echo "Moving Patron ssns to Hetula is not currently securely automated."
echo "You must take the file"
echo "    $MMT_HOME/KohaImports/Patron.ssn.csv"
echo "and move it to Hetula."
echo ""
echo "Then use the Hetula-command batchImportSsn"
echo "    perl $HETULA_HOME/scripts/batchImportSsn -o ORGANIZATION_NAME --file path/to/Patron.ssn.csv"
echo "to migrate ssns to Hetula."
echo ""
echo "Hetula outputs a file"
echo "    path/to/Patron.ssn.csv.anon"
echo "This file contains the Hetula ssn.ids for the keys that passed the validation, or the invalid-tagged bad ssns."
echo "Move this file to your migration target Koha installation."
echo ""
echo "Load the new anonymized ssn keys to Koha using"
echo "    KohaLoader/bulkPatronImport.pl --uploadSSNKeysOnly path/to/Patron.ssn.csv.anon --bnConversionTable path/to/borrowernumberConversionTable"
echo ""
echo "Thank you!"
echo ""
