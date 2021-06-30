package MMT::PrettyLib2Koha::Loan;

use MMT::Pragmas;

#External modules

#Local modules
use MMT::Validator;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::PrettyLib2Koha::Issue - Transforms PrettyLib Loans to Koha Issues

=cut

=head2 build

Flesh out the Koha-borrower -object out of the given
 @param1 Voyager data object
 @param2 Builder

=cut

sub build($self, $o, $b) {
  #$self->setIssue_id    ($o, $b); #AUTO_INCREMENT
  $self->setKeys($o, $b, [['Id_Customer' => 'borrowernumber'],['Id_Item' => 'itemnumber']]);
  $self->set(Id_Title => 'biblionumber',      $o, $b);
  $self->setDateDue                          ($o, $b);
  $self->setBranchcode                       ($o, $b);
  $self->setRenewals                         ($o, $b);
  $self->setIssuedate                        ($o, $b);
  $self->setLastrenewdate                    ($o, $b);
  $self->setNote                             ($o, $b);
}

sub id {
  return 'p:'.($_[0]->{borrowernumber} // 'NULL').'-i:'.($_[0]->{itemnumber} // 'NULL');
}

sub logId($s) {
  return 'Issue: '.$s->id();
}

sub getDeleteListId($s) {
  return 'LOAN'.($s->id() || 'UNDEF');
}

sub setBiblionumber($s, $o, $b) {
  $s->{biblionumber} = $o->{Id_Title} if $o->{Id_Title}; #Biblionumber is not needed in Koha.issues. Just a handy reference to easily spot issues.
}
sub setDateDue($s, $o, $b) {
  $s->{date_due} = $o->{DueDate};

  unless ($s->{date_due}) {
    MMT::Exception::Delete->throw($s->logId()."' has no DueDate/date_due.");
  }

  $s->{date_due} = MMT::Validator::parseDate($s->{date_due});
}
sub setBranchcode($s, $o, $b) {
  $s->{branchcode} = $b->{Branchcodes}->translate(@_, $o->{Id_Library});

  unless ($s->{branchcode}) {
    MMT::Exception::Delete->throw($s->logId()."' has no place of issuance (Id_Library/branchcode). Set a default in the TranslationTable rules!");
  }
}
sub setRenewals($s, $o, $b) {
  $s->{renewals} = ($o->{LoanCount}) ? $o->{LoanCount}-1 : 0;
}
sub setIssuedate($s, $o, $b) {
  $s->{issuedate} = $o->{LoanDate};

  unless ($s->{issuedate}) {
    MMT::Exception::Delete->throw($s->logId()." has no issuedate.");
  }

  $s->{issuedate} = MMT::Validator::parseDate($s->{issuedate});
}
sub setLastrenewdate($s, $o, $b) {
  #$s->{lastrenewdate} = PrettyLib has no such concept.
}
sub setNote($s, $o, $b) {
  $s->{note} = $o->{Material} if $o->{Material};
}

return 1;
