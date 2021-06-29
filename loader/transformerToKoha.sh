#!/bin/bash -x

## IN THIS FILE
##
## Makes a ssh-connection from the transformation server to the Koha application server
## Loads the transformed data in
##
## This is an example implementation of the data extraction pipeline automation.
## You must write your own which will work in your environment.

. "$MMT_HOME/secret/credentials.sh" || (echo "Sourcing the secret/credentials.sh for credentials failed." && exit 10) # source the above access credentials

MMT_PROGRAM_DIR=`pwd` # koha-migration-tools executes this script from it's own runtime dir.
#SRC_ILS="Lib" # From credentials
#KOHA_HOST="koha-host-server" # From credentials
#KOHA_DEFAULT_ADMIN="" # From credentials
KOHA_HOME="/home/koha"
KOHA_LOAD_WORKING_DIR="$KOHA_HOME/KohaMigration$SRC_ILS"
KOHA_LOADER_DIR="$KOHA_HOME/KohaLoader"
KOHA_LOADER_CMD="./load.sh --operation=migrate --data-source=$KOHA_HOME/KohaImports$SRC_ILS --working-dir=$KOHA_LOAD_WORKING_DIR --confirm --default-admin=$KOHA_DEFAULT_ADMIN"

HETULA_CREDENTIALS_FILE="Hetula.credentials" #This must be manually created with login information. This filename is hardcoded, don't change it.
HETULA_CREDS_FILE_IN_TRANSFORMER="$MMT_HOME/KohaImports$SRC_ILS/$HETULA_CREDENTIALS_FILE"

test -z "$MMT_HOME" && echo "Environmental variable MMT_HOME is not defined!" && exit 5

# Warn about Hetula credentials file missing, but do not demand it. Ssns migration phase can be easily continued after failure as it is not a critical-path task
if [ ! -e $HETULA_CREDS_FILE_IN_TRANSFORMER ]
then
  echo "Hetula credentials file '$HETULA_CREDS_FILE_IN_TRANSFORMER' is missing! If you want to load ssns to Hetula, you must manually create it. See 'hetula-client --help' within your Koha-installation for more information."
else
  test 1 -ge $(wc -l <$HETULA_CREDS_FILE_IN_TRANSFORMER) && echo "Hetula credentials file '$HETULA_CREDS_FILE_IN_TRANSFORMER' is too small! Atleast the username and password must be defined there. See 'hetula-client --help' within your Koha-installation for more information." && exit 6
  chmod 600 $HETULA_CREDS_FILE_IN_TRANSFORMER #Protect it if you forgot :)
fi

if [ -n "$KOHA_HOST" ]; then
  echo "Deploy the loader program"
  scp -r loader/KohaLoader $KOHA_HOST:$KOHA_HOME/
  test $? != 0 && echo "Uploading the Koha Loader failed!" && exit 8

  ssh $KOHA_HOST "chown -R koha:koha $KOHA_HOME/KohaLoader"
  test $? != 0 && echo "Setting Koha Loader permissions failed!" && exit 9


  echo "Copy the loadable files in"
  cd $MMT_HOME && mkdir -p KohaImports$SRC_ILS && cp -r KohaImports/* KohaImports$SRC_ILS/ && tar -czf kohaData.tar.gz KohaImports$SRC_ILS
  test $? != 0 && echo "Packing Koha data failed!" && exit 10

  scp -r $MMT_HOME/kohaData.tar.gz $KOHA_HOST:$KOHA_HOME
  test $? != 0 && echo "Uploading Koha data failed!" && exit 11

  ssh $KOHA_HOST "cd $KOHA_HOME && tar -xzf $KOHA_HOME/kohaData.tar.gz && rm $KOHA_HOME/kohaData.tar.gz && chown -R koha:koha $KOHA_HOME/KohaImports$SRC_ILS"
  test $? != 0 && echo "Unpacking Koha data remotely failed!" && exit 12

  ssh $KOHA_HOST "mkdir -p $KOHA_LOAD_WORKING_DIR && chown koha:koha $KOHA_LOAD_WORKING_DIR"
  test $? != 0 && echo "Creating load-phase working dir remotely failed!" && exit 13

  echo "Start loading"
  ssh -t $KOHA_HOST "cd $KOHA_LOADER_DIR && su -c '$KOHA_LOADER_CMD' koha"
  test $? != 0 && echo "Loading Koha data failed!" && exit 14
elif [ -z "$KOHA_HOST" ]; then
  echo "Link the loadable files for Loader default path"
  test ! -e $KOHA_HOME/KohaImports$SRC_ILS && (ln -s $MMT_HOME/KohaImports $KOHA_HOME/KohaImports$SRC_ILS || (echo "Linking Koha data failed!" && exit 10))

  mkdir -p $KOHA_LOAD_WORKING_DIR && chown koha:koha $KOHA_LOAD_WORKING_DIR
  test $? != 0 && echo "Creating load-phase working dir remotely failed!" && exit 13

  echo "Start loading"
  cd $MMT_PROGRAM_DIR/loader/KohaLoader && su -c "$KOHA_LOADER_CMD" koha
  test $? != 0 && echo "Loading Koha data failed!" && exit 14
fi

