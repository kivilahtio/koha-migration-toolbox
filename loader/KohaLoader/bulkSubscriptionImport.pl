#!/usr/bin/perl

use Modern::Perl '2015';
use experimental 'smartmatch', 'signatures';
$|=1;
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDIN, ":encoding(UTF-8)");

use Data::Printer;
use Getopt::Long;
use Log::Log4perl qw(:easy);

use C4::Context;

use Bulk::ConversionTable::SubscriptionidConversionTable;
use Bulk::ConversionTable::BiblionumberConversionTable;
use Bulk::ConversionTable::ItemnumberConversionTable;
use Bulk::ConversionTable::BorrowernumberConversionTable;

our $verbosity = 3;
my %args = (subscriptionfile =>                  ($ENV{MMT_DATA_SOURCE_DIR}//'.').'/Subscription.migrateme',
            serialFile       =>                  ($ENV{MMT_DATA_SOURCE_DIR}//'.').'/Serial.migrateme',
            routinglistFile  =>                  ($ENV{MMT_DATA_SOURCE_DIR}//'.').'/Subscriptionroutinglist.migrateme',
            preserveIds      =>                   $ENV{MMT_PRESERVE_IDS} // 0,
            subscriptionidConversionTableFile => ($ENV{MMT_WORKING_DIR}//'.').'/subscriptionidConversionTable',
            subscriptionidConversionTable     => undef,
            biblionumberConversionTable       => ($ENV{MMT_WORKING_DIR}//'.').'/biblionumberConversionTable',
            itemnumberConversionTable         => ($ENV{MMT_WORKING_DIR}//'.').'/itemnumberConversionTable',
            borrowernumberConversionTable     => ($ENV{MMT_WORKING_DIR}//'.').'/borrowernumberConversionTable',
            booksellerConversionTable         => ($ENV{MMT_WORKING_DIR}//'.').'/booksellerConversionTable',
);


GetOptions(
    'subscriptionFile:s'       => \$args{subscriptionFile},
    'serialFile:s'             => \$args{serialFile},
    'routinglistFile:s'        => \$args{routinglistFile},
    'suConversionTable:s'      => \$args{subscriptionidConversionTableFile},
    'b|bnConversionTable:s'    => \$args{biblionumberConversionTable},
    'i|inConversionTable:s'    => \$args{itemnumberConversionTable},
    'B|bsConversionTable:s'    => \$args{booksellerConversionTable},
    'v|verbosity:i'            => \$verbosity,
);

my $help = <<HELP;

NAME
  $0 - Import Subscriptions and Serials en masse

SYNOPSIS
  perl bulkSubscriptionImport.pl \
    --subscriptionFile $args{subscriptionfile} \
    --serialFile $args{serialFile} \
    --routinglistFile $args{routinglistFile} \
    -v $verbosity \
    --suConversionTable $args{subscriptionidConversionTableFile} \
    --bnConversionTable $args{biblionumberConversionTable} \
    --inConversionTable $args{itemnumberConversionTable}
    --bsConversionTable $args{booksellerConversionTable}


DESCRIPTION

    --subscriptionFile filepath
          The perl-serialized HASH of Subscriptions.

    --serialFile filepath
          The perl-serialized HASH of Serials.

    --routinglistFile filepath
          The perl-serialized HASH of Subscriptionroutinglist.

    --suConversionTable filePath
          Defaults to $args{subscriptionidConversionTableFile}
          Where to write the converted subscriptionids.

    --bnConversionTable filePath
          Defaults to $args{biblionumberConversionTable}
          Where to get the converted biblionumbers.

    --inConversionTable filePath
          Defaults to $args{itemnumberConversionTable}
          Where to get the converted itemnumbers.

    -v level
          Verbose output to the STDOUT,
          Defaults to $verbosity, 6 is max verbosity, 0 is fatal only.

HELP

require Bulk::Util; #Init logging && verbosity

unless ($args{subscriptionfile}) {
    die "$help\n\n--subscriptionFile is mandatory";
}
unless ($args{serialFile}) {
    die "$help\n\n--serialFile is mandatory";
}


my $dbh=C4::Context->dbh();


my $sub_insert_sth = $dbh->prepare("INSERT INTO subscription
                                    (librarian,     branchcode, biblionumber,   notes, status, internalnotes, location,
                                     startdate, firstacquidate, closed, cost, aqbooksellerid, enddate)
                                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)");
my $subhist_insert_sth = $dbh->prepare("INSERT INTO subscriptionhistory
                                    (biblionumber, subscriptionid, histstartdate, histenddate,
                                     missinglist, recievedlist)
                                    VALUES (?,?,?,?,?,?)");
my $sub_set_serial_sth = $dbh->prepare("UPDATE biblio
                                        SET serial=1
                                        WHERE biblionumber=?");

my $subhist_create_missing = $dbh->prepare #TODO: all subscriptions must have a subscriptionhistory-entry! It could be missing! How to create it ! Use Koha C4::Serial for it!

sub migrate_subscription($s) {
    $sub_insert_sth->execute('0', $s->{branchcode}, $s->{biblionumber}, $s->{notes}, $s->{status}, $s->{internalnotes}, $s->{location},
                                  $s->{startdate}, $s->{firstacquidate}, $s->{closed}, $s->{cost}, $s->{aqbooksellerid}, $s->{enddate})
      or die "INSERT:ing Subscription failed: ".$sub_insert_sth->errstr();

    my $newSubscriptionid = $dbh->last_insert_id(undef, undef, 'subscription', 'subscriptionid') or die("Fetching last insert if failed: ".$dbh->errstr());
    $args{subscriptionidConversionTable}->writeRow($s->{subscriptionid}, $newSubscriptionid);

    $sub_set_serial_sth->execute($s->{biblionumber}) or die("Setting the biblio serial-flag failed: ".$sub_set_serial_sth->errstr());
}

sub migrate_subscriptionhistory($s) {
    $subhist_insert_sth->execute($s->{biblionumber}, $s->{subscriptionid}, $s->{startdate}, $s->{enddate}, '', $s->{subscriptionhistory})
      or die "INSERT:ing Subscriptionhistory failed: ".$subhist_insert_sth->errstr();
}

my $ser_insert_sth = $dbh->prepare("INSERT INTO serial
                                (biblionumber, subscriptionid, status, planneddate, publisheddate,
                                 serialseq, serialseq_x, serialseq_y, serialseq_z)
                                VALUES (?,?,?,?,?,
                                        ?,?,?,?)");
sub migrate_serial($s) {
    eval {
        $ser_insert_sth->execute($s->{biblionumber},$s->{subscriptionid},$s->{status},      $s->{planneddate}, $s->{publisheddate},
                                 $s->{serialseq},   $s->{serialseq_x},   $s->{serialseq_y}, $s->{serialseq_z})
          or die "INSERT:ing Serial failed: ".$ser_insert_sth->errstr();
        $s->{serialid} = $ser_insert_sth->{mysql_insertid} // $ser_insert_sth->last_insert_id() // die("Couldn't get the last_insert_id from a newly created serial ".np($s));
    };

    migrate_serialitems($s) if $s->{itemnumber};
}

my $seritems_insert_sth = $dbh->prepare("INSERT INTO serialitems
                                (itemnumber, serialid)
                                VALUES (?,?)");
sub migrate_serialitems($s) {
    eval {
        $seritems_insert_sth->execute($s->{itemnumber},$s->{serialid})
          or die "INSERT:ing Serialitem failed: ".$seritems_insert_sth->errstr();
    };
}

my $srl_insert_sth = $dbh->prepare("INSERT INTO subscriptionroutinglist
                                      (borrowernumber, ranking, subscriptionid)
                                      VALUES (?,?,?)");
sub migrate_srl($s) {
    eval {
        $srl_insert_sth->execute($s->{borrowernumber},$s->{ranking},$s->{subscriptionid})
          or die "INSERT:ing SRL failed: ".$srl_insert_sth->errstr();
    };
}

sub validateAndConvertSubscriptionKeys($s) {
    my $errId = "Subscription sub='".$s->{subscriptionid}."', bib='".$s->{biblionumber}."'";

    my $newBiblionumber = $args{biblionumberConversionTable}->fetch($s->{biblionumber});
    unless ($newBiblionumber) {
        WARN "$errId has no new biblionumber in the biblionumberConversionTable!";
        return undef;
    }
    $s->{biblionumber} = $newBiblionumber;

    my $newAqbooksellerid = $args{booksellerConversionTable}->fetch($s->{aqbooksellerid});
    unless ($newAqbooksellerid) {
        WARN "$errId has no new Aqbooksellerid in the booksellerConversionTable!";
        return undef;
    }
    $s->{aqbooksellerid} = $newAqbooksellerid;

    return $s;
}

sub validateAndConvertSerialKeys($s) {
    my $errId = "Serial sub='".$s->{subscriptionid}."', ser='".$s->{serialid}."'";

    my $newSubscriptionid = $args{subscriptionidConversionTable}->fetch($s->{subscriptionid});
    unless ($newSubscriptionid) {
        WARN "$errId has no new subscriptionid in the subscriptionidConversionTable!";
        return undef;
    }
    my $newBiblionumber = $args{biblionumberConversionTable}->fetch($s->{biblionumber});
    unless ($newBiblionumber) {
        WARN "$errId has no new biblionumber in the biblionumberConversionTable!";
        return undef;
    }

    if ($s->{itemnumber}) { #Not all serials have attached Items
        my $newItemnumber = $args{itemnumberConversionTable}->fetch($s->{itemnumber});
        unless ($newItemnumber) {
            WARN "$errId has no new itemnumber in the itemnumberConversionTable!";
            return undef;
        }
        $s->{itemnumber} = $newItemnumber;
    }

    $s->{biblionumber} = $newBiblionumber;
    $s->{subscriptionid} = $newSubscriptionid;
    return $s;
}

sub validateAndConvertSRLKeys($s) {
    my $errId = "SRL sub='".$s->{subscriptionid}."', bor='".$s->{borrowernumber}."'";

    my $newSubscriptionid = $args{subscriptionidConversionTable}->fetch($s->{subscriptionid});
    unless ($newSubscriptionid) {
        WARN "$errId has no new subscriptionid in the subscriptionidConversionTable!";
        return undef;
    }
    my $newBorrowernumber = $args{borrowernumberConversionTable}->fetch($s->{borrowernumber});
    unless ($newBorrowernumber) {
        WARN "$errId has no new borrowernumber in the borrowernumberConversionTable!";
        return undef;
    }

    $s->{borrowernumber} = $newBorrowernumber;
    $s->{subscriptionid} = $newSubscriptionid;
    return $s;
}











INFO "Opening SubscriptionidConversionTable '$args{subscriptionidConversionTableFile}' for writing";
$args{subscriptionidConversionTable} = Bulk::ConversionTable::SubscriptionidConversionTable->new($args{subscriptionidConversionTableFile}, 'write');
INFO "Opening BiblionumberConversionTable '$args{biblionumberConversionTable}' for reading";
$args{biblionumberConversionTable} = Bulk::ConversionTable::BiblionumberConversionTable->new($args{biblionumberConversionTable}, 'read');
INFO "Opening ItemnumberConversionTable '$args{itemnumberConversionTable}' for reading";
$args{itemnumberConversionTable} = Bulk::ConversionTable::ItemnumberConversionTable->new($args{itemnumberConversionTable}, 'read');
INFO "Opening BooksellerConversionTable '$args{booksellerConversionTable}' for reading";
$args{booksellerConversionTable} = Bulk::ConversionTable::SubscriptionidConversionTable->new($args{booksellerConversionTable}, 'read');

my $fh = Bulk::Util::openFile($args{subscriptionfile});
my $i = 0;
while (<$fh>) {
    $i++;
    INFO "Processed $i Subscriptions" if ($i % 100 == 0);

    my $subscription = Bulk::Util::newFromBlessedMigratemeRow($_);
    next unless validateAndConvertSubscriptionKeys($subscription);
    migrate_subscription($subscription);
    migrate_subscriptionhistory($subscription);
}
$fh->close();
$args{subscriptionidConversionTable}->close();

INFO "Opening SubscriptionidConversionTable '$args{subscriptionidConversionTableFile}' for reading";
$args{subscriptionidConversionTable} = Bulk::ConversionTable::SubscriptionidConversionTable->new($args{subscriptionidConversionTableFile}, 'read');
$fh = Bulk::Util::openFile($args{serialFile});
$i = 0;
while (<$fh>) {
    $i++;
    INFO "Processed $i Serials" if ($i % 1000 == 0);

    my $serial = Bulk::Util::newFromBlessedMigratemeRow($_);
    next unless validateAndConvertSerialKeys($serial);
    migrate_serial($serial);
}
$fh->close();



INFO "Opening BorrowernumberConversionTable '$args{borrowernumberConversionTable}' for reading";
$args{borrowernumberConversionTable} = Bulk::ConversionTable::BorrowernumberConversionTable->new($args{borrowernumberConversionTable}, 'read');
$fh = Bulk::Util::openFile($args{routinglistFile});
$i = 0;
while (<$fh>) {
    $i++;
    INFO "Processed $i Subscriptionroutinglists" if ($i % 1000 == 0);

    my $srl = Bulk::Util::newFromBlessedMigratemeRow($_);
    next unless validateAndConvertSRLKeys($srl);
    migrate_srl($srl);
}
$fh->close();

