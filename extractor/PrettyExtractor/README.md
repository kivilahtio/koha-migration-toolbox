# PrettyLib/Circ Extractor

## INSTALLATION

- Make sure you have credentials for the file server where the database dumps are exported to. Username, password, hostname, directory.

- Deploy all the files in this folder to the MS SQL Server.

Withing the SQL SERVER:

- Configure ODBC interfaces using the Microsoft ODBC Data Source Administrator for the desired databases. MAKE SURE YOU ENABLE 'Perform translation for character data'.

- Configure the extract.pl tool's config.perl to use the configured ODBC data sources, and the export/shipping remote file server access. One separate config.perl-file needs to be created for both PrettyLib and PrettyCirc databases. Make sure they export to different export directories.

- Schedule the extract.pl to be ran daily via the "Task Scheduler"-program. extract.pl needs the following commandline parameters; --extract --ship --workingDir "C:\Absolute\Path\To\Directory\Of\extract.pl"

- Make sure to manually test data exporting first. See "perl extract.pl --help" for more information.

