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

echo "Deploy the loader program"
scp -r loader/KohaLoader $KOHA_HOST:$KOHA_HOME/
test $? != 0 && echo "Uploading the Koha Loader failed!" && exit 8

ssh $KOHA_HOST "chown -R koha:koha $KOHA_HOME/KohaLoader"
test $? != 0 && echo "Setting Koha Loader permissions failed!" && exit 9


echo "Copy the loadable files in"
cd ~/MMT-Voyager && tar -czf kohaData.tar.gz KohaImports
test $? != 0 && echo "Packing Koha data failed!" && exit 10

scp -r   ~/MMT-Voyager/kohaData.tar.gz $KOHA_HOST:$KOHA_HOME
test $? != 0 && echo "Uploading Koha data failed!" && exit 11

ssh $KOHA_HOST "cd $KOHA_HOME && tar -xzf $KOHA_HOME/kohaData.tar.gz && rm $KOHA_HOME/kohaData.tar.gz && chown -R koha:koha $KOHA_HOME/KohaImports"
test $? != 0 && echo "Unpacking Koha data remotely failed!" && exit 12

ssh $KOHA_HOST "mkdir -p $KOHA_LOAD_WORKING_DIR && chown koha:koha $KOHA_LOAD_WORKING_DIR"
test $? != 0 && echo "Creating load-phase working dir remotely failed!" && exit 13

echo "Start loading"
ssh $KOHA_HOST "$KOHA_LOADER_DIR/load.sh $KOHA_HOME/KohaImports"
test $? != 0 && echo "Loading Koha data failed!" && exit 14
