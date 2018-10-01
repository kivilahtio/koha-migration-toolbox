use MMT::Pragmas;

use FindBin;
use lib "$FindBin::Bin/../lib";
$ENV{MMT_HOME} = "$FindBin::Bin/../";
print "\nMMT_HOME => $FindBin::Bin/../\n";

use Test::Most tests => 1;
use Test::Differences;
use Test::MockModule;

use Devel::Size;
use Time::HiRes;

use MMT::MARC::Regex;

use MMT::MARC::Record;
use MARC::Record;
use MARC::File::XML;

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
);

subtest "Performance", sub {
  my $iterations = 1000;

  subtest "MMT::MARC::Record", sub {
    my $totalTime = Time::HiRes::gettimeofday();;

    my $time = Time::HiRes::gettimeofday();
    for (1..$iterations) {
      my $r = MMT::MARC::Record->newFromXml(\$records[1]);
    }
    $time = (Time::HiRes::gettimeofday - $time) * 1000;
    ok(1, "'$iterations' Records parsed in '$time' microseconds");


    my $r = MMT::MARC::Record->newFromXml(\$records[1]);
    $time = Time::HiRes::gettimeofday();
    for (1..$iterations) {
      $r->getControlfield('001')->content();
      $r->getControlfield('004')->content();
      $r->getUnrepeatableSubfield('111', 's')->content();
      $r->getUnrepeatableSubfield('111', 'b')->content();
      $r->getUnrepeatableSubfield('852', 'h')->content();
      $r->getUnrepeatableSubfield('852', 'i')->content();
    }
    $time = (Time::HiRes::gettimeofday - $time) * 1000;
    ok(1, "'".($iterations*6)."' lookups in '$time' microseconds");


    my $sizeStart = Devel::Size::total_size($r);
    $time = Time::HiRes::gettimeofday();
    for (1..$iterations) {
      $r->getControlfield('001')->content(rand(1000));
      $r->getControlfield('004')->content(rand(1000));
      $r->getUnrepeatableSubfield('111', 's')->content(rand(1000));
      $r->getUnrepeatableSubfield('852', 'h')->content(rand(1000));
      my $f = $r->addField('888');
      $f->addSubfield('a', rand(1000));
      $f->addSubfield('b', rand(1000));
      $f = $r->addField('777');
      $f->addSubfield('a', rand(1000));
      $f->addSubfield('b', rand(1000));
    }
    $time = (Time::HiRes::gettimeofday - $time) * 1000;
    my $sizeEnd = Devel::Size::total_size($r);
    ok(1, "'".($iterations*8)."' mutations in '$time' microseconds");
    ok(1, "Memory footprint grew from '$sizeStart' to '$sizeEnd' bytes");


    $r = MMT::MARC::Record->newFromXml(\$records[1]);
    $time = Time::HiRes::gettimeofday();
    for (1..$iterations) {
      $r->serialize();
    }
    $time = (Time::HiRes::gettimeofday - $time) * 1000;
    ok(1, "'$iterations' Records serialized in '$time' microseconds");


    $totalTime = Time::HiRes::gettimeofday() - $totalTime;
    ok(1, "Tests done in '$totalTime' seconds");
  };

  subtest "MARC::Record", sub {
    my $totalTime = Time::HiRes::gettimeofday();;

    my $time = Time::HiRes::gettimeofday();
    for (1..$iterations) {
      my $r = MARC::Record->new_from_xml($records[1], 'UTF-8', 'MARC21');
    }
    $time = (Time::HiRes::gettimeofday - $time) * 1000;
    ok(1, "'$iterations' Records parsed in '$time' microseconds");


    my $r = MARC::Record->new_from_xml($records[1], 'UTF-8', 'MARC21');
    $time = Time::HiRes::gettimeofday();
    for (1..$iterations) {
      $r->field('001')->data();
      $r->field('004')->data();
      $r->field('111')->subfield('s');
      $r->field('111')->subfield('b');
      $r->field('852')->subfield('h');
      $r->field('852')->subfield('i');
    }
    $time = (Time::HiRes::gettimeofday - $time) * 1000;
    ok(1, "'".($iterations*6)."' lookups in '$time' microseconds");


    my $sizeStart = Devel::Size::total_size($r);
    $time = Time::HiRes::gettimeofday();
    for (1..$iterations) {
      $r->field('001')->update(rand(1000));
      $r->field('004')->update(rand(1000));
      $r->field('111')->update(s => rand(1000));
      $r->field('852')->update(h => rand(1000));
      $r->add_fields('888', "1", "0", a => rand(1000), b => rand(1000));
      $r->add_fields('777', "1", "0", a => rand(1000), b => rand(1000));
    }
    $time = (Time::HiRes::gettimeofday - $time) * 1000;
    my $sizeEnd = Devel::Size::total_size($r);
    ok(1, "'".($iterations*8)."' mutations in '$time' microseconds");
    ok(1, "Memory footprint grew from '$sizeStart' to '$sizeEnd' bytes");


    $r = MARC::Record->new_from_xml($records[1], 'UTF-8', 'MARC21');
    $time = Time::HiRes::gettimeofday();
    for (1..$iterations) {
      $r->as_formatted();
    }
    $time = (Time::HiRes::gettimeofday - $time) * 1000;
    ok(1, "'$iterations' Records serialized in '$time' microseconds");


    $totalTime = Time::HiRes::gettimeofday() - $totalTime;
    ok(1, "Tests done in '$totalTime' seconds");
  };

  subtest "MMT::MARC::Regex", sub {
    my $totalTime = Time::HiRes::gettimeofday();;

    my $time = Time::HiRes::gettimeofday();
    for (1..$iterations) {
      my $r = \$records[1]; #No need to parse, since we deal with the original text transfer form reference
    }
    $time = (Time::HiRes::gettimeofday - $time) * 1000;
    ok(1, "'$iterations' Records parsed in '$time' microseconds");


    my $r = \$records[1];
    $time = Time::HiRes::gettimeofday();
    for (1..$iterations) {
      MMT::MARC::Regex->controlfield($r, '001');
      MMT::MARC::Regex->controlfield($r, '004');
      MMT::MARC::Regex->subfield($r, '111', 's');
      MMT::MARC::Regex->subfield($r, '111', 'b');
      MMT::MARC::Regex->subfield($r, '852', 'h');
      MMT::MARC::Regex->subfield($r, '852', 'i');
    }
    $time = (Time::HiRes::gettimeofday - $time) * 1000;
    ok(1, "'".($iterations*6)."' lookups in '$time' microseconds");


    my $sizeStart = Devel::Size::total_size($r);
    $time = Time::HiRes::gettimeofday();
    for (1..$iterations) {
      MMT::MARC::Regex->controlfield($r, '001', rand(1000));
      MMT::MARC::Regex->controlfield($r, '004', rand(1000));
      MMT::MARC::Regex->subfield($r,  '111', 's', rand(1000));
      MMT::MARC::Regex->subfield($r,  '852', 'h', rand(1000));
      MMT::MARC::Regex->datafield($r, '888', 'a', rand(1000));
      MMT::MARC::Regex->subfield($r,  '888', 'b', rand(1000));
      MMT::MARC::Regex->datafield($r, '777', 'a', rand(1000));
      MMT::MARC::Regex->subfield($r,  '777', 'b', rand(1000));
    }
    $time = (Time::HiRes::gettimeofday - $time) * 1000;
    my $sizeEnd = Devel::Size::total_size($r);
    ok(1, "'".($iterations*8)."' mutations in '$time' microseconds");
    ok(1, "Memory footprint grew from '$sizeStart' to '$sizeEnd' bytes");


    $r = \$records[1];
    $time = Time::HiRes::gettimeofday();
    for (1..$iterations) {
      $r = $r; #No need to serialize, since this is already in the original text transfer form
    }
    $time = (Time::HiRes::gettimeofday - $time) * 1000;
    ok(1, "'$iterations' Records serialized in '$time' microseconds");


    $totalTime = Time::HiRes::gettimeofday() - $totalTime;
    ok(1, "Tests done in '$totalTime' seconds");
  };

};