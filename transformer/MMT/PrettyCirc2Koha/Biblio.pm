package MMT::PrettyCirc2Koha::Biblio;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::Shell;
use MMT::MARC::Record;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::PrettyLib2Koha::Biblio;
use base qw(MMT::PrettyLib2Koha::Biblio);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::PrettyLib2Koha::Biblio - Transform biblios

=cut

#sub mergeLinks($s, $o, $b) {
#  $s->linkDocuments($o, $b);
#  $s->linkPublishers($o, $b);
#  $s->linkSubjects($o, $b);
  #TODO: Actually the PrettyCirc database has all the linked bibilio tables as the PrettyLib -database.
#}

return 1;
