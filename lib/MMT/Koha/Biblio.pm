package MMT::Koha::Biblio;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::Shell;
use MMT::MARC::Regex;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::Koha::Biblio - Transform biblios

=cut

=head2 build

 @param {String reference} Voyager xml record
 @param {TBuilder}

=cut

sub build($s, $xmlPtr, $b) {
  $s->{biblionumber} = MMT::MARC::Regex->controlfield($xmlPtr, '001');
  unless ($s->{biblionumber}) {
    MMT::Exception::Delete->throw(error => "Missing field 001 with record:\n$$xmlPtr\n!!");
  }

  MMT::MARC::Regex->controlfield($xmlPtr, '003', MMT::Config::organizationISILCode(), {after => '001'});

  $s->isSuppressInOPAC($xmlPtr, $b);

  $s->{xmlPtr} = $xmlPtr;
  return $s;
}

sub logId($s) {
  return "Biblio '".$s->id()."'";
}

sub id($s) {
  return $s->{biblionumber};
}

sub serialize($s) {
  return ${$s->{xmlPtr}}."\n";
}

=head2 isSuppressInOPAC

Sets the 942$n if the holding record is suppressed in OPAC

=cut

sub isSuppressInOPAC($s, $xmlPtr, $b) {
                                       #Key for the info is built with bib_id.mfhd_id.location_id
  my $suppressInOpac = $b->{SuppressInOpacMap}->get($s->id().'NULLNULL');
  if ($suppressInOpac) {
    $suppressInOpac = $suppressInOpac->[0]->{suppress_in_opac};
    $log->debug($s->logId()." - Suppress in opac '$suppressInOpac'") if $log->is_debug();

    MMT::MARC::Regex->datafield($xmlPtr, '942', 'n', $suppressInOpac);
  }
}

###########################################################################################
###########################################################################################

=head2 usemarcon

Use usemarcon to do the transformation.

=cut

sub usemarcon() {
  my $inputMARCFile = MMT::Config::voyagerExportDir()."/biblios.marcxml";
  my $outputMARCFile = MMT::Config::kohaImportDir()."/biblios.marcxml";
  my $cmd = "usemarcon/usemarcon usemarcon/rules-hamk/rules.ini $inputMARCFile $outputMARCFile";
  my ($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = MMT::Shell::run($cmd);
  return !$success; # Getopt::OO callback errors if we return something.
}

return 1;
