use 5.22.1;

package MMT::Table::PatronCategorycode;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';

#External modules
#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::ATranslator;
use base qw(MMT::ATranslator);

#Exceptions

=head1 NAME

MMT::Table::PatronCategorycode - borrowers.categorycode mapping table

=head2 DESCRIPTION

Special functions to handle translation of Voyager data points to Koha borrower categorycode.

=cut

sub example($s, $originalValue, $param1) {
  return $param1;
}

sub warning($s, $originalValue) {
  $log->warn("No mapping for value '$originalValue'");
}

return 1;