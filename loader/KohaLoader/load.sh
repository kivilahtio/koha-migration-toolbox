#!/bin/bash -x

echo ""
echo "Installing Perl dependencies"
echo "----------------------------"
cpanm --installdeps .

# Set parameter defaults
OP=""
DATA_SOURCE_DIR="../KohaImports/"
WORKING_DIR="../KohaMigration/"
CONFIRM=""
PRESERVE_IDS=""
DEFAULT_ADMIN=""

test ! -e "$KOHA_CONF" && echo "\$KOHA_CONF=$KOHA_CONF doesn't exist. Aborting!" exit 2
KOHA_DB=$(xmllint --xpath "yazgfs/config/database/text()" $KOHA_CONF)
test -z "$KOHA_DB" && echo "\$KOHA_DB is unknown. Couldn't parse it from \$KOHA_CONF=$KOHA_CONF. Aborting!" exit 3

## getopt --long
OPTS=`getopt -o o::d::w::cpa:: --long operation::,data-source::,working-dir::,confirm,preserve-ids,default-admin:: --name "$(basename "$0")" -- "$@"`
if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

eval set --$OPTS
echo $OPTS
# extract options and their arguments into variables.
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--operation)      OP=$2 ;              shift 2 ;;
        -d|--data-source)    DATA_SOURCE_DIR=$2 ; shift 2 ;;
        -w|--working-dir)    WORKING_DIR=$2 ;     shift 2 ;;
        -a|--default-admin)  DEFAULT_ADMIN=$2 ;   shift 2 ;;
        -c|--confirm)        CONFIRM=1 ;          shift ;;
        -p|--preserve-ids)   PRESERVE_IDS=1 ;     shift ;;
        --) shift ; break ;;
        *) echo "Internal error! '$1'" ; exit 1 ;;
    esac
done

function help {
  echo "NAME"
  echo "  " $(basename $0) "- Load interface"
  echo ""
  echo "This is a master data loading interface to all the data migration tooling Koha provides."
  echo "One can manage the whole migration process from testing to going live to merging databases"
  echo "using this tooling."
  echo ""
  echo "SYNOPSIS"
  echo "  " $(basename $0) "--operation=migrate --data-source=$DATA_SOURCE_DIR --working-dir=$WORKING_DIR --confirm --preserve-ids --default-admin=admin:1234"
  echo ""
  echo "OPTIONS"
  echo ""
  echo "  --operation String"
  echo "    Which operation to conduct? One of backup, restore, migrate, merge"
  echo ""
  echo "  --data-source Path to directory"
  echo "    Where to find the importable files"
  echo ""
  echo "  --working-dir Path to dir"
  echo "    Where to write primary key conversion tables and working logs"
  echo ""
  echo "  --confirm"
  echo "    Automatically confirm that you want to cause all kinds of bad side effects on yourself."
  echo ""
  echo "  --preserve-ids"
  echo "    Preserve the original database IDs in Koha for some types of data, such as bibs and patrons"
  echo ""
  echo "  --default-admin username:password"
  echo "    username:password of the default superlibrarian to add automatically, leave as 0|null to ingore adding the default admin"
  echo ""
}


test -z $OP &&                echo -e "\$OP is undefined\n" &&                         help && exit 5
echo "Doing operation '$OP'"
test -z $DATA_SOURCE_DIR &&   echo -e "\$DATA_SOURCE_DIR is undefined\n" &&            help && exit 6
echo "\$DATA_SOURCE_DIR='$DATA_SOURCE_DIR'"
test -z $WORKING_DIR &&       echo -e "\$WORKING_DIR is undefined\n" &&                help && exit 7
echo "\$WORKING_DIR='$WORKING_DIR'"
test ! -r $DATA_SOURCE_DIR && echo -e "\$DATA_SOURCE_DIR=$DATA_SOURCE_DIR is not readable?" && exit 8
test ! -w $WORKING_DIR &&     echo -e "\$WORKING_DIR=$WORKING_DIR is not writable?"         && exit 9

test -z $PRESERVE_IDS &&      echo -e "\$PRESERVE_IDS not set. Letting Koha generate new primary keys for everything"
test $PRESERVE_IDS &&         echo -e "\$PRESERVE_IDS set. Preserving legacy database IDs"

