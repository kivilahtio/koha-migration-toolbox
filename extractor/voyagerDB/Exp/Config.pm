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

package Exp::Config;

#Pragmas
use warnings;
use strict;

#External modules
use DBI;

=head2 NAME

Exp::Config

=head2 DESCRIPTION

Configuration manager

=cut



sub _LoadConfig($) {
  my $filename = $_[0];
  my $FH;
  my %config;
  open($FH, "<:raw", $filename) or die "Cannot open configuration file '$filename': $!";
  while (my $row = <$FH>) {
    $row =~ s/\s*$//s;
    $row =~ /\s*:\s*/;
    my $lhs = $`;
    my $rhs = $';
    $config{$lhs} = $rhs;
  }
  close($FH);


  $config{dbname} = $config{username};
  $config{exportDir} = '/tmp/'.$config{dbname} unless $config{exportDir};
  print "Exporting to '$config{exportDir}'\n";
  mkdir($config{exportDir}, 0744) or die "Couldn't create the exportDir='".$config{exportDir}."': $!"
    unless -e $config{exportDir};

  return \%config;
}
our $config = _LoadConfig($ENV{VOYAGER_EXPORTER_CONFIG_PATH});

=head2 exportPath

 @param1 String, filename to export
 @returns String, the combined export path and the database name to be prepended to the given file path

=cut

sub exportPath($) {
  my ($filename) = @_;
  return $config->{exportDir}.'/'.$config->{dbname}.'.'.$filename;
}

return 1;
