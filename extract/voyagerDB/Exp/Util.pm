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

package MMT::Util;

#Pragmas
use warnings;
use strict;

#External modules
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

=head2 NAME

Exp::Util

=head2 DESCRIPTION

Misc stuff

=cut

use Exp::DB;

sub toUtf8($) { # hacky, hacky, hacky...
  my $val = $_[0];
  my $orig_val = $val;
  my $printed = 0;
  use bytes;
  my $str = '';
  if ( $orig_val =~ /^[0-9]{5}[acdnp]....22/ ) { # marc-tietue vissiin
    # Koko ei saa muuttua...
  }
  else {
    # Eivät mene tietueisiin, joten ei koolla niin väliä
    $val =~ s/\xC3/Ã/g;
    $val =~ s/\xC4/Ä/g;
    $val =~ s/\xC5/Å/g;
    $val =~ s/\xC9/É/g;
    $val =~ s/\xD6/Ö/g;
    $val =~ s/\xE4/ä/g;
    $val =~ s/\xE5/å/g;
    $val =~ s/\xF6/ö/g;
    $val =~ s/\xFC/ü/g;
  }

  while ( length($val) ) {
    my $hit = 0;
    while ( $val =~ s/^([\000-\177]+)//s ||
	    $val =~ s/^([\300-\337][\200-\277])//s ||
	    $val =~ s/^([\340-\357][\200-\277]{2})//s ||
	    $val =~ s/^([\360-\367][\200-\277]{3})//s ) {
      $str .= $1;
      $hit = 1;
    }
    if ( !$hit ) {
      my $c = substr($val, 0, 1); # skip first char
      print STDERR "SKIP '$c'";
      if ( $orig_val =~ /^[0-9]{5}[acdnp]....22/ ) { # marc-tietue vissiin
      	$str .= '?'; # Säilytä koko...
      }
      if ( !$printed ) {
        print STDERR " in '$orig_val'\n";
        $printed = 1;
      }
      print STDERR "\n";
      $val = substr($val, 1); # skip first char
    }
  }

  no bytes;
  return $str;
}

sub isUtf8($) {
  use bytes;
  my ($val, $msg ) = @_;
  my $original_val = $val;
  my $i = 1;
  while ( $i ) {
    $i = 0;
    if ( $val =~ s/^[\000-\177]+//s ||
         $val =~ s/^([\300-\337][\200-\277])//s ||
         $val =~ s/^([\340-\357][\200-\277]{2})+//s ||
         $val =~ s/^([\360-\367][\200-\277]{3})+//s ) {
       $i=1;
    }
  }
  no bytes;
  if ( $val eq '' ) {
    return 1;
  }
#  #if ( $val !~ /^([\000-\177\304\326\344\366])+$/s ) {
#  my $reval = $val;
#  $reval =~ s/[\000-177]//g;
#  unless ( $reval =~ /^[\304\326\344\366]+$/ ) {
#    $i = ord($val);
#    my $c = chr($i);
#    #print STDERR "$msg: UTF8 Failed: '$c'/$i/'$val'\n$original_val\n";
#
#  }
  return 0;
}

return 1;
