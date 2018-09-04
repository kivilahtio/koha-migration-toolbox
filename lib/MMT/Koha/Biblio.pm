package MMT::Koha::Biblio;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::Shell;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::Koha::Biblio - Transform biblios

=cut

=head2 transform

=cut

sub transform() {
  my $cmd = "usemarcon/usemarcon usemarcon/rules-hamk/rules.ini ".MMT::Config::voyagerExportDir()."/biblios.xml ".MMT::Config::kohaImportDir()."/biblios.marcxml";
  my ($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = MMT::Shell::run($cmd);

  return undef; #Getopt::OO callback errors if we return something.
}

return 1;
