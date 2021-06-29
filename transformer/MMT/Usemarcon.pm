package MMT::Usemarcon;

use MMT::Pragmas;

=head2 usemarcon

Use usemarcon to do the transformation.

=cut

sub usemarcon() {
  my $inputMARCFile = MMT::Config::kohaImportDir()."/biblios.marcxml.finmarc";
  my $outputMARCFile = MMT::Config::kohaImportDir()."/biblios.marcxml";
  my $cmd = "usemarcon/usemarcon usemarcon/USEMARCON-fi2ma/fi2ma.ini $inputMARCFile $outputMARCFile";
  my ($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = MMT::Shell::run($cmd);
  return !$success; # Getopt::OO callback errors if we return something.
}

return 1;

