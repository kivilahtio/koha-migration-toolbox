#!/bin/bash -x

## IN THIS FILE
##
## Makes a ssh-connection from the transformation server via a jump host to the Koha application server
## Loads the transformed data in
##
## This is an example implementation of the data extraction pipeline automation.
## You must write your own which will work in your environment.

KOHA_HOST="koha-ci-jyu"
KOHA_HOME="/home/koha/Koha"
KOHA_LOAD_WORKING_DIR="/home/koha/KohaMigration"

#Copy the loadable files in
cd ~/MMT-Voyager && tar -czf kohaData.tar.gz KohaImports
test $? != 0 && echo "Packing Koha data failed!" && exit 10

scp -r   ~/MMT-Voyager/kohaData.tar.gz $KOHA_HOST:/home/koha/
test $? != 0 && echo "Uploading Koha data failed!" && exit 11

ssh $KOHA_HOST "cd /home/koha && tar -xzf /home/koha/kohaData.tar.gz"
test $? != 0 && echo "Unpacking Koha data remotely failed!" && exit 12

ssh $KOHA_HOST "mkdir -p $KOHA_LOAD_WORKING_DIR && chown koha:koha $KOHA_LOAD_WORKING_DIR"
test $? != 0 && echo "Creating load-phase working dir remotely failed!" && exit 13

#Start loading
ssh $KOHA_HOST "$KOHA_HOME/misc/migration_tools/load.sh ~/KohaImports"
test $? != 0 && echo "Loading Koha data failed!" && exit 14
