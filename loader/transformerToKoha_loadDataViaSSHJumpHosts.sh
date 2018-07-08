#!/bin/bash

## IN THIS FILE
##
## Makes a ssh-connection from the transformation server via a jump host to the Koha application server
## Loads the transformed data in
##
## This is an example implementation of the data extraction pipeline automation.
## You must write your own which will work in your environment.

KOHA_HOST="koha-ci-jyu"
KOHA_HOME="/home/koha/Koha"

#Copy the loadable files in
scp -r ~/MMT-Voyager/KohaImports $KOHA_HOST:~/

#Start loading
ssh $KOHA_HOST "$KOHA_HOME/misc/migration_tools/load.sh ~/KohaImports"
