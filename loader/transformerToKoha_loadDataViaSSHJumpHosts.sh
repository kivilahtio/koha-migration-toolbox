#!/bin/bash -x

## IN THIS FILE
##
## Makes a ssh-connection from the transformation server via a jump host to the Koha application server
## Loads the transformed data in
##
## This is an example implementation of the data extraction pipeline automation.
## You must write your own which will work in your environment.

KOHA_HOST="koha-host-server"
KOHA_HOME="/home/koha"
KOHA_LOAD_WORKING_DIR="$KOHA_HOME/KohaMigration"
KOHA_LOADER_DIR="$KOHA_HOME/KohaLoader"
KOHA_LOADER_CMD="./load.sh --operation=migrate --data-source=$KOHA_HOME/KohaImports --working-dir=$KOHA_LOAD_WORKING_DIR --confirm --preserve-ids --default-admin=0"

HETULA_CREDENTIALS_FILE="Hetula.credentials" #This must be manually created with login information. This filename is hardcoded, don't change it.
HETULA_CREDS_FILE_IN_TRANSFORMER="$MMT_HOME/KohaImports/$HETULA_CREDENTIALS_FILE"

test -z "$MMT_HOME" && echo "Environmental variable MMT_HOME is not defined!" && exit 5

test ! -e $HETULA_CREDS_FILE_IN_TRANSFORMER && echo "Hetula credentials file '$HETULA_CREDS_FILE_IN_TRANSFORMER' is missing! You must manually create it. See 'hetula-client --help' within your Koha-installation for more information." && exit 6
test 1 -ge $(wc -l <$HETULA_CREDS_FILE_IN_TRANSFORMER) && echo "Hetula credentials file '$HETULA_CREDS_FILE_IN_TRANSFORMER' is too small! Atleast the username and password must be defined there. See 'hetula-client --help' within your Koha-installation for more information." && exit 6
chmod 600 $HETULA_CREDS_FILE_IN_TRANSFORMER #Protect it if you forgot :)

echo "Deploy the loader program"
scp -r loader/KohaLoader $KOHA_HOST:$KOHA_HOME/
test $? != 0 && echo "Uploading the Koha Loader failed!" && exit 8

ssh $KOHA_HOST "chown -R koha:koha $KOHA_HOME/KohaLoader"
test $? != 0 && echo "Setting Koha Loader permissions failed!" && exit 9


echo "Copy the loadable files in"
cd $MMT_HOME && tar -czf kohaData.tar.gz KohaImports
test $? != 0 && echo "Packing Koha data failed!" && exit 10

scp -r $MMT_HOME/kohaData.tar.gz $KOHA_HOST:$KOHA_HOME
test $? != 0 && echo "Uploading Koha data failed!" && exit 11

ssh $KOHA_HOST "cd $KOHA_HOME && tar -xzf $KOHA_HOME/kohaData.tar.gz && rm $KOHA_HOME/kohaData.tar.gz && chown -R koha:koha $KOHA_HOME/KohaImports"
test $? != 0 && echo "Unpacking Koha data remotely failed!" && exit 12

ssh $KOHA_HOST "mkdir -p $KOHA_LOAD_WORKING_DIR && chown koha:koha $KOHA_LOAD_WORKING_DIR"
test $? != 0 && echo "Creating load-phase working dir remotely failed!" && exit 13

echo "Start loading"
ssh $KOHA_HOST "cd $KOHA_LOADER_DIR && su -c '$KOHA_LOADER_CMD' koha"
test $? != 0 && echo "Loading Koha data failed!" && exit 14
