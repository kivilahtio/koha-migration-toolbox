#!/usr/bin/env perl

=head2 SYNOPSIS

Script to do in-place FinMARC to MARC21 migration for a live Koha instance.
You should do the format conversion in the transform-phase instead.
But sometimes one might forget :)

=cut

use Modern::Perl;

use File::Slurp;
use MARC::File::XML;
use MARC::Record;

use C4::Context;
use C4::Biblio;

my $dbh = C4::Context->dbh();

print "----LOADING FROM DB\n";
my %rr;
my @rs = $dbh->selectall_array("SELECT b.biblionumber, b.frameworkcode, metadata FROM biblio_metadata bm LEFT JOIN biblio b ON b.biblionumber = bm.biblionumber WHERE datecreated = '2020-01-02'");

open(my $FH, ">:encoding(UTF-8)", "finmarc.xml") or die $!;

print $FH '<?xml version="1.0"?>';
print $FH '<collection xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd" xmlns="http://www.loc.gov/MARC21/slim">"';

print "----WRITING TO FILE\n";
for (@rs) {
  my $bn = $_->[0];
  #Make sure 999$c and $d contain biblionumber!
  if ($_->[2] !~ m!<datafield tag="999" ind1=!gsm) {
    if ($_->[2] !~ s!</record>!  <datafield tag="999" ind1=" " ind2=" ">\n    <subfield code="c">$bn</subfield>\n    <subfield code="d">$bn</subfield>\n  </datafield>\n</record>!gsm) {
      warn "Coudln't inject biblionumber to ".$_->[2];
    }
  }
  print $FH $_->[2]."\n";
  $rr{$bn} = {bn => $bn, frameworkcode => $_->[1]};
}

print $FH '</collection>';

close($FH);



print "----USEMARCON\n";
system('./usemarcon', 'USEMARCON-fi2ma/fi2ma.ini', 'finmarc.xml', 'marc21.xml') or die $!;

my $m21 = File::Slurp::read_file('marc21.xml');
my @r_xmls = ($m21 =~ m!(<record format="MARC21" type="Bibliographic">.+?</record>)!gsm);

my $marcflavour = C4::Context->preference('marcflavour');
MARC::File::XML->default_record_format($marcflavour);
print "----WRITE TO DB\n";
for my $r_xml (@r_xmls) {
  my $r = MARC::Record::new_from_xml($r_xml, "utf8", $marcflavour);

  remove382b($r);

  my $bn;
  if ($r_xml =~ m!<datafield tag="999" ind1=" " ind2=" ">\n    <subfield code="c">(\d+)</subfield>!gsm) {$bn = $1;}
  else {warn "Couldn't parse biblionumber from '$r_xml'";}
  if (!C4::Biblio::ModBiblio($r, $bn, $rr{$bn}->{frameworkcode})) {
    warn "modbiblio failed for ".$r_xml."\n";
  }
}


#FinMARC 526$b pois ####
sub remove382b {
  my $r = $_[0];
  my $f382 = $r->field('382');
  if ($f382 && $f382->subfield('b') && $f382->subfield('b') =~ m/###/) {
    $f382->delete_subfield(code => 'b');
  }
  if ($f382 && scalar($f382->subfields) == 0) {
    $r->delete_fields($f382);
  }
}