test $DEFAULT_ADMIN &&        echo -e "\$DEFAULT_ADMIN scheduled for creation."
test -z $DEFAULT_ADMIN &&     echo -e "\$DEFAULT_ADMIN not being created."

# Make environment known for bulk*.pl -scripts, so they can infer defaults automatically.
export MMT_DATA_SOURCE_DIR=$DATA_SOURCE_DIR
export MMT_WORKING_DIR=$WORKING_DIR
export MMT_PRESERVE_IDS=$PRESERVE_IDS

function checkUser {
    user=$1
    if [ $(whoami) != "$user" ]
    then
        echo "You must run this as $user-user"
        exit
    fi
}

function migrateBulkScripts {
    export PERL5LIB="$PERL5LIB:." #New Perl versions no longer implicitly include modules from .

    #Migrate MARC and Items
    ./bulkBibImport.pl --file $DATA_SOURCE_DIR/biblios.marcxml \
        --bnConversionTable $WORKING_DIR/biblionumberConversionTable \
        &> $WORKING_DIR/bulkBibImport.log

    ./bulkMFHDImport.pl &> $WORKING_DIR/bulkMFHDImport.log

    ./bulkItemImport.pl &> $WORKING_DIR/bulkItemImport.log

    #./bulkItemImport.pl --file $DATA_SOURCE_DIR/Hankinta.migrateme --bnConversionTable $WORKING_DIR/biblionumberConversionTable &> $WORKING_DIR/bulkAcquisitionImport.log

    ./bulkPatronImport.pl --defaultAdmin "$DEFAULT_ADMIN" &> $WORKING_DIR/bulkPatronImport.log
    ./bulkPatronImport.pl --messagingPreferencesOnly &> $WORKING_DIR/bulkPatronImportMessagingDefaults.log & #This is forked on the background
    ./bulkPatronImport.pl --uploadSSNKeysOnly &> $WORKING_DIR/bulkPatronImportSSNKeys.log & #This is forked on the background

    ./bulkCheckoutImport.pl -file $DATA_SOURCE_DIR/Issue.migrateme \
        --inConversionTable $WORKING_DIR/itemnumberConversionTable \
        --bnConversionTable $WORKING_DIR/borrowernumberConversionTable \
        &> $WORKING_DIR/bulkCheckoutImport.log

    ./bulkFinesImport.pl --file $DATA_SOURCE_DIR/Fine.migrateme \
        --inConversionTable $WORKING_DIR/itemnumberConversionTable \
        --bnConversionTable $WORKING_DIR/borrowernumberConversionTable \
        &> $WORKING_DIR/bulkFinesImport.log

    ./bulkHoldsImport.pl --file $DATA_SOURCE_DIR/Reserve.migrateme \
        --inConversionTable $WORKING_DIR/itemnumberConversionTable \
        --bornumConversionTable $WORKING_DIR/borrowernumberConversionTable \
        --bnConversionTable $WORKING_DIR/biblionumberConversionTable \
        &> $WORKING_DIR/bulkHoldsImport.log

    ./bulkSubscriptionImport.pl \
        --subscriptionFile $DATA_SOURCE_DIR/Subscription.migrateme \
        --serialFile $DATA_SOURCE_DIR/Serial.migrateme \
        --suConversionTable $WORKING_DIR/subscriptionidConversionTable \
        --bnConversionTable $WORKING_DIR/biblionumberConversionTable \
        &> $WORKING_DIR/bulkSubscriptionImport.log

    ./bulkBranchtransfersImport.pl -file $DATA_SOURCE_DIR/Branchtransfer.migrateme \
        --inConversionTable $WORKING_DIR/itemnumberConversionTable
        &> $WORKING_DIR/bulkBranchtransfersImport.log

    #./bulkRotatingCollectionsImport.pl --file $DATA_SOURCE_DIR/Siirtolaina.migrateme &> $WORKING_DIR/bulkRotatingCollectionsImport.log
    #./bulkHistoryImport.pl --file /home/koha/pielinen/histories.migrateme &> bulkHistoryImport.log
}

