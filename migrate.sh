#!/bin/bash
#
# This script is just a helper wrapper for migrate.pl so one can run the whole shizang with one shebang.
#

#perl migrate.pl --biblios --items --patrons --issues --fines --reserves --serials --subscriptions
perl migrate.pl --patrons --issues --fines --reserves --serials --subscriptions

