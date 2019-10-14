## IN THIS FILE
##
## PrettyLib/Circ database extraction script configuration
##
## This file should always be next to the extract.pl-script and be named config.perl
## This is a pure-perl config entity so no funny config file parsing is needed.
##

return {
  # The Name of the ODBC (D)ata (S)ource (N)ame to connect into the system.
  # You must use the Windows ODBC Data Source Administration tool to configure
  # a PrettyLib/Circ as ODBC data source to be accessible for the Perl's DBD::ODBC -driver.
  db_dsn => "",

  # Depending on how the Windows user is authorized to access various resources this might be the username
  # of the Windows-user account or a specific DB account.
  db_username => "",

  # Same as above, not needed if authorizing as the Windows system user.
  db_password => "",

  # The "database" name, eg. PrettyLib or PrettyCirc, or whatever is the name of the DB
  db_catalog => "PrettyLib",

  # Schema withing the DB. Typically odb
  db_schema => "dbo",

  # This is only needed if doing introspection for a specific table. Should be left emtpy.
  db_table => "",

  # Directory where to export the table dumps
  export_path => "",

  # The ODBC-driver can do some really really strange things with UTF-8 decoding.
  # Marking Strings as UTF-8, but actually leaving them in the native DB encoding.
  # This 
  db_reverse_decoding => 1,
};
