use 5.22.1;
use experimental 'smartmatch', 'signatures';
$|=1;
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDIN, ":encoding(UTF-8)");

package Bulk::Util;

use Log::Log4perl qw(:easy);

print 'Verbosity='.$main::verbosity."\n";
my $verbosity = $main::verbosity;
my $level;
if    ($verbosity == 0) {  $level = Log::Log4perl::Level::FATAL_INT;  }
elsif ($verbosity == 1) {  $level = Log::Log4perl::Level::ERROR_INT;  }
elsif ($verbosity == 2) {  $level = Log::Log4perl::Level::WARN_INT;   }
elsif ($verbosity == 3) {  $level = Log::Log4perl::Level::INFO_INT;   }
elsif ($verbosity == 4) {  $level = Log::Log4perl::Level::DEBUG_INT;  }
elsif ($verbosity == 5) {  $level = Log::Log4perl::Level::TRACE_INT;  }
elsif ($verbosity == 6) {  $level = Log::Log4perl::Level::ALL_INT;    }
else  { die("--verbosity must be between 0 to 6"); }
Log::Log4perl->easy_init($level);

use Data::Dumper;
$Data::Dumper::Indent = 0;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Useqq = 1;
$Data::Dumper::Purity = 1;

sub openFile($itemsFile, $skipRows=0) {
    INFO "Opening file '$itemsFile'".($skipRows ? " Skipping '$skipRows' rows" : "");
    $skipRows = 0 unless $skipRows;

    open(my $fh, "<:encoding(utf-8)", $itemsFile ) or die("Couldn't open file '$itemsFile': $!");
    my $i=0;
    while($i++ < $skipRows) {
        my $waste = <$fh>;
        #Skip rows.
    }
    return $fh;
}

sub newFromBlessedMigratemeRow($row) {
    my $o = eval $row;
    die $@ if $@;
    return $o;
}

sub newFromUnblessedMigratemeRow($row) {
    no strict 'vars';
    eval $row;
    my $o = $VAR1;
    use strict 'vars';
    warn $@ if $@;
    return $o;
}

return 1;