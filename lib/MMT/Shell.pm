use 5.22.1;

package MMT::Shell;
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

MMT::Shell - Wrapper to run shell scripts

=cut

sub run($cmd) {
  my($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = IPC::Cmd::run(command => $cmd, verbose => 1);

  if ($error_code) {
    $log->logdie(
      "Executing '$cmd' failed:\n".
      "\$error_code='$error_code'\n".
      "OUT:\n".
      join("\n", @$full_buf)
    );
  }

  return ($success, $error_code, $full_buf, $stdout_buf, $stderr_buf);
}

return 1;
