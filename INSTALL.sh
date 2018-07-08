#!/bin/bash
## IN THIS FILE
#
# Install MMT Voyager without needing sudo-privileges.
#

IS_PERLBREW_INSTALLED=`which perlbrew`
test $IS_PERLBREW_INSTALLED || ( echo "perlbrew is not installed, install it with 'apt install perlbrew'" && exit 1)


MMT_HOME="$HOME/MMT-Voyager" #Put configuration files here and preconfigure paths
MMT_CODE=`dirname $0` #Where this installer resides, resides the code to execute
test $MMT_CODE == "." && MMT_CODE=`pwd`
CONFIG_MAIN="$MMT_HOME/config/main.yaml"
VOYAGER_EXPORT_DIR="$MMT_HOME/VoyagerExports"
KOHA_IMPORT_DIR="$MMT_HOME/KohaImports"
LOG_DIR="$MMT_HOME/logs"
TEST_DIR="$MMT_HOME/tests"
EXTRACTOR_DIR="$MMT_CODE/extractor"
LOADER_DIR="$MMT_CODE/loader"


cd $MMT_CODE #Make sure we are in the source directory
test $? != 0 && echo "Couldn't cd to app source code directory '$MMT_CODE', failed with error code '$?'" && exit 7


echo "Installing Perl dependencies to the program dir '$MMT_CODE'"
perlbrew install-cpanm
test $? != 0 && echo "Couldn't install cpanminus via perlbrew, failed with error code '$?'" && exit 8
cpanm -L extlib --installdeps .
test $? != 0 && echo "Perl dependencies install failed with error code '$?'" && exit 9


echo "Configuring application home to '$MMT_HOME'"
mkdir -p $MMT_HOME           || exit 11
mkdir -p $VOYAGER_EXPORT_DIR || exit 11
mkdir -p $KOHA_IMPORT_DIR    || exit 11
mkdir -p $LOG_DIR            || exit 11
mkdir -p $TEST_DIR           || exit 11
cp -r config $MMT_HOME/      || exit 11
cp -r tests $MMT_HOME/       || exit 11
sed -i 's/^voyagerExportDir.+$/voyagerExportDir: "$VOYAGER_EXPORT_DIR"/' $CONFIG_MAIN
test $? != 0 && echo "Configuring file '$CONFIG_MAIN' with param 'voyagerExportDir' failed with error code '$?'" && exit 10
sed -i 's/^kohaImportDir.+$/kohaImportDir: "$KOHA_IMPORT_DIR"/' $CONFIG_MAIN
test $? != 0 && echo "Configuring file '$CONFIG_MAIN' with param 'kohaImportDir' failed with error code '$?'" && exit 11

echo "Persisting environment variables"
function setConf {
  name="$1"
  val="$2"
  dest="$3"
  if [[ `grep -P "$name" $dest` ]]
  then
    perl -pi.bak -e "s|^.*$name.+$|$name: $val|" $dest
  else
    echo "$name: $val" >> $dest
  fi
}

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

setConf "voyagerExportDir" "$VOYAGER_EXPORT_DIR" $CONFIG_MAIN
setConf "kohaImportDir"    "$KOHA_IMPORT_DIR"    $CONFIG_MAIN

echo <<STEPS
-----------------------
Awesome! MMT installed!
-----------------------
Now you need to do some manual steps.

- Firstly the Voyager extract scripts need to be deployed.
  You can do so by copying the whole $EXTRACTOR_DIR/voyagerDB/* to your
  Voyager DB server, for ex.
    scp -r $EXTRACTOR_DIR/voyagerDB/* username@voyager-server:~/
  See the $EXTRACTOR_DIR/voyagerDB/README for installation information


- A extract-phase connection script needs to be created and configured to make a
  connection to the Voyager DB server and extract data.
  You can find examples in $EXTRACTOR_DIR
  You must edit/create a script and configure MMT to use it.
  Set
    $CONFIG_MAIN -> exportPipelineScript
  to point into the extract-phase triggering script.


- A load-phase (import) connection script needs to be created and configured to
  make a connection to the Koha application server and load data in.
  You can find examples in $LOADER_DIR
  You must edit/create a script and configure MMT to use it.
  Set
    $CONFIG_MAIN -> importPipelineScript
  to point into the load-phase triggering script.

  Load-phase uses Koha's import tools, so no extra code needs to be deployed to
  the Koha server


STEPS

