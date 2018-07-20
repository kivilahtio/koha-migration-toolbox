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



return 1;
