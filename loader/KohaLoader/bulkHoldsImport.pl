#!/usr/bin/perl

use Modern::Perl;
use experimental 'smartmatch', 'signatures';
$|=1;
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDIN, ":encoding(UTF-8)");

use Getopt::Long;
use Log::Log4perl qw(:easy);

use Bulk::ConversionTable::ItemnumberConversionTable;
use Bulk::ConversionTable::BorrowernumberConversionTable;
use Bulk::ConversionTable::BiblionumberConversionTable;
use Bulk::PatronImporter;

use C4::Letters;
use C4::Context;

use Koha::Libraries;

our $verbosity = 3;

my %args = (importFile =>                     ($ENV{MMT_DATA_SOURCE_DIR}//'.').'/Reserve.migrateme',
            borrowernumberConversionTable =>  ($ENV{MMT_WORKING_DIR}//'.').'/borrowernumberConversionTable',
            biblionumberConversionTable =>    ($ENV{MMT_WORKING_DIR}//'.').'/biblionumberConversionTable',
            itemnumberConversionTable =>      ($ENV{MMT_WORKING_DIR}//'.').'/itemnumberConversionTable');

my $help = <<HELP;

NAME
  $0 - Import reserves en masse

SYNOPSIS
  perl bulkHoldsImport.pl --file /home/koha/pielinen/holds.migrateme -v 6 \
      -b $args{biblionumberConversionTable} \
      -i $args{itemnumberConversionTable} \
      -o $args{borrowernumberConversionTable}

DESCRIPTION
  Migrates the Perl-serialized MMT-processed holds-files to Koha.

    --file filepath
          The perl-serialized HASH of reserves.

    -b --bnConversionTable filepath
          Defaults to '$args{biblionumberConversionTable}'.

    -i --inConversionTable filepath
          Defaults to '$args{itemnumberConversionTable}'.

    -o --bornumConversionTable filepath
          Defaults to '$args{borrowernumberConversionTable}'.

    -v level
          Verbose output to the STDOUT,
          Defaults to $verbosity, 6 is max verbosity, 0 is fatal only.

HELP

GetOptions(
    'file:s'                               => \$args{importFile},
    'o|bornumConversionTable:s'            => \$args{borrowernumberConversionTable},
    'i|inConversionTable:s'                => \$args{itemnumberConversionTable},
    'b|bnConversionTable:s'                => \$args{biblionumberConversionTable},
    'v|verbosity:i'                        => \$verbosity,
);

require Bulk::Util; #Init logging && verbosity

unless ($args{importFile}) {
    die "$help\n\n--file is mandatory";
}

INFO "Opening BorrowernumberConversionTable '$args{borrowernumberConversionTable}' for reading";
$args{borrowernumberConversionTable} = Bulk::ConversionTable::BorrowernumberConversionTable->new( $args{borrowernumberConversionTable}, 'read' );
INFO "Opening ItemnumberConversionTable '$args{itemnumberConversionTable}' for reading";
$args{itemnumberConversionTable}     = Bulk::ConversionTable::ItemnumberConversionTable->new(     $args{itemnumberConversionTable},     'read' );
INFO "Opening BiblionumberConversionTable '$args{biblionumberConversionTable}' for reading";
$args{biblionumberConversionTable}   = Bulk::ConversionTable::BiblionumberConversionTable->new(   $args{biblionumberConversionTable} ,  'read' );

my $dbh=C4::Context->dbh;

my $fh = Bulk::Util::openFile($args{importFile});
my $i = 0;
while (<$fh>) {
    $i++;
    INFO "Processed $i Items" if ($i % 1000 == 0);

    my $hold = Bulk::Util::newFromBlessedMigratemeRow($_);
    next unless convertKeys($hold);
    next unless addHold($hold);
    createNotification($hold) if ($hold->{found} && $hold->{found} eq 'W');
}

my $sth_addHold;
sub addHold($hold) {
    unless ($sth_addHold) {
        $sth_addHold = $dbh->prepare(qq/
            INSERT INTO reserves
                (borrowernumber,biblionumber,reservedate,branchcode,priority,reservenotes,itemnumber,found,waitingdate,expirationdate)
            VALUES
                (?,             ?,           ?,          ?,         ?,       ?,           ?,         ?,    ?,          ?)
        /) or die("Preparing the reserves statements failed: ".$sth_addHold->errstr());
    }
    $sth_addHold->execute(
        $hold->{borrowernumber}, $hold->{biblionumber}, $hold->{reservedate},          $hold->{branchcode},
        $hold->{priority},       $hold->{reservenotes}, $hold->{itemnumber},
        $hold->{found},          $hold->{waitingdate},	$hold->{expirationdate}
    ) or die("Adding a new reserve failed: ".$sth_addHold->errstr());
    $hold->{reserve_id} = $dbh->last_insert_id(undef, undef, 'reserves', 'reserve_id') or die("Fetching last insert if failed: ".$dbh->errstr());

    return 1;
}

=head2 convertKeys

Converts primary|foreign keys biblionumber, itemnumber, borrowernumber via ConversionTables to match the new primary keys
of previously added Biblios, Items and Patrons.

=cut

sub convertKeys {
    my ($hold) = @_;

    my ($biblionumber, $itemnumber, $borrowernumber);

    $itemnumber = $args{itemnumberConversionTable}->fetch(  $hold->{itemnumber}  ) if $hold->{itemnumber};
    if (not($itemnumber) && $hold->{itemnumber}) {
        WARN holdId($hold)." has no Item in conversion table, even if the Hold initially targets a specific Item!";
        return undef;
    }

    my $waiting = $hold->{waiting};
    if (not($itemnumber) && $hold->{waiting} && $hold->{waiting} eq 'W') {
        WARN holdId($hold)." has no Item in conversion table, even if the Hold is waiting!";
        return undef;
    }

    $borrowernumber = $args{borrowernumberConversionTable}->fetch(  $hold->{borrowernumber}  );
    unless ($borrowernumber) {
        WARN holdId($hold)." has no Borrower in conversion table!";
        return undef;
    }

    $biblionumber = $args{biblionumberConversionTable}->fetch(  $hold->{biblionumber}  );
    unless ($biblionumber) {
        WARN holdId($hold)." has no Biblio in conversion table!";
        return undef;
    }

    $hold->{biblionumber}   = $biblionumber;
    $hold->{itemnumber}     = $itemnumber;
    $hold->{borrowernumber} = $borrowernumber;

    return 1;
}

=head2 createNotification

Queues a "hold ready for pickup"-notification for holds waiting for pickup.

=cut

sub createNotification($hold) {
    INFO "Creating a notification for ".holdId($hold);
    my $borrower = Bulk::PatronImporter::GetBorrower($hold->{borrowernumber});
    my $branch_details = Koha::Libraries->find($borrower->{branchcode})->unblessed;
    my $letter = C4::Letters::GetPreparedLetter (
        module => 'reserves',
        letter_code => 'HOLD',
        branchcode => $hold->{branchcode},
        tables => {
            'branches'  => $branch_details,
            'borrowers' => $borrower,
            'biblio'    => $hold->{biblionumber},
            'items'     => $hold->{itemnumber},
            #'reserves'  => {borrowernumber => $hold->{borrowernumber}, biblionumber => $hold->{biblionumber}}, #This part of Koha needs to be fixed to use the reserve_id instead
        },
    );
    DEBUG "Letter: $letter";

    unless ($letter) {
        return undef;
    }
    my $admin_email_address = $branch_details->{'branchemail'} || C4::Context->preference('KohaAdminEmailAddress');

    C4::Letters::EnqueueLetter(
        {
            letter                 => $letter,
            borrowernumber         => $hold->{borrowernumber},
            message_transport_type => 'email',
            from_address           => $admin_email_address,
            to_address             => $borrower->{email},
        }
    );
}

sub holdId($hold) {
    return "Hold: p".$hold->{borrowernumber}."-b:".$hold->{biblionumber}."-i:".($hold->{itemnumber} || 'NULL');
}
