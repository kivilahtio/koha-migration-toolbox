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

package Exp::Encoding;

#Pragmas
use warnings;
use strict;

#External modules
use Carp;

=head2 NAME

Exp::Encoding

=head2 DESCRIPTION

Encoding subroutines. Separated to their own module due to the very experimental nature of the code.

=cut

use Exp::Config;

my $trace = 0;
sub decodeToPerlInternalEncoding($$) {
  my ($cols, $colEncodings) = @_;

  for (my $j=0; $j < @$cols; $j++) {
    next unless ($cols->[$j]);
    my $enc = $colEncodings->[$j];
    if ($trace) {
      #Try to find out what needs to be done to turn the Voyager data to Perl's internal strings correctly.
      #Show diagnostics about some approaches to find out what hexes we get and how those behave when encoded/decoded
      #Setting the Oracle UTF-8 export env variables on in Exp::DB::dbh complicates this some more
      $DB::single=1;
      my $o = $cols->[$j];
      binmode(STDOUT, ':raw');
      print "ORI: $o\n";
      print unpack( 'H*', $o).'   utf8flag:'.Encode::is_utf8($o)."\n";
      my $a = Encode::decode($enc, $cols->[$j]);
      print "DEC: $a\n";
      print unpack( 'H*', $a).'   utf8flag:'.Encode::is_utf8($a)."\n";
      my $a2 = Encode::encode('UTF-8', $cols->[$j]);
      print "DEC-UTF: $a2\n";
      print unpack( 'H*', $a2).'   utf8flag:'.Encode::is_utf8($a2)."\n";
      my $b = Encode::encode($enc, $cols->[$j]);
      print "ENC: $b\n";
      print unpack( 'H*', $b)."\n";
      my $b2 = Encode::decode('UTF-8', $cols->[$j]);
      print "ENC-UTF: $b2\n";
      print unpack( 'H*', $b2)."\n";
    }

    #normally just decode
    $cols->[$j] = Encode::decode($enc, $cols->[$j]) or die("Decoding '".$cols->[$j]."' failed: $!");
  }
}

=head2 toUtf8

Turns specific characters to utf8
@author Nicholas Volk
@returns String, new fixed value

=cut

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

=head2 isUtf8

Checks if this string contains utf8 graphemes
@author Nicholas Volk

=cut

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
