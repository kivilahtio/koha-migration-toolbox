BEGIN {
  use FindBin;
  use lib "$FindBin::Bin/../lib";
  $ENV{MMT_HOME} = "$FindBin::Bin/../";
  print "# MMT_HOME => $FindBin::Bin/../\n";
}

use MMT::Pragmas;

use Test::Most tests => 3;
use Test::Differences;
use Test::MockModule;

use MMT::MARC::Record;
use MMT::Voyager2Koha::Holding;

my @records = (
  <<RECORD,
<record xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00204cx  a22000973  4500</leader>
  <controlfield tag="001">113</controlfield>
  <controlfield tag="004">79</controlfield>
  <controlfield tag="005">20020628115341.0</controlfield>
  <controlfield tag="008">0206280p    8   4001auswe0000000</controlfield>
  <datafield tag="014" ind1="1" ind2=" ">
    <subfield code="a">EISI000078</subfield>
  </datafield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="a">HAMKLM</subfield>
    <subfield code="b">Hamklmhl</subfield>
    <subfield code="h">67.3 KONGL.</subfield>
  </datafield>
</record>
RECORD
  <<RECORD,
<record xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00184cx  a22000854  4500</leader>
  <controlfield tag="001">116</controlfield>
  <controlfield tag="004">80</controlfield>
  <controlfield tag="005">20180907150456.0</controlfield>
  <controlfield tag="008">0206282f    8   4001a fin0000000</controlfield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="a">Hamkr</subfield>
    <subfield code="b">Hamkropi</subfield>
    <subfield code="h">TIETO INS</subfield>
    <subfield code="i">TURKKILA</subfield>
  </datafield>
</record>
RECORD
  <<RECORD,
<record>
</record>
RECORD
);

require MMT::Cache;                                # Mock the 'SuppressInOpacMap' to return (Y)es
my $mmtCache = Test::MockModule->new('MMT::Cache');
$mmtCache->mock('get', sub { return [{suppress_in_opac => 'Y'}] });

require MMT::TranslationTable::LocationId;

require MMT::Voyager2Koha::Holding;
ok(my $builder = {
  SuppressInOpacMap => bless({}, 'MMT::Cache'),
  LocationId => MMT::TranslationTable::LocationId->new(),
}, "Given a HAMK preconfigured builder");

subtest "Transform a Holdings record with ccode", sub {
  plan tests => 2;

  my $kohaObject = MMT::Voyager2Koha::Holding->new();
  my $xml = $records[0];
  $kohaObject->build(\$xml, $builder);

  is($kohaObject->id(), 113, 'Holdings id ok');
  eq_or_diff($xml, <<RECORD, 'Record ok');
<record xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00204cx  a22000973  4500</leader>
  <controlfield tag="001">113</controlfield>
  <controlfield tag="003">FI-Hamk</controlfield>
  <controlfield tag="004">79</controlfield>
  <controlfield tag="005">20020628115341.0</controlfield>
  <controlfield tag="008">0206280p    8   4001auswe0000000</controlfield>
  <datafield tag="014" ind1="1" ind2=" ">
    <subfield code="a">EISI000078</subfield>
  </datafield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="a">FI-Hamk</subfield>
    <subfield code="b">HAMKL</subfield>
    <subfield code="c">MUS</subfield>
    <subfield code="g">LIN</subfield>
    <subfield code="h">67.3 KONGL.</subfield>
    <subfield code="n">fi</subfield>
  </datafield>
  <datafield tag="942" ind1=" " ind2=" ">
    <subfield code="n">Y</subfield>
  </datafield>
</record>
RECORD
};

subtest "Transform a Holdings record without a ccode or opac suppression", sub {
  plan tests => 2;
  $mmtCache->mock('get', sub { return [{suppress_in_opac => undef}] });

  my $kohaObject = MMT::Voyager2Koha::Holding->new();
  my $xml = $records[1];
  $kohaObject->build(\$xml, $builder);

  is($kohaObject->id(), 116, 'Holdings id ok');
  eq_or_diff($xml, <<RECORD, 'Record ok');
<record xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00184cx  a22000854  4500</leader>
  <controlfield tag="001">116</controlfield>
  <controlfield tag="003">FI-Hamk</controlfield>
  <controlfield tag="004">80</controlfield>
  <controlfield tag="005">20180907150456.0</controlfield>
  <controlfield tag="008">0206282f    8   4001a fin0000000</controlfield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="a">FI-Hamk</subfield>
    <subfield code="b">HAMKR</subfield>
    <subfield code="c">EI_KOHAAN</subfield>
    <subfield code="h">TIETO INS</subfield>
    <subfield code="i">TURKKILA</subfield>
    <subfield code="n">fi</subfield>
  </datafield>
</record>
RECORD
};

done_testing;
