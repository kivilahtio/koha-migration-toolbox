use MMT::Pragmas;

use FindBin;
use lib "$FindBin::Bin/../lib";
$ENV{MMT_HOME} = "$FindBin::Bin/../";
print "\nMMT_HOME => $FindBin::Bin/../\n";

use Test::Most tests => 1;
use Test::Differences;
use Test::MockModule;

use Time::HiRes;

use MMT::MARC::Regex;

use MMT::MARC::Record;

my @records = (
  <<RECORD,
<record format="MARC21" type="Bibliographic" xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00181cx  a22000853  4500</leader>
  <controlfield tag="001">3</controlfield>
  <controlfield tag="004">14</controlfield>
  <controlfield tag="005">20150520100954.0</controlfield>
  <controlfield tag="008">asd</controlfield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="h">371.3</subfield>
    <subfield code="i">TOISKALLIO</subfield>
  </datafield>
</record>
RECORD
  <<RECORD,
<record format="MARC21" type="Bibliographic" xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00181cx  a22000853  4500</leader>
  <controlfield tag="001">3</controlfield>
  <controlfield tag="004">14</controlfield>
  <datafield tag="111" ind1="2" ind2="6">
    <subfield code="s">333.3</subfield>
    <subfield code="o">666.6</subfield>
    <subfield code="b">1333.2</subfield>
  </datafield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="h">371.3</subfield>
    <subfield code="i">TOISKALLIO</subfield>
  </datafield>
  <datafield tag="852" ind1="4" ind2="2">
    <subfield code="h">84.2</subfield>
    <subfield code="i">APUA</subfield>
  </datafield>
</record>
RECORD
  <<RECORD,
<record>
  <datafield tag="100" ind1="1" ind2=" ">
    <subfield code="a">Huang, Paulos.</subfield>
  </datafield>
  <datafield tag="245" ind1="1" ind2="0">
    <subfield code="a">Kiina-suomi kaksisuuntainen puhekielen oppikirja =</subfield>
    <subfield code="b">Han Fen shuangxiang shi kouyu keben /</subfield>
    <subfield code="c">Paulos Huang.</subfield>
  </datafield>
</record>
RECORD
);

