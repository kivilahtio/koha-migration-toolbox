use strict;
use warnings;
use utf8; #This file is utf8 encoded and so are all the strings within.

#just do this !
return {
  ########################
  ## Main configuration ##
  ########################

  oracle_home => '/oracle/app/oracle/product/12.1.0.2/db_1', #DBD::Oracle needs this
  sid => 'VERTA',
  host => '127.0.0.1',
  port => '1521',
  username => 'ahmed',
  password => 'ahne',

  #This should be 'Oracle' only, configured this way due to a limitation in IDE code analysis tools
  dbdriver => 'Oracle',

  exportDir => '../data', #The default is relative to the directory from where the extract.pl is ran.


  ######################################
  ## Character encoding configuration ##
  ######################################
  
  #Which Encoding post-fix regexp substitutions to run on which tables/files -> columns and transformations
  #Are done against the internal Perl stringified format after the Voyager inputs have been decoded to the configured character encoding.
  characterEncodingRepairs => {
    # ↓ Define files or tables to fix, depending on which export strategy is used.
    #                           ↓ column name to select for post-repair
    #                                   ↓ Regex representation of the string to search
    #                                                 ↓ Regex representation of the substitution
    '09-patron_notes.csv' => [['note', '\x{0080}' => '€']],
  },

  #Define the character encodings of Voyager tables here
  characterEncodings => {
    _DEFAULT_ => 'iso-8859-1',
    item_vw => 'UTF-8',
  },

};
