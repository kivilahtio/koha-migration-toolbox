#!/bin/bash -x

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

# Comment JUMP_HOST if you are not using one.
VOYAGERDB="xxxdb"
JUMP_HOST="user@jumphost"
VOYAGERDB_SERVER="user@voyagerserver.fi"
SSH_PASSWORD="password"
EXTRACT_CMD='/opt/CSCperl/current/bin/perl extract.pl -B -A -H --precision=1 --bound'
VOYAGER_MMT_DIR="/m1/koha_migration/${VOYAGERDB}_koha"
VOYAGER_MMT_DATA_DIR="${VOYAGER_MMT_DIR}/data"


test -z "$MMT_HOME" && echo "Environmental variable MMT_HOME is not defined!" && exit 7

#Tunnel to VoyagerDB-server and deploy the newest version of the extractor program.
if [[ ! -z $JUMP_HOST ]]; then
    sshpass -p $SSH_PASSWORD ssh -o ProxyCommand="ssh -A -W %h:%p $JUMP_HOST" $VOYAGERDB_SERVER \
	    "if [ ! -e $VOYAGER_MMT_DIR ]; then mkdir $VOYAGER_MMT_DIR; fi"    
    sshpass -p $SSH_PASSWORD scp -r -o ProxyCommand="ssh -A -W %h:%p $JUMP_HOST" \
	    extractor/VoyagerExtractor $VOYAGERDB_SERVER:$VOYAGER_MMT_DIR/
else
    sshpass -p $SSH_PASSWORD ssh $VOYAGERDB_SERVER \
	    "if [ ! -e $VOYAGER_MMT_DIR ]; then mkdir $VOYAGER_MMT_DIR; fi"
    sshpass -p $SSH_PASSWORD scp -r  \
	    extractor/VoyagerExtractor $VOYAGERDB_SERVER:$VOYAGER_MMT_DIR/
fi

#Tunnel to VoyagerDB-server and run the extract.pl, make the zip and cleanup.
if [[ ! -z $JUMP_HOST ]]; then
    sshpass -p $SSH_PASSWORD ssh -o ProxyCommand="ssh -A -W %h:%p $JUMP_HOST" $VOYAGERDB_SERVER \
	    "cd $VOYAGER_MMT_DIR/VoyagerExtractor && time $EXTRACT_CMD && cd $VOYAGER_MMT_DATA_DIR && zip voyagerData.zip *.marcxml *.csv && rm *.csv *.marcxml"
else
      sshpass -p $SSH_PASSWORD ssh $VOYAGERDB_SERVER \
    "cd $VOYAGER_MMT_DIR/VoyagerExtractor && time $EXTRACT_CMD && cd $VOYAGER_MMT_DATA_DIR && zip voyagerData.zip *.xml *.csv && rm *.csv *.xml"
fi

#Download the data
if [[ ! -z $JUMP_HOST ]]; then
    sshpass -p $SSH_PASSWORD scp -o ProxyCommand="ssh -A -W %h:%p $JUMP_HOST" \
	    $VOYAGERDB_SERVER:$VOYAGER_MMT_DATA_DIR/voyagerData.zip $MMT_HOME/VoyagerExports/
else
    sshpass -p $SSH_PASSWORD scp \
    $VOYAGERDB_SERVER:$VOYAGER_MMT_DATA_DIR/voyagerData.zip ~/MMT-Voyager/VoyagerExports/
fi

#unzip for consumption
cd $MMT_HOME/VoyagerExports/ && unzip -o voyagerData.zip && rm voyagerData.zip

