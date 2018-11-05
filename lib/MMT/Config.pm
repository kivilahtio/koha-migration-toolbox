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

sub defaultReplacementPrice() {
  return $config->{defaultReplacementPrice};
}
sub getEffectiveUser() {
  return $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
}
sub mainConfigFile() {
  return $ENV{MMT_HOME}.'/config/main.yaml';
}
sub voyagerExportDir() {
  return $config->{voyagerExportDir};
}
sub holdingsTransformationModule() {
  return $config->{holdingsTransformationModule};
}
sub kohaImportDir() {
  return $config->{kohaImportDir};
}
sub log4perlConfig() {
  return $ENV{MMT_HOME}.'/config/log4perl.conf';
}
sub translationTablesDir() {
  return $ENV{MMT_HOME}.'/config/translationTables';
}
sub logDir() {
  return $ENV{MMT_HOME}.'/logs';
}
sub testDir() {
  return $ENV{MMT_HOME}.'/tests';
}
sub exportPipelineScript() {
  return $config->{exportPipelineScript};
}
sub importPipelineScript() {
  return $config->{importPipelineScript};
}
sub patronHomeLibrary() {
  return $config->{patronHomeLibrary};
}
sub workers() {
  return $config->{workers};
}
sub organizationISILCode() {
  return $config->{organizationISILCode};
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

return 1;