use MMT::Pragmas;

use FindBin;
use lib "$FindBin::Bin/../lib";
$ENV{MMT_HOME} = "$FindBin::Bin/../";
print "\nMMT_HOME => $FindBin::Bin/../\n";

use Test::Most tests => 3;

use MMT::MARC::Record;
use MMT::Koha::Holding;

my @records = (
  <<RECORD,
<record format="MARC21" type="Bibliographic" xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00181cx  a22000853  4500</leader>
  <controlfield tag="001">3</controlfield>
  <controlfield tag="004">14</controlfield>
  <controlfield tag="005">20150520100954.0</controlfield>
  <controlfield tag="008">0206282p    8   4001aufin0000000</controlfield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="a">Hamkl</subfield>
    <subfield code="b">Hamklmhl</subfield>
    <subfield code="h">371.3</subfield>
    <subfield code="i">TOISKALLIO</subfield>
  </datafield>
</record>
RECORD
  <<RECORD,
<record format="MARC21" type="Bibliographic" xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00348cx  a22001094  4500</leader>
  <controlfield tag="001">150628</controlfield>
  <controlfield tag="004">132979</controlfield>
  <controlfield tag="005">20180913153618.0</controlfield>
  <controlfield tag="008">1809132f    8   1001a fin0901128</controlfield>
  <datafield tag="852" ind1="8" ind2=" ">
    <subfield code="a">Hamk</subfield>
    <subfield code="b">Hamksark</subfield>
    <subfield code="h">Mechanical engineering and production technology</subfield>
    <subfield code="i">MELNIKOV</subfield>
  </datafield>
  <datafield tag="506" ind1=" " ind2=" ">
    <subfield code="a">K<C3><A4>ytett<C3><A4>viss<C3><A4> vain HAMKin VDI-palvelun kautta.</subfield>
  </datafield>
  <datafield tag="506" ind1=" " ind2=" ">
    <subfield code="a">Available only via HAMK VDI service.</subfield>
  </datafield>
</record>
RECORD
);

subtest "isControlField", sub {
  plan tests => 2;
  my $f = MMT::MARC::Field->new('001');
  ok($f->isControlfield, 'Field 001 is a control field');

  $f = MMT::MARC::Field->new('010');
  ok(! $f->isControlfield, 'Field 010 is not a control field');
};

subtest "Parse MARC records", sub {

  my $r = MMT::MARC::Record->newFromXml(\$records[0]);
  my $fs = $r->fields;

  is($r->leader, '00181cx  a22000853  4500', 'r0 - leader');
  testFields($r->fields, [
    ['001', undef, undef, '0', '3'],
    ['004', undef, undef, '0', '14'],
    ['005', undef, undef, '0', '20150520100954.0'],
    ['008', undef, undef, '0', '0206282p    8   4001aufin0000000'],
    ['852', '8', ' '],
  ]);
  testSubfields($fs->[0]->getAllSubfields, [
    ['0', '3']
  ]);
  testSubfields($fs->[4]->getAllSubfields, [
    ['a', 'Hamka'],
    ['b', 'Hamkavana'],
    ['h', '371.3'],
    ['i', 'TOISKALLIO'],
  ]);
  is($r->docId, '3', 'r0 - docId');

  is(MMT::Koha::Holding::serialize({r => $r}), $records[0], 'r0 - serialized');



  $r = MMT::MARC::Record->newFromXml(\$records[1]);
  my $fs = $r->fields;

  is($r->leader, '00348cx  a22001094  4500', 'r1 - leader');
  testFields($r->fields, [
    ['001', undef, undef, '0', '150628'],
    ['004', undef, undef, '0', '132979'],
    ['005', undef, undef, '0', '20180913153618.0'],
    ['008', undef, undef, '0', '1809132f    8   1001a fin0901128'],
    ['852', '8', ' '],
    ['506', ' ', ' ', 'a', 'K<C3><A4>ytett<C3><A4>viss<C3><A4> vain HAMKin VDI-palvelun kautta.'],
    ['506', ' ', ' ', 'a', 'Available only via HAMK VDI service.'],
  ]);
  testSubfields($fs->[4]->getAllSubfields, [
    ['a', 'Hamk'],
    ['b', 'Hamksark'],
    ['h', 'Mechanical engineering and production technology'],
    ['i', 'MELNIKOV'],
  ]);
  is($r->docId, '150628', 'r0 - docId');

  is(MMT::Koha::Holding::serialize({r => $r}), $records[1], 'r1 - serialized');
};

subtest "Field 852 - Voyager location to Koha", sub {
  require MMT::TranslationTable::LocationId;
  require MMT::Koha::Holding::HAMK;
  my $TTLocationId = MMT::TranslationTable::LocationId->new();
  my $builder = {LocationId => $TTLocationId};
  my $kohaObject = MMT::Koha::Holding->new();
  $kohaObject->{id} = 1001;
  my $record = MMT::MARC::Record->newFromXml(\$records[0]);

  MMT::Koha::Holding::HAMK::transform($kohaObject, $record, $builder);
  my $f = $record->fields('852');

  testSubfields($f->[0]->getAllSubfields, [
    ['a', 'FI-Hamk'],
    ['b', 'HAMKL'],
    ['b', 'LIN'],
    ['c', 'MUS'],
    ['h', '371.3'],
    ['i', 'TOISKALLIO'],
    ['n', 'fi'],
  ]);

  MMT::Koha::Holding::HAMK::transform($kohaObject, $record, $builder);

  $f->[0]->deleteSubfield( $_ ) for @{$f->[0]->subfields('b')};
  $f->[0]->deleteSubfield( $_ ) for @{$f->[0]->subfields('b')};
  MMT::Koha::Holding::HAMK::transform($kohaObject, $record, $builder);
};

sub testFields($fs, $tests) {
  is(@$fs, @$tests, "Given as many fields '".scalar(@$fs)."' as tests '".scalar(@$tests)."'");

  for (my $i=0 ; $i<@$tests ; $i++) {
    testField($fs->[$i], $tests->[$i], $i);
  }
}

sub testField($f, $test, $i) {
  unless ($f) {
    ok($f, 'f $i: field at index $i is missing');
    return;
  }
  my $descr = "f $i: ".$f->code;
  is($f->code, $test->[0],       $descr." - code='".($f->code//'undef')."'");
  is($f->indicator(1), $test->[1], $descr." - indicator1='".($f->indicator(1)//'undef')."'");
  is($f->indicator(2), $test->[2], $descr." - indicator2='".($f->indicator(2)//'undef')."'");

  if (defined $test->[3]) { #Start testing subfields
    my $sfs = $f->getAllSubfields;

    my $j = 0;
    for (my $i=3 ; $i<@$test ; $i+=2) {
      testSubfield($sfs->[$j], [$test->[$i], $test->[$i+1]], $j);
      $j++;
    }
  }
}

sub testSubfields($sfs, $tests) {
  is(@$sfs, @$tests, "Given as many subfields '".scalar(@$sfs)."' as tests '".scalar(@$tests)."'");

  for (my $i=0 ; $i<@$tests ; $i++) {
    testSubfield($sfs->[$i], $tests->[$i], $i);
  }
}

sub testSubfield($sf, $test, $i) {
  unless ($sf) {
    ok($sf, 'sf $i: subfield at index $i is missing');
    return;
  }
  my $descr = "sf $i: ";
  is($sf->code,    $test->[0], $descr." - code '".($sf->code//'undef')."'");
  is($sf->content, $test->[1], $descr." - content '".($sf->content//'undef')."'");
}

done_testing;
