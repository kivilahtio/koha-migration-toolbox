use 5.22.1;
use experimental 'smartmatch', 'signatures';
$|=1;
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDIN, ":encoding(UTF-8)");

package Bulk::Util;

use English;

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

#
# Koha doesn't work nicely with the thread-model, but it is not too dastardly.
#
sub invokeThreadCompatibilityMagic() {
    #Koha::Cache cannot be shared across threads due to Sereal. Hack around it.
    Koha::Caches::flush_L1_caches();
    $ENV{CACHING_SYSTEM} = 'disable';
    $Koha::Cache::L1_encoder = Sereal::Encoder->new;
    $Koha::Cache::L1_decoder = Sereal::Decoder->new;
    C4::Context->dbh({new => 1}); #Force a new database connection for new threads, so each thread gets it's own DB handle to avoid race conditions with mysql last_insert_id
}

=head2 getMarcFileIterator

  my $i = $s->getMarcFileIterator();
  my ($marcRecord, $marcXmlPointer) = $i->();

Pick an marcxml collection iteration strategy.
The built-in way Koha uses is way too slow.
Trying different strategies to speed it up while maintaining optimal memory footprint.

 @returns Subroutine, call this to get XML as a reference to String

=cut

sub getMarcFileIterator($s) {
  local $INPUT_RECORD_SEPARATOR = '</record>'; #Let perl split MARCXML for us
  open(my $FH, '<:encoding(UTF-8)', $s->p('inputMarcFile')) or die("Opening the MARC file '".$s->p('inputMarcFile')."' for slurping failed: $!"); # Make sure we have the proper encoding set before handing these to the MARC-modules

  sub _i {
    my ($recursionDepth) = @_;
    local $INPUT_RECORD_SEPARATOR = '</record>'; #Let perl split MARCXML for us
    my $xml = <$FH>;

    $xml =~ s/(?:^\s+)|(?:\s+$)//gsm if $xml; #Trim leading and trailing whitespace
    #Trim colection information or other whitespace fluff
    $xml =~ s!^.+?<record!<record!sm if $xml;
    $xml =~ s!</record>.+$!</record>!sm if $xml;

    unless ($xml) {
      DEBUG "No more MARC XMLs";
      return undef;
    }
    unless ($xml =~ /<record.+?<\/record>/sm) {
      FATAL "Broken MARCXML:\n$xml";
      return _i(($recursionDepth ? $recursionDepth+1 : 1)) if (not($recursionDepth) || $recursionDepth < 5);
      die "Broken MARCXML. Too deep recursion '$recursionDepth' to recover.:\n$xml";
    }
    return \$xml;
  };
  return \&_i;
}

## Get the id from where we start adding old issues. It is the biggest issue_id in use. It is important the issue_ids don't overlap.
sub getMaxIssueId {
  my ($dbh) = @_;
  my $old_issue_id = $dbh->selectrow_array("SELECT MAX(issue_id) FROM old_issues");
  $old_issue_id = 1 unless $old_issue_id;
  my $issue_id     = $dbh->selectrow_array("SELECT MAX(issue_id) FROM issues");
  $issue_id = 1 unless $issue_id;
  $old_issue_id = ($old_issue_id > $issue_id) ? $old_issue_id : $issue_id;
  $old_issue_id++;
  return $old_issue_id;
}

sub logArgs {
  my ($args) = @_;
  $Data::Dumper::Indent=1;
  print("***ARGS:***\n".Data::Dumper::Dumper($args)."\n");
}

return 1;
