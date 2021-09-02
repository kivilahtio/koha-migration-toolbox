package MMT::Config;

#Pragmas
#use MMT::Pragmas; #Do not load this here, because it triggers race condition issues when loading Log4Perl from other dependant modules prior to having it initialized
use Carp::Always::Color;

#External modules
use YAML::XS;
use Log::Log4perl; #First the config must be loaded so the logger subsystem can be initialized (below)

=head1 NAME

MMT::Config - Manage app-wide config

=head2 DESCRIPTION

=cut

our $config;

#
# Introduce configuration options as subroutines, to exchange one-time typing effort for compile-time error checking.
#

sub anonymize() {
  return $config->{anonymize} // 1;
}
sub csvInputEncoding() {
  return $config->{csvInputParams}->{encoding};
}
sub csvInputNew() {
  return $config->{csvInputParams}->{new};
}
sub csvInputHeader() {
  return $config->{csvInputParams}->{header};
}
sub defaultReplacementPrice() {
  return $config->{defaultReplacementPrice};
}
sub emptyBarcodePattern() {
  return $config->{emptyBarcodePattern};
}
sub emptyBarcodePolicy() {
  return $config->{emptyBarcodePolicy};
}
sub exportsDir() {
  return $ENV{MMT_HOME}.'/'.$config->{sourceSystemType}.'Exports';
}
sub exportPipelineScript() {
  return $ENV{MMT_HOME}.'/secret/'.$config->{exportPipelineScript};
}
sub getEffectiveUser() {
  return $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
}
sub holdingsTransformationModule() {
  return $config->{holdingsTransformationModule};
}
sub importPipelineScript() {
  return $ENV{MMT_HOME}.'/secret/'.$config->{importPipelineScript};
}
sub kohaImportDir() {
  mkdir $ENV{MMT_HOME}.'/KohaImports' unless (-e $ENV{MMT_HOME}.'/KohaImports');
  return $ENV{MMT_HOME}.'/KohaImports';
}
sub log4perlConfig() {
  return $ENV{MMT_HOME}.'/config/log4perl.conf';
}
sub logDir() {
  return $ENV{MMT_HOME}.'/logs';
}
sub mainConfigFile() {
  return $ENV{MMT_HOME}.'/config/main.yaml';
}
sub marcInputEncoding() {
  return $config->{marcInputEncoding} || 'utf-8';
}
sub organizationISILCode() {
  return $config->{organizationISILCode};
}
sub patronAddExpiryYears() {
  return $config->{patronAddExpiryYears};
}
sub patronHomeLibrary() {
  return $config->{patronHomeLibrary};
}
sub patronInitials() {
  return $config->{patronInitials};
}
sub phoneNumberValidationStrategy() {
  return $config->{phoneNumberValidationStrategy};
}
sub sourceSystemType() {
  return $config->{sourceSystemType};
}
sub testDir() {
  return $ENV{MMT_HOME}.'/tests';
}
sub translationTablesDir() {
  return $ENV{MMT_HOME}.'/config/translationTables/'.$config->{sourceSystemType};
}
sub useHetula() {
  return $config->{useHetula};
}
sub workers() {
  return $config->{workers};
}
sub barcodeMinLength() {
  return $config->{barcodeMinLength} // 5;
}


sub pl_barcodeFromAcqNumber() {
  return $config->{pl_barcodeFromAcqNumber};
}
sub pl_class_classifiers() {
  return $config->{pl_class_classifiers};
}
sub pl_shelf_filter() {
  return $config->{pl_shelf_filter};
}


#Check that the environment is properly configured
my $errorDescr = "This must point to the home directory created during MMT-Voyager installation, where all the configurations reside.";
die "\$ENV{MMT_HOME} '$ENV{MMT_HOME}' is undefined! $errorDescr"
  unless $ENV{MMT_HOME};
die "\$ENV{MMT_HOME} '$ENV{MMT_HOME}' is unreadable by user '".getEffectiveUser()."'! $errorDescr"
  unless -r $ENV{MMT_HOME};

$config = YAML::XS::LoadFile(mainConfigFile());

#Initialize the logging subsystem
eval {
  Log::Log4perl::init_once(log4perlConfig());
};
if ($@) {
  die "Initializing the Log::Log4perl-subsystem failed, reading config from '".log4perlConfig()."'. Error message='$@'";
}


unless (emptyBarcodePolicy() eq 'ERROR' || emptyBarcodePolicy() eq 'IGNORE' || emptyBarcodePolicy() eq 'CREATE') {
  die "Config emptyBarcodePolicy '".emptyBarcodePolicy()."' is unvalid, must be one of [ERROR, IGNORE, CREATE]";
}
unless (sourceSystemType() =~ /^(?:Voyager|PrettyLib|PrettyCirc)$/) {
  die "Config sourceSystemType '".sourceSystemType()."' is invalid";
}
unless ($config->{csvInputParams} && $config->{csvInputParams}->{new}) {
  die "Config 'csvInputParams->new' is not a proper Text::CSV options HASH";
}
unless ($config->{csvInputParams} && $config->{csvInputParams}->{header}) {
  die "Config 'csvInputParams->header' is not a proper Text::CSV options HASH";
}

unless (defined $config->{pl_shelf_filter}) {
  die "Config 'pl_shelf_filter' is not defined";
}

if (sourceSystemType() =~ /^(?:PrettyLib|PrettyCirc)$/) {
  unless ($config->{pl_class_classifiers} && ref($config->{pl_class_classifiers}) eq 'ARRAY') {
    die "config 'pl_class_classifiers' is not set or is not an ARRAY|List! See the source code template config/main.yaml for usage example."
  }
}

return 1;
