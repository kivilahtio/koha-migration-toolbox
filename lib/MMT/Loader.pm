use 5.22.1;

package MMT::Loader;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';

#External modules

#Local modules
use MMT::Config;
use MMT::Shell;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::ExtractorLoader - Loads the transformed data into Koha using the 'importPipelineScript'

=cut

sub load() {
  my $script = MMT::Config::importPipelineScript();
  my $errCtxt = "Trying to trigger Koha load-phase as effective user='".MMT::Config::getEffectiveUser()."', but the configured importPipelineScript='$script'";
  my $cfgMsg = "It is configured in '".MMT::Config::mainConfigFile()."'.";
  $log->logdie("$errCtxt is undefined? $cfgMsg")
    unless $script;
  $log->logdie("$errCtxt is unreadable? $cfgMsg")
    unless -r $script;
  $log->logdie("$errCtxt is not executable? $cfgMsg")
    unless -x $script;

  my ($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = MMT::Shell::run($script);

  return $success;
}

return 1;
