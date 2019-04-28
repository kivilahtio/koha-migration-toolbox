#!/bin/bash -x

## IN THIS FILE
##
## Explains that the PrettyLib's MS SQL Server needs to be manually dumped.
##
## This is an example implementation of the data extraction pipeline automation.
## You must write your own which will work in your environment.

echo "You must extract PrettyLib/Circ database tables in .csv-format, where each column is quoted and comma separated."
echo "Those tables must be put to '$MMT_HOME/PrettyLibExports'"

