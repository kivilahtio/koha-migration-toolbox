use Modern::Perl;
use autodie;
use open qw(:utf8);

use File::Slurp;
use Data::Printer;
use List::Util qw(pairs);
use Getopt::Long qw(:config no_ignore_case);


GetOptions(
    'h|help'        => sub {
      print <<HELP;

$0 - Takes MARC21 MFHD-Records in XML-format and analyzes what subfields they contain, and counts how many times each subfield is used and how many times each individual subfields data-content is used.

This is a glorified version of a typical

    grep | sort | uniq -c

pipeline

Writes the following filestructure:

$ ls fenn*
fennica.852        fennica.852a.dist  fennica.852d.dist  fennica.852g       fennica.852j       fennica.852m       fennica.852t       fennica.852x
fennica.8522       fennica.852b       fennica.852.dist   fennica.852g.dist  fennica.852j.dist  fennica.852m.dist  fennica.852t.dist  fennica.852x.dist
fennica.8522.dist  fennica.852b.dist  fennica.852e       fennica.852h       fennica.852k       fennica.852p       fennica.852u       fennica.852z
fennica.8528       fennica.852c       fennica.852e.dist  fennica.852h.dist  fennica.852k.dist  fennica.852p.dist  fennica.852u.dist  fennica.852z.dist
fennica.8528.dist  fennica.852c.dist  fennica.852f       fennica.852i       fennica.852l       fennica.852q       fennica.852v
fennica.852a       fennica.852d       fennica.852f.dist  fennica.852i.dist  fennica.852l.dist  fennica.852q.dist  fennica.852v.dist

Reads MFHD XML Records from files in src/ -dir

HELP
    },
) or exit 1;


$ENV{DEBUG} = 0;

my @db = qw(hamk viola fennica);
for my $db (@db) {
  print "Analyzing '$db'\n";

  my %FH;
  open($FH{'852'},     '>', "$db.852"); #all fields 852
  open($FH{'852DIST'}, '>', "$db.852.dist"); #How are the subfield codes used?

  my $f = File::Slurp::read_file("src/$db");
  my @m = $f =~ m!(<datafield tag="852" ind1="." ind2=".">.+?</datafield>)!gsm; #Pick 852
  print { $FH{'852'} } join("\n", @m)."\n";

  my %dist; #collect subfield distributions here

  for my $f852 (@m) {

    my @m2 = $f852 =~ m!<subfield code="(.)">(.*?)</subfield>!gsm;
    p(@m2) if $ENV{DEBUG};

    for (my $i=0 ; $i<@m2 ; $i+=2) {
      my ($code, $data) = ($m2[$i], $m2[$i+1]);

        open($FH{"852$code"}, '>', "$db.852$code") unless $FH{"852$code"}; #subfield contents
        open($FH{"852$code.dist"}, '>', "$db.852$code.dist") unless $FH{"852$code.dist"}; #subfield contents

        print { $FH{"852$code"} } "$data\n";

        $dist{sf}{$code} = ($dist{sf}{$code}) ? $dist{sf}{$code}+1 : 1;
        $dist{data}{$code}{$data} = ($dist{data}{$code}{$data}) ? $dist{data}{$code}{$data}+1 : 1;
    }
  }

  print { $FH{'852DIST'} } map { sprintf("%-10s %-70s\n", $dist{sf}{$_}, $_) } sort keys %{$dist{sf}};

=head #FYI: A famous Perl one-liner could be made here, but for sake of any readability such a challenge is skipped here.
  for my $code (keys %{$dist{data}}) {
    my $h = $dist{data}{$code};

    print { $FH{"852$code.dist"} } map {
      sprintf("%-10s %-70s\n", $h->{$_}, $_)
    } keys %{$h};
  }
=cut #LOL just kidding mate!

  print { $FH{"852$_.dist"} } map {
      sprintf("%-10s %-70s\n", $_->[1], $_->[0])
    } sort {$a->[0] cmp $b->[0]} pairs %{$dist{data}{$_}} for (sort keys %{$dist{data}});
}
