#!/bin/bash

## IN THIS FILE
##
## Makes a ssh-connection from the transformation-server via a jump host to the VoyagerDB-server
## Runs the extract.pl to take DB dumps
## zip the .csv-files and pulls them to the Transform-phase of the DB migration.
##
## This is an example implementation of the data extraction pipeline automation.
## You must write your own which will work in your environment.

which sshpass
test $? != 0 && echo "sshpass is not installed. Install it with 'apt install sshpass'" && exit 10

JUMP_HOST="user@jumphost"
VOYAGERDB_SERVER="user@voyagerserver.fi"
SSH_PASSWORD="password"
EXTRACT_CMD='/opt/CSCperl/current/bin/perl extract.pl -B -A -H --bywater --bound'
VOYAGER_MMT_DIR="/m1/groupcron/hamk/scripts/koha"
VOYAGER_MMT_DATA_DIR="/m1/groupcron/hamk/scripts/koha/data"

#Tunnel to VoyagerDB-server and run the extract.pl, make the zip and cleanup.
sshpass -p $SSH_PASSWORD ssh -o ProxyCommand="ssh -A -W %h:%p $JUMP_HOST" $VOYAGERDB_SERVER \
"cd $VOYAGER_MMT_DIR && time $EXTRACT_CMD && cd $VOYAGER_MMT_DATA_DIR && zip voyagerData.zip *.csv && rm *.csv"

#Download the data
sshpass -p $SSH_PASSWORD scp -o ProxyCommand="ssh -A -W %h:%p $JUMP_HOST" \
$VOYAGERDB_SERVER:$VOYAGER_MMT_DATA_DIR/voyagerData.zip ~/MMT-Voyager/VoyagerExports/

#unzip for consumption
cd ~/MMT-Voyager/VoyagerExports/ && unzip -o voyagerData.zip && rm voyagerData.zip

