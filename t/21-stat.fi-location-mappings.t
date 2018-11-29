BEGIN {
  use FindBin;
  use lib "$FindBin::Bin/../lib";
  $ENV{MMT_HOME} = "$FindBin::Bin/../";
  print "# MMT_HOME => $FindBin::Bin/../\n";
}

use MMT::Pragmas;

use Test::Most tests => 5;
use Test::Differences;
use Test::MockModule;

use File::Slurp;

use MMT::TBuilder;
use MMT::TranslationTable::LocationId;

subtest "Translation bugs squashing", sub {
  plan tests => 1;

  cmp_deeply(
    ['2.K', undef],
    [MMT::TranslationTable::LocationId::_statisticsLibrary(
      '',
      '',
      '',
      '08 Nord',
    )],
    "08 Nord should map properly"
  );
};

#Example data set
my $dataFile = "$FindBin::Bin/../t/resource/21-stat.fi-location_mappings.csv";
#Data set after translation
my $resultsFile = "$FindBin::Bin/../t/resource/21-stat.fi-location_mappings.results";

my $csv = Text::CSV->new({ binary => 1, sep_char => ',', auto_diag => 9 });
open(my $inFH, '<:encoding(UTF-8)', $dataFile) or die("Loading file failed: $!");
$csv->column_names(  $csv->getline( $inFH )  );
ok(1, "Given the source test data has been opened for reading");



my @results;

while (my $data = $csv->getline_hr( $inFH )) {
  push(@results, [
      MMT::TranslationTable::LocationId::_statisticsLibrary(
        $data->{begin_pub_date},
        $data->{freq_increment},
        $data->{freq_calc_type},
        $data->{display_call_no},
      )
    ]
  );
}

ok(@results,
  "When source data has been translated using the custom translator");

subtest "Then the locations and itemtypes are translated as expected", sub {
  my @tests = (
    [1,  ['2.K',  undef]], #This is actually row 1  in $dataFile
    [38, ['VARA', undef]], #This is actually row 40 in $dataFile
  );
  plan tests => scalar(@tests);

  for my $t (@tests) {
    cmp_deeply(
      $results[ $t->[0] ],
      $t->[1],
      "Result $t->[0] ok"
    );
  }
};

open(my $outFH, '>:encoding(UTF-8)', $resultsFile) or die("Couldn't open '$resultsFile' for writing: $!");
my @data = File::Slurp::read_file($dataFile, {chomp => 1});
for (my $i=0 ; $i<@data ; $i++) {
  if ($i == 0) { #First row is the header row
    print $outFH "$data[$i]\n";
  }
  else {
    printf $outFH "%-120s => %s\n", $data[$i], join(',', map {$_ || ''} @{$results[$i-1]});
  }
}
ok(close($outFH),
  "Finally the translated results are written back to file '$resultsFile' for manual inspection");