function cleanPastMigrationWorkspace {
    #Remove traces of existing migrations
    rm $WORKING_DIR/biblionumberConversionTable $WORKING_DIR/itemnumberConversionTable $WORKING_DIR/borrowernumberConversionTable \
       $WORKING_DIR/subscriptionidConversionTable
    rm $WORKING_DIR/marc.matchlog $WORKING_DIR/marc.manualmatching
}

function fullReindex {
    flush="$1"
    if [ -z "$flush" ]; then
        flush="-d"
    fi
    #Make a full Zebra reindex.
    #Zebra is no longer used $KOHA_PATH/misc/migration_tools/rebuild_zebra.pl -b -a -r -x -v &> $WORKING_DIR/rebuild_zebra.log
    $KOHA_PATH/misc/search_tools/rebuild_elastic_search.pl $flush &> $WORKING_DIR/rebuild_elasticsearch.log
}

if [ "$OP" == "backup" ]
then
    ##Run this as root to use the backup
    checkUser "root"

    echo "Packaging MySQL databases and Zebra index. This will take some time."
    ##Run this as root to make a backup of an existing merge target database
    service mysql stop
    service koha-zebra-daemon stop
    time tar -czf $WORKING_DIR/mysql.bak.tar.gz -C /var/lib/ mysql
    time tar -czf $WORKING_DIR/zebra.bak.tar.gz -C /home/koha/koha-dev/var/lib/ zebradb
    service mysql start
    service koha-zebra-daemon start
    exit

elif [ "$OP" == "restore" ]
then
    ##Run this as root to use the backup
    checkUser "root"

    echo "Restoring MySQL-databases and Zebra-index from backups. Have a cup of something :)"
    service mysql stop
    service koha-zebra-daemon stop
    rm -r /var/lib/mysql
    rm -r /home/koha/koha-dev/var/lib/zebradb
    time tar -xzf $WORKING_DIR/mysql.bak.tar.gz -C /var/lib/
    time tar -xzf $WORKING_DIR/zebra.bak.tar.gz -C /home/koha/koha-dev/var/lib/
    service mysql start
    service koha-zebra-daemon start
    #  #Reindex zebra as the koha-user, this will take a loong time.
    #  #su -c "$KOHA_PATH/misc/migration_tools/rebuild_zebra.pl -b -a -r -x -v &> $KOHA_PATH/misc/migration_tools/rebuild_zebra.log_from_revertdb" koha
    exit

elif [ "$OP" == "migrate" ]
then
    ##Run this as koha to not break permissions
    checkUser "koha"

    if [ -z $CONFIRM ]; then
        echo "Are you OK with having the Koha database and search index destroyed, and migrating a new batch? OK to accept, anything else to abort."
        read confirmation
        if [ $confirmation == "OK"  ]; then
            echo "I AM HAPPY TO HEAR THAT!"
        else
            echo "Try some other option."
            exit 1
        fi
    else
        echo "Automatic confirmation given"
    fi

    cleanPastMigrationWorkspace

    #Kill the search indexes when doing bare migrations. Remember to not kill indexes when merging migrations :)
    rm -r /home/koha/koha-dev/var/lib/zebradb/biblios/*
    rm -r /home/koha/koha-dev/var/lib/zebradb/authorities/*
    #Empty all previously migrated data, except configurations. You don't want this when merging records :)
    mysql $KOHA_DB < bulkEmptyMigratedTables.sql

    migrateBulkScripts

    fullReindex flush

    exit

elif [ "$OP" == "merge" ]
then
    ##Run this as koha to not break permissions
    checkUser "koha"

    if [ -z $CONFIRM ]; then
        echo "Are you OK with having two databases merged? You should have a Zebra index to merge against. OK to accept, anything else to abort."
        read confirmation
        if [ $confirmation == "OK"  ]; then
            echo "I AM HAPPY TO HEAR THAT!"
        else
            echo "Try some other option."
            exit 1
        fi
    else
        echo "Automatic confirmation given"
    fi

    cleanPastMigrationWorkspace

    migrateBulkScripts

    fullReindex

    exit
fi
