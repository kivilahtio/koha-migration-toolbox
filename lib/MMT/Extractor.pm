use 5.22.1;

package MMT::Extractor;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';

#External modules
use IPC::Cmd;

#Local modules
use MMT::Config;
use Log::Log4perl;
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

  my($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = IPC::Cmd::run(command => $script, verbose => 1);

  if ($error_code) {
    $log->logdie(
      "$errCtxt execution failed:\n".
      "\$error_code='$error_code'\n".
      "OUT:\n".
      join("\n", @$full_buf)
    );
  }
}

return 1;
