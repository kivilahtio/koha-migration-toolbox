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
KOHA_INSTANCE_NAME=$(koha-list | head -n 1)
KOHA_USER="$KOHA_INSTANCE_NAME-koha"

## getopt --long
OPTS=`getopt -o o::k::d::w::cpa:: --long operation::,koha-instance::,data-source::,working-dir::,confirm,preserve-ids,default-admin:: --name "$(basename "$0")" -- "$@"`
if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

eval set --$OPTS
echo $OPTS
# extract options and their arguments into variables.
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--operation)      OP=$2 ;              shift 2 ;;
        -k|--koha-instance)  KOHA_INSTANCE_NAME=$2 ; shift 2 ;;
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
  echo "  --koha-instance String"
  echo "    Which Koha-instance to migrate data for. Defaults to the first instance from koha-list"
  echo ""
  echo "  --koha-user String"
  echo "    Username of the koha-user account on the server. Defaults to 'koha_' followed by the first instance name on the server."
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


export KOHA_CONF="/etc/koha/sites/$KOHA_INSTANCE_NAME/koha-conf.xml"
test ! -e "$KOHA_CONF" && echo "\$KOHA_CONF=$KOHA_CONF doesn't exist. Aborting!" exit 2
KOHA_DB=$(xmllint --xpath "yazgfs/config/database/text()" $KOHA_CONF)
KOHA_DB_USER=$(xmllint --xpath "yazgfs/config/user/text()" $KOHA_CONF)
KOHA_DB_PASS=$(xmllint --xpath "yazgfs/config/pass/text()" $KOHA_CONF)
KOHA_USE_ELASTIC=$(xmllint --xpath "yazgfs/config/elasticsearch/server/text()" $KOHA_CONF)
test -z "$KOHA_DB" && echo "\$KOHA_DB is unknown. Couldn't parse it from \$KOHA_CONF=$KOHA_CONF. Aborting!" exit 3
test -z "$KOHA_DB_USER" && echo "\$KOHA_DB_USER is unknown. Couldn't parse it from \$KOHA_CONF=$KOHA_CONF. Aborting!" exit 3
test -z "$KOHA_DB_PASS" && echo "\$KOHA_DB_PASS is unknown. Couldn't parse it from \$KOHA_CONF=$KOHA_CONF. Aborting!" exit 3




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

test $KOHA_USE_ELASTIC &&     echo -e "\$KOHA_USE_ELASTIC = '$KOHA_USE_ELASTIC'. Indexing to Elasticsearch."
test -z $KOHA_USE_ELASTIC &&  echo -e "\$KOHA_USE_ELASTIC is unset. Indexing to Zebra."

# Make environment known for bulk*.pl -scripts, so they can infer defaults automatically.
echo "
export MMT_DATA_SOURCE_DIR=$DATA_SOURCE_DIR
export MMT_WORKING_DIR=$WORKING_DIR
export MMT_PRESERVE_IDS=$PRESERVE_IDS
export DEFAULT_ADMIN=$DEFAULT_ADMIN
export PRESERVE_IDS=$PRESERVE_IDS
export KOHA_USE_ELASTIC=$KOHA_USE_ELASTIC
export KOHA_DB=$KOHA_DB
export KOHA_DB_USER=$KOHA_DB_USER
export KOHA_DB_PASS=$KOHA_DB_PASS
" > $WORKING_DIR/mmt-env
. $WORKING_DIR/mmt-env # This way the used environment can be reused without rerunning this script => better dev and debugging

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

    ./bulkPatronImport.pl &> $WORKING_DIR/bulkPatronImport.log
    test -n $DEFAULT_ADMIN && ./bulkPatronImport.pl --defaultAdmin "$DEFAULT_ADMIN" &> $WORKING_DIR/bulkPatronImportDefaultAdmin.log
    ./bulkPatronImport.pl --messagingPreferencesOnly &> $WORKING_DIR/bulkPatronImportMessagingDefaults.log & #This is forked on the background
    ./bulkPatronImport.pl --uploadSSNKeysOnly &> $WORKING_DIR/bulkPatronImportSSNKeys.log & #This is forked on the background

    ./bulkHistoryImport.pl &> $WORKING_DIR/bulkHistoryImport.log # Histories' issue_id should be less then active checkouts.

    ./bulkCheckoutImport.pl &> $WORKING_DIR/bulkCheckoutImport.log

    ./bulkFinesImport.pl &> $WORKING_DIR/bulkFinesImport.log

    ./bulkHoldsImport.pl --file $DATA_SOURCE_DIR/Reserve.migrateme \
        --inConversionTable $WORKING_DIR/itemnumberConversionTable \
        --bornumConversionTable $WORKING_DIR/borrowernumberConversionTable \
        --bnConversionTable $WORKING_DIR/biblionumberConversionTable \
        &> $WORKING_DIR/bulkHoldsImport.log

    ./bulkBooksellerImport.pl --file $DATA_SOURCE_DIR/Bookseller.migrateme \
        &> $WORKING_DIR/bulkBooksellerImport.log

    ./bulkSubscriptionImport.pl \
        --subscriptionFile $DATA_SOURCE_DIR/Subscription.migrateme \
        --serialFile $DATA_SOURCE_DIR/Serial.migrateme \
        --routinglistFile $DATA_SOURCE_DIR/Subscriptionroutinglist.migrateme \
        --suConversionTable $WORKING_DIR/subscriptionidConversionTable \
        --bnConversionTable $WORKING_DIR/biblionumberConversionTable \
        --inConversionTable $WORKING_DIR/itemnumberConversionTable \
        &> $WORKING_DIR/bulkSubscriptionImport.log

    ./bulkBranchtransfersImport.pl -file $DATA_SOURCE_DIR/Branchtransfer.migrateme \
        --inConversionTable $WORKING_DIR/itemnumberConversionTable \
        &> $WORKING_DIR/bulkBranchtransfersImport.log

}

function cleanPastMigrationWorkspace {
    #Remove traces of existing migrations
    rm $WORKING_DIR/biblionumberConversionTable $WORKING_DIR/itemnumberConversionTable $WORKING_DIR/borrowernumberConversionTable \
       $WORKING_DIR/subscriptionidConversionTable
    rm $WORKING_DIR/marc.matchlog $WORKING_DIR/marc.manualmatching
}

function flushDataFromDB {
    #Empty all previously migrated data, except configurations. You don't want this when merging records :)
    ./bulkEmptyMigratedTables.sh
}

function fullReindex {
    FLUSH="$1"

    checkUser "$KOHA_USER"

    if [ -n "$KOHA_USE_ELASTIC" ]; then
        if [ -n "$FLUSH" ]; then
            FLUSH="--delete"
        fi
        koha-elasticsearch $FLUSH --rebuild --verbose KOHA_INSTANCE_NAME &> $WORKING_DIR/rebuild_search_index.log
    else
        if [ -n "$FLUSH" ]; then
            FLUSH="--full"
        fi
        koha-rebuild-zebra --verbose $FLUSH KOHA_INSTANCE_NAME &> $WORKING_DIR/rebuild_search_index.log
    fi
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
    checkUser "$KOHA_USER"

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

    #Empty all previously migrated data, except configurations. You don't want this when merging records :)
    flushDataFromDB

    migrateBulkScripts

    #Kill the search indexes when doing bare migrations. Remember to not kill indexes when merging migrations :)
    fullReindex flush

    exit

elif [ "$OP" == "merge" ]
then
    ##Run this as koha to not break permissions
    checkUser "$KOHA_USER"

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
