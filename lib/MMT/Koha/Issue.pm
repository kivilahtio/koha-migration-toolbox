use 5.22.1;

package MMT::Koha::Issue;
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

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::Koha::Issue - Transforms a bunch of Voyager data into a Koha issue-transaction

=cut

=head2 build

Flesh out the Koha-borrower -object out of the given
 @param1 Voyager data object
 @param2 Builder

=cut

sub build($self, $o, $b) {
  $self->setBorrowernumber                   ($o, $b);
  $self->setItemnumber                       ($o, $b);
  $self->setCardnumber                       ($o, $b);
  $self->setBarcode                          ($o, $b);
  $self->setDateDue                          ($o, $b);
  $self->setBranchcode                       ($o, $b);
  $self->setRenewals                         ($o, $b);
  $self->setIssuedate                        ($o, $b);
  $self->setLastrenewdate                    ($o, $b);
  #$self->setNote                             ($o, $b); #Voyager doesn't have issue-level notes
}

sub id {
  return 'p:'.($_[0]->{cardnumber} || $_[0]->{borrowernumber}).'-i:'.($_[0]->{barcode} || $_[0]->{itemnumber});
}

sub logId($s) {
  return 'Issue: '.$s->id();
}

#Do not set issue_id here, just move some primary key for deubgging purposes
sub setBorrowernumber($s, $o, $b) {
  unless ($o->{patron_id}) {
    MMT::Exception::Delete->throw("Issue is missing patron_id ".MMT::Validator::dumpObject($o));
  }
  $s->{borrowernumber} = $o->{patron_id};
}
sub setItemnumber($s, $o, $b) {
  unless ($o->{item_id}) {
    MMT::Exception::Delete->throw("Issue is missing item_id ".MMT::Validator::dumpObject($o));
  }
  $s->{itemnumber} = $o->{item_id};
}
sub setCardnumber($s, $o, $b) {
  $s->{cardnumber} = $o->{patron_barcode};

  unless ($o->{patron_barcode}) {
    $log->warn($s->logId()."' has no patron_barcode.");
    #patron_barcode is not needed, only the borrowernumber|patron_id, but having no cardnumber|patron_barcode| is a dangerous anomaly
  }
}
sub setBarcode($s, $o, $b) {
  $s->{barcode} = $o->{item_barcode};

  unless ($o->{item_barcode}) {
    $log->warn($s->logId()."' has no item_barcode.");
    #item_barcode is not needed, only the itemnumber|item_id, but having no barcode|item_barcode| is a dangerous anomaly
  }
}
sub setDateDue($s, $o, $b) {
  $s->{date_due} = $o->{current_due_date}; #duedate can possibly be one year in the future

  unless ($s->{date_due}) {
    MMT::Exception::Delete->throw($s->logId()."' has no date_due/current_due_date.");
  }
}
sub setBranchcode($s, $o, $b) {
  my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{charge_location});
  $s->{branchcode} = $branchcodeLocation->{branch};

  unless ($s->{branchcode}) {
    MMT::Exception::Delete->throw($s->logId()."' has no place of issuance (charge_location/branchcode). Set a default in the TranslationTable rules!");
  }
}
sub setRenewals($s, $o, $b) {
  $s->{renewals} = $o->{renewal_count} || 0;
}
sub setIssuedate($s, $o, $b) {
  $s->{issuedate} = $o->{charge_date};

  unless ($s->{issuedate}) {
    MMT::Exception::Delete->throw($s->logId()." has no issuedate.");
  }
}
sub setLastrenewdate($s, $o, $b) {
  my $lastRenewDates = $b->{LastRenewDate}->get($o);
  if ($lastRenewDates) {
    unless ($lastRenewDates->[0]->{last_renew_date}) {
      $log->error($s->logId()." has a last_renew_date-row, but the key 'last_renew_date' us undefined?");
      next;
    }
    $s->{lastrenewdate} = $lastRenewDates->[0]->{last_renew_date};

    if (not($s->{renewals})) { #Some defensive programming sanity checks
      $log->warn($s->logId()." has lastrenewdate='".$s->{lastrenewdate}."' but no renewal_count|renewals?");
    }
  }
  elsif ($s->{renewals}) { #Some defensive programming sanity checks
    $log->warn($s->logId()." has no last_renew_date but renewal_count|renewals='".$s->{renewals}."'?");
  }
}

return 1;