package MMT::Extractor;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::Shell;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::Extractor - Runs the extract script on the remote Voyager DB server

=cut

sub extract() {
  my $script = MMT::Config::exportPipelineScript();
  my $errCtxt = "Trying to trigger Voyager DB extraction-phase as effective user='".MMT::Config::getEffectiveUser()."', but the configured exportPipelineScript='$script'";
  my $cfgMsg = "It is configured at '".MMT::Config::mainConfigFile()."'.";
  $log->logdie("$errCtxt is undefined? $cfgMsg")
    unless $script;
  $log->logdie("$errCtxt is unreadable? $cfgMsg")
    unless -r $script;
  $log->logdie("$errCtxt is not executable? $cfgMsg")
    unless -x $script;

  my ($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = MMT::Shell::run($script);

  return undef if $success;
  return $error_code;
}

return 1;
