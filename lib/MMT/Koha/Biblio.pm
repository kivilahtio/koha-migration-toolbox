use 5.22.1;

package MMT::Koha::Biblio;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';
use English;

#External modules

#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);
use MMT::Date;
use MMT::Validator;
use MMT::Shell;

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
