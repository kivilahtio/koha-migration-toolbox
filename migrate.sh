#!/bin/bash
#
# This script is just a helper wrapper for transform.pl so one can run the whole shizang with one shebang.
#

#Override MMT_HOME to support multiple pipelines on one control/transformation machine
test ! -z $1 && MMT_HOME=$1
MMT_CONFIG="$MMT_HOME/config/main.yaml"

echo "MMT_HOME='$MMT_HOME'"
echo -e "Log output uses shell colouring. Remember to set your reader to accept the colour codes.\n \$> less -Rr <file>\n"

test ! -e "$MMT_CONFIG" && echo "\$MMT_CONFIG=$MMT_CONFIG doesn't exist. Aborting!" exit 2
SOURCE_SYSTEM=$(perl -e "use YAML; \$yaml = YAML::LoadFile('$MMT_CONFIG'); print \$yaml->{sourceSystemType};")
test -z "$SOURCE_SYSTEM" && echo "'sourceSystemType' is unknown. Couldn't parse it from \$MMT_CONFIG=$MMT_CONFIG. Aborting!" exit 3


LOG_DIR="$MMT_HOME/logs"

if [[ "$SOURCE_SYSTEM" =~ "Voyager" ]]; then
  echo "--extract"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --extract         &> $LOG_DIR/01-extract.log
  echo "--biblios"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --biblios         &> $LOG_DIR/02-biblios.log
  echo "--holdings"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --holdings        &> $LOG_DIR/03-holdings.log
  echo "--items"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --items           &> $LOG_DIR/04-items.log
  echo "--patrons"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --patrons         &> $LOG_DIR/05-patrons.log
  echo "--issues"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --issues          &> $LOG_DIR/06-issues.log
  echo "--fines"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --fines           &> $LOG_DIR/07-fines.log
  echo "--reserves"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --reserves        &> $LOG_DIR/08-reserves.log
  echo "--serials"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --serials         &> $LOG_DIR/09-serials.log
  echo "--subscriptions"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --subscriptions   &> $LOG_DIR/10-subscriptions.log
  echo "--branchtransfers"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --branchtransfers &> $LOG_DIR/11-branchtransfers.log
  echo "--load"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --load            &> $LOG_DIR/12-load.log
fi

if [[ "$SOURCE_SYSTEM" =~ "PrettyLib" ]]; then
  echo "--extract"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --extract         &> $LOG_DIR/00-extract.log
  echo "--biblios"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --biblios         &> $LOG_DIR/01-biblios.log
  echo "--items"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --items           &> $LOG_DIR/02-items.log
  echo "--patrons"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --patrons         &> $LOG_DIR/03-patrons.log
  echo "--issues"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --issues          &> $LOG_DIR/04-issues.log
  echo "--fines"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --fines           &> $LOG_DIR/05-fines.log
  echo "--load"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --load            &> $LOG_DIR/10-load.log
fi

if [[ "$SOURCE_SYSTEM" =~ "PrettyCirc" ]]; then
  echo "--extract"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --extract         &> $LOG_DIR/00-extract.log
  echo "--biblios"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --biblios         &> $LOG_DIR/01-biblios.log
  echo "--items"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --items           &> $LOG_DIR/02-items.log
  echo "--patrons"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --patrons         &> $LOG_DIR/03-patrons.log
  echo "--subscriptions"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --subscriptions   &> $LOG_DIR/03-subscriptions.log
  echo "--serials"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --serials         &> $LOG_DIR/04-serials.log
  echo "--load"
  MMT_HOME="$MMT_HOME" perl -Itransformer transformer/transform.pl --load            &> $LOG_DIR/10-load.log
fi

echo ""
echo "Data migration pipeline complete."
echo "Please carefully check all the logs in the log directory '$LOG_DIR'"
echo "Also logs are available in the Koha-instance's /home/koha/KohaMigration/bulk*.log"
echo ""
echo ""
echo "Thank you!"
echo ""
