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
use Cwd;

=head2 NAME

Exp::Config

=head2 DESCRIPTION

Configuration manager

=cut



our $config;
sub LoadConfig($) {
  my $filename = $_[0];
  $config = do $filename;
  unless ($config) {
    die "Configuration file '$filename' compilation failed: $@" if ($@);
    die "Configuration file '$filename' reading failed: $!" if ($!);
  }

  $config->{schema} = $config->{username} unless $config->{schema};
  $config->{exportDir} = '/tmp/'.$config->{schema} unless $config->{exportDir};
  print "Exporting to '".Cwd::realpath($config->{exportDir})."'\n";
  mkdir($config->{exportDir}, 0744) or die "Couldn't create the exportDir='".$config->{exportDir}."': $!"
    unless -e $config->{exportDir};
}

sub config() {
  return $config;
}

=head2 exportPath

 @param1 String, filename to export
 @returns String, the combined export path and the database name to be prepended to the given file path

=cut

sub exportPath($) {
  my ($filename) = @_;
  return $config->{exportDir}.'/'.$filename;
}

sub getTableEncoding($) {
  my ($table) = @_;
  return $config->{characterEncodings}->{$table} || $config->{characterEncodings}->{'_DEFAULT_'} || die("config->characterEncodings->_DEFAULT_ is not defined?");
}

sub getTableRepairs($) {
  my ($table) = @_;
  return $config->{characterEncodingRepairs}->{$table};
}

return 1;
