package MMT::Usemarcon;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::Shell;
my Log::Log4perl $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::Usemarcon - Runs the USEMARCON tool on your bibliographic records

=cut

=head2 execute

Use usemarcon to do the transformation. Outputs MARC21.

ARGS:

C<$sourceRecordsFile> Input

=cut

sub execute($sourceRecordsFile) {
  my $usemarconIniFile = MMT::Config::usemarconIniFile();
  unless ($usemarconIniFile) {
    return 1;
  }
  my $inputMARCFile = $sourceRecordsFile;
  my $outputMARCFile = $sourceRecordsFile.'.marc21';

  $log->info("Starting USEMARCON script with $usemarconIniFile configuration");
  my $cmd = $ENV{MMT_CODE} . "/usemarcon/usemarcon $usemarconIniFile $inputMARCFile $outputMARCFile";
  my ($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = MMT::Shell::run($cmd, 0);
  if ($success) {
    MMT::Shell::run("cp $outputMARCFile $inputMARCFile && rm $outputMARCFile", 0);
    $log->info("USEMARCON success");
  } else {
    $log->error("USEMARCON error (code $error_code): $stderr_buf");
  }
  return !$success; # Getopt::OO callback errors if we return something.
}

return 1;
