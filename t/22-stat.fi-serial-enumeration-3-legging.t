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
use MMT::Koha::Serial;
use MMT::Koha::Serial::Enumerations;

#Example data set. This is just the extracted file 21-ser_issues.csv
my $dataFile = "$FindBin::Bin/../t/resource/22-stat.fi-serial-enumeration-3-legging.csv";
#Data set after translation
my $resultsFile = "$FindBin::Bin/../t/resource/22-stat.fi-serial-enumeration-3-legging.results";

my $csv = Text::CSV->new({ binary => 1, sep_char => ',', auto_diag => 9 });
open(my $inFH, '<:encoding(UTF-8)', $dataFile) or die("Loading file failed: $!");
$csv->column_names(  $csv->getline( $inFH )  );
ok(1, "Given the source test data has been opened for reading");



my @results;

while (my $data = $csv->getline_hr( $inFH )) {
  my $s = MMT::Koha::Serial->new();
  $s->{_id} = $data->{component_id}.','.$data->{issue_id};
  $s->{_enumchron} = $data->{enumchron};
  MMT::Koha::Serial::Enumerations::enumThenChron($s, $data, {});
  push(@results, $s);
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
for (my $i=0 ; $i<@results ; $i++) {
  my $s = $results[$i];
  if ($i == 0) { #First row is the header row
    print $outFH "$s\n";
  }
  else {
    printf $outFH "%-10s, [%-30s], '%s' '%s' '%s'\n", $s->{_id}, $s->{_enumchron}, ($s->{serialseq_x} || ''), ($s->{serialseq_y} || ''), ($s->{serialseq_z} || '');
  }
}
ok(close($outFH),
  "Finally the translated results are written back to file '$resultsFile' for manual inspection");
