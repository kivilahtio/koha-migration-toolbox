#!/bin/bash
#
# This script is just a helper wrapper for migrate.pl so one can run the whole shizang with one shebang.
#

#Override MMT_HOME to support multiple pipelines on one control/transformation machine
test ! -z $1 && MMT_HOME=$1



MMT_HOME="$MMT_HOME" perl migrate.pl --extract       &> $MMT_HOME/logs/01-extract.log
MMT_HOME="$MMT_HOME" perl migrate.pl --biblios       &> $MMT_HOME/logs/02-biblios.log
MMT_HOME="$MMT_HOME" perl migrate.pl --items         &> $MMT_HOME/logs/03-items.log
MMT_HOME="$MMT_HOME" perl migrate.pl --patrons       &> $MMT_HOME/logs/04-patrons.log
MMT_HOME="$MMT_HOME" perl migrate.pl --issues        &> $MMT_HOME/logs/05-issues.log
MMT_HOME="$MMT_HOME" perl migrate.pl --fines         &> $MMT_HOME/logs/06-fines.log
MMT_HOME="$MMT_HOME" perl migrate.pl --reserves      &> $MMT_HOME/logs/07-reserves.log
MMT_HOME="$MMT_HOME" perl migrate.pl --serials       &> $MMT_HOME/logs/08-serials.log
MMT_HOME="$MMT_HOME" perl migrate.pl --subscriptions &> $MMT_HOME/logs/09-subscriptions.log
MMT_HOME="$MMT_HOME" perl migrate.pl --load          &> $MMT_HOME/logs/10-load.log

