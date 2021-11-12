#!/bin/bash
## IN THIS FILE
#
# Install MMT Voyager without needing sudo-privileges.
#

IS_CPANM_INSTALLED=`which cpanm`
test $IS_CPANM_INSTALLED || ( echo "cpanm is not installed, install it with 'apt install cpanminus'" && exit 1)

if [ -z "$MMT_HOME" ]; then
  MMT_HOME="$HOME/MMT-Voyager" #Put configuration files here and preconfigure paths
  echo "MMT_HOME not defined, installing to default directory '$MMT_HOME'"
  echo "Is this acceptable? <Ctrl+C to abort, ENTER to accept>"
  read -t 10 -p "Your answer: "
else
  echo "Installing to MMT_HOME='$MMT_HOME'"
fi
MMT_CODE=`dirname $0` #Where this installer resides, resides the code to execute
test $MMT_CODE == "." && MMT_CODE=`pwd`
CONFIG_MAIN="$MMT_HOME/config/main.yaml"
VOYAGER_EXPORT_DIR="VoyagerExports"
KOHA_IMPORT_DIR="KohaImports"
LOG_DIR="$MMT_HOME/logs"
TEST_DIR="$MMT_HOME/tests"
EXTRACTOR_DIR="$MMT_CODE/extractor"
EXTRACTOR_PIPELINE_SCRIPT="voyagerToTransformer.sh"
LOADER_DIR="$MMT_CODE/loader"
LOADER_PIPELINE_SCRIPT="transformerToKoha.sh"
PIPELINE_SCRIPTS="$MMT_HOME/"

cd $MMT_CODE #Make sure we are in the source directory
test $? != 0 && echo "Couldn't cd to app source code directory '$MMT_CODE', failed with error code '$?'" && exit 7


echo "Installing Perl dependencies to the program dir '$MMT_CODE'"
cd transformer
cpanm -L extlib --installdeps .
# Ubuntu 18 fails on one of the dependencies, unless --force is used...
if [ $? != 0 ]
then
  echo "Perl dependencies install failed with error code '$?'. Using force." && cpanm -L extlib --force --installdeps .
  test $? != 0 && echo "Perl dependencies install failed with error code '$?'. Force did not help." && exit 9
fi
cd ..


echo "Configuring application home to '$MMT_HOME'"
mkdir -p $MMT_HOME                     || exit 11
mkdir -p $MMT_HOME/$VOYAGER_EXPORT_DIR || exit 11
mkdir -p $MMT_HOME/$KOHA_IMPORT_DIR    || exit 11
mkdir -p $LOG_DIR                      || exit 11
mkdir -p $TEST_DIR                     || exit 11
mkdir -p $PIPELINE_SCRIPTS             || exit 11
cp -r config $MMT_HOME/                || exit 11
cp -r tests $MMT_HOME/                 || exit 11
cp config/seed.gitignore $MMT_HOME/.gitignore || exit 11
cp $EXTRACTOR_DIR/$EXTRACTOR_PIPELINE_SCRIPT $PIPELINE_SCRIPTS/ || exit 12
cp $LOADER_DIR/$LOADER_PIPELINE_SCRIPT $PIPELINE_SCRIPTS/ || exit 12


echo "Persisting environment variables"
export MMT_HOME=$MMT_HOME
export MMT_CODE=$MMT_CODE
if [[ `grep -P 'MMT_HOME' $HOME/.bashrc` ]]
then
  perl -pi.bak -e "s|^.+MMT_HOME.+$|export MMT_HOME=$MMT_HOME|" $HOME/.bashrc
else
  echo "export MMT_HOME=$MMT_HOME" >> $HOME/.bashrc
fi
if [[ `grep -P 'MMT_CODE' $HOME/.bashrc` ]]
then
  perl -pi.bak -e "s|^.+MMT_CODE.+$|export MMT_CODE=$MMT_CODE|" $HOME/.bashrc
else
  echo "export MMT_CODE=$MMT_CODE" >> $HOME/.bashrc
fi


cat <<STEPS
-----------------------
Awesome! MMT installed!
-----------------------
Working directory is '$MMT_HOME'.
Now you need to do some manual steps.

1)
  A extract-phase connection script needs to be created and configured to make a
  connection to the Voyager DB server and extract data.
  You can find examples in $EXTRACTOR_DIR
  You must edit/create a script and configure MMT to use it.
  Set
    $CONFIG_MAIN -> exportPipelineScript
  to point into the extract-phase triggering script.

  A default script is placed for you into a default position.

2)
  A load-phase (import) connection script needs to be created and configured to
  make a connection to the Koha application server and load data in.
  You can find examples in $LOADER_DIR
  You must edit/create a script and configure MMT to use it.
  Set
    $CONFIG_MAIN -> importPipelineScript
  to point into the load-phase triggering script.

  A default script is placed for you into a default position.

3)
  You probably want to version control your MMT configuration at '$MMT_HOME'
  A default .gitignore has been provided.


STEPS

