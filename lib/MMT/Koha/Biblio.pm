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
  $s->linkBoundRecord($xmlPtr, $b);

  if ($$xmlPtr =~ s!<subfield code="9">([^0-9]+)</subfield>!!gsm) {
    $log->trace($s->logId().". Subfield \$9 = '$1' dropped. \$9 must be a number!") if $log->is_trace();
  }

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

=head2 linkBoundRecord

Link this Bib under the bound bib's parent record.
Executes only if this Bib is a bound record.

Bound parent record is transparently created if missing in the Loader, because due to the Perl's multi-threading nature of share-nothing, communicating the creation
of the bound parent bib is very difficult and communicating between processes is extra slow.
It is much easier to just spam the DB during loading to check if the bound parent record already exists or not.

=cut

sub linkBoundRecord($s, $xmlPtr, $b) {
  my $boundParent = $b->{BoundBibParent}->get($s->id());
  return unless $boundParent;

  $boundParent = $boundParent->[0]->{bound_parent_bib_id};
  die($s->logId()." - Bound parent biblionumber '$boundParent' is not a valid digit?") unless ($boundParent =~ /^\d+$/);

  $log->info($s->logId()." is a part of a bound record. Linking it under the reserved bound parent record biblionumber '$boundParent'");
  if (my $f773w = MMT::MARC::Regex->datafield($xmlPtr, '773', 'w')) {
    $log->warn($s->logId()." already has Field '773\$w'with value '$f773w'. This is overwritten with '$boundParent'. Sorry."); #TODO: Try to figure out a good solution if we encounter bound bibs which are also component parts.
  }
  MMT::MARC::Regex->datafield($xmlPtr, '773', 'w', $boundParent); #Overwrites any existing field 773
  MMT::MARC::Regex->subfield($xmlPtr, '773', 'i', 'Bound biblio');
  MMT::MARC::Regex->subfield($xmlPtr, '773', 't', 'Bound biblio parent record');
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
