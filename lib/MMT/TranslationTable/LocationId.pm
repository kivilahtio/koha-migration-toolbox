use 5.22.1;

package MMT::TranslationTable::LocationId;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';

#External modules
#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::ATranslationTable;
use base qw(MMT::ATranslationTable);

#Exceptions

=head1 NAME

MMT::TranslationTable::LocationId - map voyager.location_id to Koha

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/location_id.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub branchLoc($s, $kohaObject, $voyagerObject, $builder, $originalValue, $branch, $loc, $collectionCode=undef, $error=undef) {
  return {
    branch => uc($branch),
    location => uc($loc),
    collectionCode => $collectionCode,
  };
}

return 1;