subtest "Transform a Bibliographic record", sub {
  plan tests => 5;

  subtest "_getPadding()", sub {
    plan tests => 2;
    is(MMT::MARC::Regex::_getPadding(\$records[0]), '  ', 'Got padding');
    is(MMT::MARC::Regex::_getPadding(\$records[1]), '  ', 'Got padding');
  };

  subtest "controlfield", sub {
    plan tests => 9;

    my $xml = $records[0];
    is(MMT::MARC::Regex->controlfield(\$xml, '001', '70',      {after => '001'}), 'replace', 'replace positioned');
    is(MMT::MARC::Regex->controlfield(\$xml, '003', 'FI-Hamk', {after => '001'}), 'after',   'after positioned');
    is(MMT::MARC::Regex->controlfield(\$xml, '006', '666',     {first => 1}),     'first',   'first positioned');
    is(MMT::MARC::Regex->controlfield(\$xml, '009', 'last',    {}),               'last',    'last positioned');
    is(MMT::MARC::Regex->controlfield(\$xml, '001'), '70',      'Get 001');
    is(MMT::MARC::Regex->controlfield(\$xml, '003'), 'FI-Hamk', 'Get 003');
    is(MMT::MARC::Regex->controlfield(\$xml, '009'), 'last',    'Get 009');

    ok(my $record = MMT::MARC::Record->newFromXml(\$xml), 'Can parse');

    eq_or_diff($xml, <<RECORD, 'Record ok');
<record format="MARC21" type="Bibliographic" xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00181cx  a22000853  4500</leader>
  <controlfield tag="006">666</controlfield>
  <controlfield tag="001">70</controlfield>
  <controlfield tag="003">FI-Hamk</controlfield>
  <controlfield tag="004">14</controlfield>
  <controlfield tag="005">20150520100954.0</controlfield>
  <controlfield tag="008">asd</controlfield>
  <controlfield tag="009">last</controlfield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="h">371.3</subfield>
    <subfield code="i">TOISKALLIO</subfield>
  </datafield>
</record>
RECORD
  };

  subtest "subfield", sub {
    plan tests => 14;

    my $xml = $records[0];
    is(MMT::MARC::Regex->subfield(\$xml, '852', 'h'), '371.3',      'Get 852$h');
    is(MMT::MARC::Regex->subfield(\$xml, '852', 'i'), 'TOISKALLIO', 'Get 852$i');

    is(MMT::MARC::Regex->subfield(\$xml, '852', 'h', '84.2'),                'replace',    'replace subfield 852$h 84.2');
    eq_or_diff($xml, <<RECORD, 'Record ok');
<record format="MARC21" type="Bibliographic" xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00181cx  a22000853  4500</leader>
  <controlfield tag="001">3</controlfield>
  <controlfield tag="004">14</controlfield>
  <controlfield tag="005">20150520100954.0</controlfield>
  <controlfield tag="008">asd</controlfield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="h">84.2</subfield>
    <subfield code="i">TOISKALLIO</subfield>
  </datafield>
</record>
RECORD

    is(MMT::MARC::Regex->subfield(\$xml, '852', 'i', 'POTTA'),               'replace',    'replace subfield 852$i POTTA');
    eq_or_diff($xml, <<RECORD, 'Record ok');
<record format="MARC21" type="Bibliographic" xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00181cx  a22000853  4500</leader>
  <controlfield tag="001">3</controlfield>
  <controlfield tag="004">14</controlfield>
  <controlfield tag="005">20150520100954.0</controlfield>
  <controlfield tag="008">asd</controlfield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="h">84.2</subfield>
    <subfield code="i">POTTA</subfield>
  </datafield>
</record>
RECORD

    is(MMT::MARC::Regex->subfield(\$xml, '852', 't', 'dik'),                 'last',       'last subfield 852$t dik');
    eq_or_diff($xml, <<RECORD, 'Record ok');
<record format="MARC21" type="Bibliographic" xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00181cx  a22000853  4500</leader>
  <controlfield tag="001">3</controlfield>
  <controlfield tag="004">14</controlfield>
  <controlfield tag="005">20150520100954.0</controlfield>
  <controlfield tag="008">asd</controlfield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="h">84.2</subfield>
    <subfield code="i">POTTA</subfield>
    <subfield code="t">dik</subfield>
  </datafield>
</record>
RECORD

    is(MMT::MARC::Regex->subfield(\$xml, '852', 'n', 'fi', {after => 'i'}),  'after',      'after subfield 852$n fi');
    eq_or_diff($xml, <<RECORD, 'Record ok');
<record format="MARC21" type="Bibliographic" xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00181cx  a22000853  4500</leader>
  <controlfield tag="001">3</controlfield>
  <controlfield tag="004">14</controlfield>
  <controlfield tag="005">20150520100954.0</controlfield>
  <controlfield tag="008">asd</controlfield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="h">84.2</subfield>
    <subfield code="i">POTTA</subfield>
    <subfield code="n">fi</subfield>
    <subfield code="t">dik</subfield>
  </datafield>
</record>
RECORD

    is(MMT::MARC::Regex->subfield(\$xml, '100', 'a', 'PRINKALA', {after => 't'}),  'last', 'new field via subfield 100$a PRINKALA');
    eq_or_diff($xml, <<RECORD, 'Record ok');
<record format="MARC21" type="Bibliographic" xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00181cx  a22000853  4500</leader>
  <controlfield tag="001">3</controlfield>
  <controlfield tag="004">14</controlfield>
  <controlfield tag="005">20150520100954.0</controlfield>
  <controlfield tag="008">asd</controlfield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="h">84.2</subfield>
    <subfield code="i">POTTA</subfield>
    <subfield code="n">fi</subfield>
    <subfield code="t">dik</subfield>
  </datafield>
  <datafield tag="100" ind1=" " ind2=" ">
    <subfield code="a">PRINKALA</subfield>
  </datafield>
</record>
RECORD

    is(MMT::MARC::Regex->subfield(\$xml, '852', 'a', 'FI-C', {first => 1}),  'first', 'prepend subfield 852$a FI-C');
    eq_or_diff($xml, <<RECORD, 'Record ok');
<record format="MARC21" type="Bibliographic" xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00181cx  a22000853  4500</leader>
  <controlfield tag="001">3</controlfield>
  <controlfield tag="004">14</controlfield>
  <controlfield tag="005">20150520100954.0</controlfield>
  <controlfield tag="008">asd</controlfield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="a">FI-C</subfield>
    <subfield code="h">84.2</subfield>
    <subfield code="i">POTTA</subfield>
    <subfield code="n">fi</subfield>
    <subfield code="t">dik</subfield>
  </datafield>
  <datafield tag="100" ind1=" " ind2=" ">
    <subfield code="a">PRINKALA</subfield>
  </datafield>
</record>
RECORD
  };

  subtest "datafield", sub {
    plan tests => 8;

    my $xml = $records[1];
    eq_or_diff(MMT::MARC::Regex->datafield(\$xml, '852')."\n", <<SF, 'Get 852');
    <subfield code="h">371.3</subfield>
    <subfield code="i">TOISKALLIO</subfield>
SF

    is(MMT::MARC::Regex->datafield(\$xml, '101', 'a', 'Aatu',  {after => '111'}),              'after',   'after positioned');
    is(MMT::MARC::Regex->datafield(\$xml, '100', 'a', 'Beetu', {first => 1}),                  'first',   'first positioned');
    is(MMT::MARC::Regex->datafield(\$xml, '999', undef, '<subfield code="a">bibi</subfield>'), 'last',    'last positioned, full contents');

    is(MMT::MARC::Regex->datafield(\$xml, '999')."\n", <<SF, 'Get 999');
    <subfield code="a">bibi</subfield>
SF
    is(MMT::MARC::Regex->datafield(\$xml, '100')."\n", <<SF, 'Get 100');
    <subfield code="a">Beetu</subfield>
SF

    ok(my $record = MMT::MARC::Record->newFromXml(\$xml), 'Can parse');

    eq_or_diff($xml, <<RECORD, 'Record ok');
<record format="MARC21" type="Bibliographic" xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00181cx  a22000853  4500</leader>
  <controlfield tag="001">3</controlfield>
  <controlfield tag="004">14</controlfield>
  <datafield tag="100" ind1=" " ind2=" ">
    <subfield code="a">Beetu</subfield>
  </datafield>
  <datafield tag="111" ind1="2" ind2="6">
    <subfield code="s">333.3</subfield>
    <subfield code="o">666.6</subfield>
    <subfield code="b">1333.2</subfield>
  </datafield>
  <datafield tag="101" ind1=" " ind2=" ">
    <subfield code="a">Aatu</subfield>
  </datafield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="h">371.3</subfield>
    <subfield code="i">TOISKALLIO</subfield>
  </datafield>
  <datafield tag="852" ind1="4" ind2="2">
    <subfield code="h">84.2</subfield>
    <subfield code="i">APUA</subfield>
  </datafield>
  <datafield tag="999" ind1=" " ind2=" ">
    <subfield code="a">bibi</subfield>
  </datafield>
</record>
RECORD
  };

  subtest "Fringe-cases", sub {
    my $xml = $records[2];

    is(MMT::MARC::Regex->subfield(\$xml, '100', 'b', 'B-PRINKALA', {after => 'a'}), 'after', 'Prevent subfield selection from skipping datafield boundaries');

    eq_or_diff($xml, <<RECORD, 'Record ok');
<record>
  <datafield tag="100" ind1="1" ind2=" ">
    <subfield code="a">Huang, Paulos.</subfield>
    <subfield code="b">B-PRINKALA</subfield>
  </datafield>
  <datafield tag="245" ind1="1" ind2="0">
    <subfield code="a">Kiina-suomi kaksisuuntainen puhekielen oppikirja =</subfield>
    <subfield code="b">Han Fen shuangxiang shi kouyu keben /</subfield>
    <subfield code="c">Paulos Huang.</subfield>
  </datafield>
</record>
RECORD
  }

};



done_testing;
