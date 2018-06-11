#!/bin/bash

## IN THIS FILE
##
## Makes a ssh-connection from the Koha-server via a jump host to the VoyagerDB-server
## Runs the extract.pl to take DB dumps
## zip the .csv-files and pulls them to the Transform-phase of the DB migration.
##
## This is an example implementation of the data extraction pipeline automation.
## You must write your own which will work in your environment.

sudo apt install sshpass

PROXYCOMMAND="-o 'ProxyCommand ssh -A -W %h:%p user@jumpserver.fi'"
VOYAGERDB_SERVER="user@voyagerserver.fi"
SSH_PASSWORD="password"

#Tunnel to VoyagerDB-server and run the extract.pl, make the zip and cleanup.
sshpass -p $SSH_PASSWORD ssh $PROXYCOMMAND $VOYAGERDB_SERVER "cd /export/home/koha/extract && time ./extract.pl && zip voyagerData.zip *.csv && rm *.csv"
#Download the data
sshpass -p $SSH_PASSWORD scp $PROXYCOMMAND $VOYAGERDB_SERVER:/export/home/koha/extract/voyagerData.zip ~/MMT-Voyager/VoyagerExports/
#unzip for consumption
cd ~/MMT-Voyager/VoyagerExports/ && unzip voyagerData.zip

