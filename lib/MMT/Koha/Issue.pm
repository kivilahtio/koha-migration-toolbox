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

=head1 NAME

MMT::Koha::Issue - Transforms a bunch of Voyager data into a Koha issue-transaction

=cut

=head2 build
Flesh out the Koha-borrower -object out of the given
 @param1 Voyager data object
 @param2 Builder
=cut
sub build($self, $o, $b) {
  $self->setPatronId                         ($o, $b);
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
  return ($_[0]->{patron_barcode} || $_[0]->{patron_id}).'-'.($_[0]->{item_barcode} || 'NULL');
}

sub logId($s) {
  return 'Issue: '.$s->id();
}

#Do not set issue_id here, just move some primary key for deubgging purposes
sub setPatronId($s, $o, $b) {
  unless ($o->{patron_id}) {
    die "\$DELETE: Issue is missing patron_id, DELETEing:\n".$s->toYaml();
  }
  $s->{patron_id} =      $o->{patron_id};
}
sub setCardnumber($s, $o, $b) {
  $s->{cardnumber} = $o->{patron_barcode};

  unless ($s->{cardnumber}) {
    $log->warn($s->logId()."' has no cardnumber.");
    $s->{cardnumber} = $s->createTemporaryBarcode();
  }
}
sub setBarcode($s, $o, $b) {
  $s->{barcode} = $o->{item_barcode};

  unless ($s->{barcode}) {
    $log->warn($s->logId()."' has no barcode.");
    $s->{barcode} = $s->createTemporaryBarcode();
  }
}
sub setDateDue($s, $o, $b) {
  $s->{datedue} = MMT::Date::translateDateDDMMMYY($o->{current_due_date}, $s, 'current_due_date->datedue');

  unless ($s->{datedue}) {
    die "\$DELETE: '".$s->logId()."' has no datedue/current_due_date.";
  }
}
sub setBranchcode($s, $o, $b) {
  my $branchcodeLocation = $b->{locationIdTranslation}->translate($o->{charge_location});
  $s->{branchcode} = $b->{branchcodeTranslation}->translate($branchcodeLocation->[0]);

  unless ($s->{branchcode}) {
    $s->{branchcode} = 'HAMK';
    $log->warn($s->logId()."' has no place of issuance (charge_location/branchcode).");
  }
}
sub setRenewals($s, $o, $b) {
  $s->{renewals} = $o->{renewal_count} || 0;
}
sub setIssuedate($s, $o, $b) {
  $s->{issuedate} = MMT::Date::translateDateDDMMMYY($o->{charge_date}, $s, 'charge_date->issuedate');

  unless ($s->{issuedate}) {
    die "\$DELETE: '".$s->logId()."' has no issuedate.";
  }
}
sub setLastrenewdate($s, $o, $b) {
  my $dates = $b->{lastBorrowDates}->get($s->{barcode});
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
}


return 1;