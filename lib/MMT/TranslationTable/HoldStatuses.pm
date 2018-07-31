use Modern::Perl '2016';

package MMT::TranslationTable::HoldStatuses;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';

#External modules
#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);
use MMT::Date;

#Inheritance
use MMT::ATranslationTable;
use base qw(MMT::ATranslationTable);

#Exceptions

=head1 NAME

MMT::TranslationTable::HoldStatuses - voyager.hold_recall.hold_recall_status to koha.reserves.found et. al. mapping table

=cut

my $translationTableFile = MMT::Config::translationTablesDir."/hold_recall_statuses.yaml";

sub new($class) {
  return $class->SUPER::new({file => $translationTableFile});
}

sub isWaitingForFulfilment($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $kohaObject->{found} = undef;
  return $kohaObject->{found}; #return value is arbitrary, but logged, so might as well return something useful to log
}
sub isWaitingForPickup($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $kohaObject->{found} = 'W';
  $kohaObject->{waitingdate} = $voyagerObject->{hold_recall_status_date};
  return $kohaObject->{found};
}
sub isInTransitForPickup($s, $kohaObject, $voyagerObject, $builder, $originalValue, $tableParams, $transParams) {
  $kohaObject->{found} = 'T';
  return $kohaObject->{found};
}

return 1;