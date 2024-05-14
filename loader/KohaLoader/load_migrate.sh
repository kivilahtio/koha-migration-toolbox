#!/bin/bash

MMT_WORKING_DIR="$1"

test -z "$MMT_WORKING_DIR" && echo "This cannot be ran standalone, but must be called from load.sh" && exit 1

. $MMT_WORKING_DIR/mmt-env

export PERL5LIB="$PERL5LIB:." #New Perl versions no longer implicitly include modules from .

#Migrate frameworks
./bulkMARCFrameworkImport.pl &> $MMT_WORKING_DIR/bulkMARCFrameworkImport.log

#Migrate MARC and Items
./bulkBibImport.pl --file $MMT_DATA_SOURCE_DIR/biblios.marcxml \
    --bnConversionTable $MMT_WORKING_DIR/biblionumberConversionTable \
    &> $MMT_WORKING_DIR/bulkBibImport.log

./bulkMFHDImport.pl &> $MMT_WORKING_DIR/bulkMFHDImport.log

./bulkItemImport.pl &> $MMT_WORKING_DIR/bulkItemImport.log

#./bulkItemImport.pl --file $MMT_DATA_SOURCE_DIR/Hankinta.migrateme --bnConversionTable $MMT_WORKING_DIR/biblionumberConversionTable &> $WORKING_DIR/bulkAcquisitionImport.log

./bulkPatronImport.pl &> $MMT_WORKING_DIR/bulkPatronImport.log
test -n $DEFAULT_ADMIN && test -n $DEFAULT_ADMIN_APIKEY && ./bulkPatronImport.pl --defaultAdmin "$DEFAULT_ADMIN" --defaultAdminApiKey "$DEFAULT_ADMIN_APIKEY" &> $MMT_WORKING_DIR/bulkPatronImportDefaultAdmin.log
./bulkPatronImport.pl --messagingPreferencesOnly &> $MMT_WORKING_DIR/bulkPatronImportMessagingDefaults.log & #This is forked on the background
./bulkPatronImport.pl --sort1ToAuthorizedValueOnly &> $MMT_WORKING_DIR/bulkPatronImportSort1ToAuthorisedValue.log & #This is forked on the background
./bulkPatronImport.pl --uploadSSNKeysOnly &> $MMT_WORKING_DIR/bulkPatronImportSSNKeys.log & #This is forked on the background

./bulkHistoryImport.pl &> $MMT_WORKING_DIR/bulkHistoryImport.log # Histories' issue_id should be less then active checkouts.

./bulkCheckoutImport.pl &> $MMT_WORKING_DIR/bulkCheckoutImport.log

./bulkFinesImport.pl &> $MMT_WORKING_DIR/bulkFinesImport.log

./bulkHoldsImport.pl --file $MMT_DATA_SOURCE_DIR/Reserve.migrateme \
    --inConversionTable $MMT_WORKING_DIR/itemnumberConversionTable \
    --bornumConversionTable $MMT_WORKING_DIR/borrowernumberConversionTable \
    --bnConversionTable $MMT_WORKING_DIR/biblionumberConversionTable \
    &> $MMT_WORKING_DIR/bulkHoldsImport.log

./bulkBooksellerImport.pl --file $MMT_DATA_SOURCE_DIR/Bookseller.migrateme \
    &> $MMT_WORKING_DIR/bulkBooksellerImport.log

./bulkSubscriptionImport.pl \
    --subscriptionFile $MMT_DATA_SOURCE_DIR/Subscription.migrateme \
    --serialFile $MMT_DATA_SOURCE_DIR/Serial.migrateme \
    --routinglistFile $MMT_DATA_SOURCE_DIR/Subscriptionroutinglist.migrateme \
    --suConversionTable $MMT_WORKING_DIR/subscriptionidConversionTable \
    --bnConversionTable $MMT_WORKING_DIR/biblionumberConversionTable \
    --inConversionTable $MMT_WORKING_DIR/itemnumberConversionTable \
    &> $MMT_WORKING_DIR/bulkSubscriptionImport.log

./bulkBranchtransfersImport.pl -file $MMT_DATA_SOURCE_DIR/Branchtransfer.migrateme \
    --inConversionTable $MMT_WORKING_DIR/itemnumberConversionTable \
    &> $MMT_WORKING_DIR/bulkBranchtransfersImport.log
