#!/bin/bash
#
# This script is just a helper wrapper for migrate.pl so one can run the whole shizang with one shebang.
#

#Override MMT_HOME to support multiple pipelines on one control/transformation machine
test ! -z $1 && MMT_HOME=$1



MMT_HOME="$MMT_HOME" perl migrate.pl --extract --biblios --items --patrons --issues --fines --reserves --serials --subscriptions --load

