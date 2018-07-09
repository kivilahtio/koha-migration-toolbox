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
    MMT::Exception::Delete->throw("Issue is missing patron_id:\n".$s->toYaml());
  }
  $s->{borrowernumber} = $o->{patron_id};
}
sub setItemnumber($s, $o, $b) {
  unless ($o->{item_id}) {
    MMT::Exception::Delete->throw("Issue is missing item_id:\n".$s->toYaml());
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
  $s->{datedue} = MMT::Date::translateDateDDMMMYY($o->{current_due_date}, $s, 'current_due_date->datedue');

  unless ($s->{datedue}) {
    MMT::Exception::Delete->throw($s->logId()."' has no datedue/current_due_date.");
  }
}
sub setBranchcode($s, $o, $b) {
  my $branchcodeLocation = $b->{LocationId}->translate(@_, $o->{charge_location});
  $s->{branchcode} = $b->{Branchcodes}->translate(@_, $branchcodeLocation->[0]);

  unless ($s->{branchcode}) {
    MMT::Exception::Delete->throw($s->logId()."' has no place of issuance (charge_location/branchcode). Set a default in the TranslationTable rules!");
  }
}
sub setRenewals($s, $o, $b) {
  $s->{renewals} = $o->{renewal_count} || 0;
}
sub setIssuedate($s, $o, $b) {
  $s->{issuedate} = MMT::Date::translateDateDDMMMYY($o->{charge_date}, $s, 'charge_date->issuedate');

  unless ($s->{issuedate}) {
    MMT::Exception::Delete->throw($s->logId()."' has no issuedate.");
  }
}
sub setLastrenewdate($s, $o, $b) {
  my $dates = $b->{LastBorrowDates}->get($s->{barcode});
  if ($dates && $dates->[0]) {
    if (ref ($dates->[0]) eq 'HASH' && $dates->[0]->{'max(charge_date)'}) {
      $s->{lastrenewdate} = $dates->[0]->{'max(charge_date)'};
    }
    else {
      $log->error("lastBorrowDates row is malformed?: ".MMT::Validator::dumpObject($dates->[0]));
    }
  }

  unless ($s->{lastrenewdate}) {
    $log->warn($s->logId()."' has no lastrenewdate, using issuedate");
    $s->{lastrenewdate} = $s->{issuedate};
  }

  $s->{lastrenewdate} = MMT::Date::translateDateDDMMMYY($s->{lastrenewdate}, $s, 'max(charge_date)->lastrenewdate')
    unless MMT::Date::isIso8601($s->{lastrenewdate});
}


return 1;