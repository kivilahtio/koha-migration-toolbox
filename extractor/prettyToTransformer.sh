#!/bin/bash -x

## IN THIS FILE
##
## Makes a ssh-connection from the transformation-server to the Pretty database dump fileserver.
## PrettyExtractor from the PrettyExtractor-dir needs to be manually deployed to the Windows-server and schedule to be ran nightly.
## Uses scp to copy all the files to the transformer to do it's job.
##
## This is an example implementation of the data extraction pipeline automation.
## You must write your own which will work in your environment.

which sshpass
test $? != 0 && echo "sshpass is not installed. Install it with 'apt install sshpass'" && exit 10

test -z "$MMT_HOME" && echo "Environmental variable MMT_HOME is not defined!" && exit 7

. "$MMT_HOME/secret/pretty.credentials.sh" || (echo "Sourcing the secret/credentials.sh for credentials failed." && exit 10) # source the above access credentials


# Pull the files
sshpass -p "$SSH_PASS" sftp -r "$SSH_USER"@$SSH_SERVER:"$SSH_REMOTE_DIR" "$MMT_HOME/PrettyLibExports/"

