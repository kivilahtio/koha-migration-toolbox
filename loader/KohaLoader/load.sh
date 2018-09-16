#!/bin/bash -x

cpanm --installdeps .

OP=$1              #Which operation to conduct?
DATA_SOURCE_DIR=$2 #Where the importable files are?
WORKING_DIR=$3     #Where to put all the conversion tables and generated logs?
CONFIRM=$4         #Automatically confirm that you want to cause all kinds of bad side effects on yourself.

test ! -e "$KOHA_CONF" && echo "\$KOHA_CONF=$KOHA_CONF doesn't exist. Aborting!" exit 2
KOHA_DB=$(xmllint --xpath "yazgfs/config/database/text()" $KOHA_CONF)
test -z "$KOHA_DB" && echo "\$KOHA_DB is unknown. Couldn't parse it from \$KOHA_CONF=$KOHA_CONF. Aborting!" exit 3

function help {
  echo "NAME"
  echo "  " $(basename $0) "- Load interface"
  echo ""
  echo "This is a master data loading interface to all the data migration tooling Koha provides."
  echo "One can manage the whole migration process from testing to going live to merging databases"
  echo "using this tooling."
  echo ""
  echo "SYNOPSIS"
  echo "  " $(basename $0) "operation importFilesDir workingDir"
  echo ""
  echo "OPTIONS"
  echo ""
  echo "  operation"
  echo "    one of backup, restore, migrate, merge"
  echo ""
  echo "  importFilesDir"
  echo "    Where to find the importable files"
  echo ""
  echo "  workingDir"
  echo "    Where to write primary key conversion tables and working logs"
  echo ""
}

test -z $OP &&                echo -e "\$OP is undefined\n" &&                         help && exit 5
test -z $DATA_SOURCE_DIR &&   echo -e "\$DATA_SOURCE_DIR is undefined\n" &&            help && exit 6
test -z $WORKING_DIR &&       echo -e "\$WORKING_DIR is undefined\n" &&                help && exit 7
test ! -r $DATA_SOURCE_DIR && echo -e "\$DATA_SOURCE_DIR=$DATA_SOURCE_DIR is not readable?" && exit 8
test ! -w $WORKING_DIR &&     echo -e "\$WORKING_DIR=$WORKING_DIR is not writable?"         && exit 9

# Make environment known for bulk*.pl -scripts, so they can infer defaults automatically.
export MMT_DATA_SOURCE_DIR=$DATA_SOURCE_DIR
export MMT_WORKING_DIR=$WORKING_DIR

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

    ./bulkMFHDImport.pl --file $DATA_SOURCE_DIR/mfhd.xml \
        --bnConversionTable $WORKING_DIR/biblionumberConversionTable \
        --hiConversionTable $WORKING_DIR/holding_idConversionTable \
        &> $WORKING_DIR/bulkMFHDImport.log

    ./bulkItemImport.pl &> $WORKING_DIR/bulkItemImport.log

    #./bulkItemImport.pl --file $DATA_SOURCE_DIR/Hankinta.migrateme --bnConversionTable $WORKING_DIR/biblionumberConversionTable &> $WORKING_DIR/bulkAcquisitionImport.log

    ./bulkPatronImport.pl --defaultadmin &> $WORKING_DIR/bulkPatronImport.log
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
    #Make a full Zebra reindex.
    #Zebra is no longer used $KOHA_PATH/misc/migration_tools/rebuild_zebra.pl -b -a -r -x -v &> $WORKING_DIR/rebuild_zebra.log
    $KOHA_PATH/misc/search_tools/rebuild_elastic_search.pl &> $WORKING_DIR/rebuild_elasticsearch.log
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

    fullReindex

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
