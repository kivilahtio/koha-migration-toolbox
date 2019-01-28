#!/bin/bash -x

## IN THIS FILE
##
## Makes a ssh-connection from the transformation-server to the VoyagerDB-server
## Runs the extract.pl to take DB dumps
## zip the .csv-files and pulls them to the Transform-phase of the DB migration.
##
## This is an example implementation of the data extraction pipeline automation.
## You must write your own which will work in your environment.

which sshpass
test $? != 0 && echo "sshpass is not installed. Install it with 'apt install sshpass'" && exit 10

VOYAGERDB="xxxdb"
VOYAGERDB_SERVER="user@voyagerserver.fi"
SSH_PASSWORD="password"
EXTRACT_CMD='/opt/CSCperl/current/bin/perl extract.pl -B -A -H --precision=HAMK'
VOYAGER_MMT_DIR="/m1/koha_migration/${VOYAGERDB}_koha"
VOYAGER_MMT_DATA_DIR="${VOYAGER_MMT_DIR}/data"


test -z "$MMT_HOME" && echo "Environmental variable MMT_HOME is not defined!" && exit 7

#Tunnel to VoyagerDB-server and deploy the newest version of the extractor program.
sshpass -p "$SSH_PASSWORD" ssh $VOYAGERDB_SERVER \
    "if [ ! -e $VOYAGER_MMT_DIR ]; then mkdir $VOYAGER_MMT_DIR; fi"
sshpass -p "$SSH_PASSWORD" scp -r  \
    extractor/VoyagerExtractor $VOYAGERDB_SERVER:$VOYAGER_MMT_DIR/

#Tunnel to VoyagerDB-server and run the extract.pl, make the zip and cleanup.
sshpass -p "$SSH_PASSWORD" ssh $VOYAGERDB_SERVER \
    "cd $VOYAGER_MMT_DIR/VoyagerExtractor && time $EXTRACT_CMD && cd $VOYAGER_MMT_DATA_DIR && zip voyagerData.zip *.marcxml *.csv && rm *.csv *.marcxml"

#Download the data
sshpass -p "$SSH_PASSWORD" scp \
    $VOYAGERDB_SERVER:$VOYAGER_MMT_DATA_DIR/voyagerData.zip ~/MMT-Voyager/VoyagerExports/

#unzip for consumption
cd $MMT_HOME/VoyagerExports/ && unzip -o voyagerData.zip && rm voyagerData.zip

