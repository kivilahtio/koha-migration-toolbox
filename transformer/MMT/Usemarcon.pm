package MMT::Usemarcon;

use MMT::Pragmas;

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head2 usemarcon

Use usemarcon to do the transformation.

=cut

sub usemarcon() {
  my $inputMARCFile = MMT::Config::kohaImportDir()."/biblios.marcxml.finmarc";
  my $outputMARCFile = MMT::Config::kohaImportDir()."/biblios.marcxml";
  my $cmd = "usemarcon/usemarcon usemarcon/USEMARCON-fi2ma/fi2ma.ini $inputMARCFile $outputMARCFile";
  my ($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = MMT::Shell::run($cmd);

  return usemarcon() unless post_conversion_checks();
  return !$success; # Getopt::OO callback errors if we return something.
}

=head2 post_conversion_checks

On some platforms usemarcon can caused corrupt Records to be generated. Try to detect those in advance.

=cut

sub post_conversion_checks() {
  my $outputMARCFile = MMT::Config::kohaImportDir()."/biblios.marcxml";
  open(my $FH, '<:raw', $outputMARCFile);

  my $recordsBlob = join("",<$FH>);
  my @brokenLeaders = $recordsBlob =~ /<leader>(.{0,23}?)<\/leader>\s+<controlfield tag="001">(.+?)</gsm;
  for (my $i=0 ; $i<@brokenLeaders ; $i+=2) {
    my $brokenLeader = $brokenLeaders[$i];
    my $f001 = $brokenLeaders[$i+1];
    $log->error("USEMARCON broke the leader of Record F001='$f001'");
  }
  return 0 if @brokenLeaders;
  return 1;
}

return 1;

