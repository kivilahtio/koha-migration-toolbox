# This file is part of koha-migration-toolbox
#
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with koha-migration-toolbox; if not, see <http://www.gnu.org/licenses>.
#

package Exp::DB;

#Pragmas
use warnings;
use strict;

#External modules
use DBI;
use Carp;

=head2 NAME

Exp::DB

=head2 DESCRIPTION

DB accessors

=cut

use Exp::Config;

=head2 dbh

 @returns DBI::Oracle, database handle

=cut

my $dbh;
sub dbh {
  return $dbh if $dbh && $dbh->ping();

  my $config = Exp::Config::config();

  #Try to get Oracle to send UTF-8 with 05-patron-address.csv
  #This doesn't work very nicely. Oracle sets the utf8-flag on, but actually doesn't convert it's internal encoding (latin1) to UTF-8
  #$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8'; #Straight from the DBD::Oracle docs. WTF is the American language?
  #$ENV{NLS_NCHAR} = 'AL32UTF8'; #Tell Oracle to output UTF-8 . Looks like this doesn't do anything.

  #Try to get Oracle to send UTF-8 with 02-items.csv
  #Same problem, even worse, "ä" becomes hexes "FD FD"
  #$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
  #$ENV{NLS_NCHAR} = 'AL32UTF8';


  $ENV{ORACLE_HOME} = $config->{oracle_home}; #DBD::Oracle needs this
  die "Configuration variable 'oracle_home' is undefined. DBD::Oracle needs to know where the Oracle files are"
    unless ($ENV{ORACLE_HOME});
  die "Configuration variable 'oracle_home' is not readable. DBD::Oracle needs to access the Oracle files"
    unless (-r $ENV{ORACLE_HOME});

  my $dataSource =  'dbi:'.$config->{dbdriver}.':'. #Workaround to remove DBD::Oracle from compile time syntax checking, because installing DBD::Oracle locally needs some extra Oracle-files
                    'host='.$config->{host}.';'.
                    'sid='.$config->{sid}.';'.
                    'port='.$config->{port};
  warn "Init connection to $dataSource, username=".$config->{username}."\n" if ($ENV{DEBUG});
  $dbh = DBI->connect($dataSource, $config->{username}, $config->{password})
    || confess "Could no connect: $DBI::errstr";

  $dbh->do("ALTER SESSION SET nls_date_format = 'yyyy-mm-dd\"T\"hh24:mi:ss'"); #ISO8601 as the default format. Only lower case variable name works here.
  return $dbh;
}

=head2 mfhd_id2bib_ids

Voyager has bound records, which share the same MFHD-record.
So $004 doesn't always cut it as it (apparently) can store only one value.

 @returns ARRAYRef, bib ids that the given MFHD record references to
 @author Nicholas Volk

=cut

my $mfhd_id2bib_id_sth;
sub mfhd_id2bib_ids($) {
  my ($mfhdId) = @_;

  $mfhd_id2bib_id_sth = dbh->prepare("SELECT BIB_ID FROM BIB_MFHD WHERE MFHD_ID=?") || confess $dbh->errstr
    unless $mfhd_id2bib_id_sth;

  $mfhd_id2bib_id_sth->execute($mfhdId) || confess $dbh->errstr;
  my @bibIds;
  while (my @row = $mfhd_id2bib_id_sth->fetchrow_array) {
    push(@bibIds, $row[0]);
  }
  return \@bibIds;
}

=head2 bib_id2bib_record

 @returns String, The complete ISO-record from DB as is.
 @author Nicholas Volk

=cut

my $bib_id2bib_record_sth;
sub bib_id2bib_record($) {
  my ($bibId) = @_;

  $bib_id2bib_record_sth = dbh->prepare("SELECT RECORD_SEGMENT FROM BIB_DATA WHERE BIB_ID=? ORDER BY SEQNUM") || confess $dbh->errstr
    unless $bib_id2bib_record_sth;

  $bib_id2bib_record_sth->execute($bibId) || confess $dbh->errstr;
  my @marcdata;
  while (my @row = $bib_id2bib_record_sth->fetchrow_array) {
    push(@marcdata, $row[0]);
  }
  my $rv = join("", @marcdata);
  warn __PACKAGE__."::bib_id2bib_record($bibId):> Returns $rv\n" if ($ENV{DEBUG});
  return $rv;
}

return 1;
