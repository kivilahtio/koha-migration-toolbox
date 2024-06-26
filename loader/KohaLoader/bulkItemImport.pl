#!/usr/bin/perl

use Modern::Perl;
$|=1;
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDIN, ":encoding(UTF-8)");

use Getopt::Long;
use Log::Log4perl qw(:easy);
use Time::HiRes qw(gettimeofday);

use Bulk::ConversionTable::ItemnumberConversionTable;
use Bulk::ConversionTable::BiblionumberConversionTable;
use Bulk::ConversionTable::SubscriptionidConversionTable;
use Bulk::AutoConfigurer;
use Bulk::Item;

our $verbosity = 3;
our %args = (itemsFile =>                          ($ENV{MMT_DATA_SOURCE_DIR}//'.').'/Item.migrateme',
            biblionumberConversionTable =>        ($ENV{MMT_WORKING_DIR}//'.').'/biblionumberConversionTable',
            itemnumberConversionTable =>          ($ENV{MMT_WORKING_DIR}//'.').'/itemnumberConversionTable',
            preserveIds =>                        $ENV{MMT_PRESERVE_IDS} // 0,
            populateStatistics =>           0);

GetOptions(
    'file:s'                   => \$args{itemsFile},
    's|statistics'             => \$args{populateStatistics},
    'b|bnConversionTable:s'    => \$args{biblionumberConversionTable},
    'i|inConversionTable:s'    => \$args{itemnumberConversionTable},
    'preserveIds'              => \$args{preserveIds},
    'v|verbosity'              => \$verbosity,
    'h|help'              => sub {
    print <<HELP;

NAME
  $0 - Import Items en masse

SYNOPSIS
  perl ./bulkItemsImport.pl --file /home/koha/pielinen/items.migrateme -v $verbosity \
      --bnConversionTable '$args{biblionumberConversionTable}'

DESCRIPTION
  -Migrates the Perl-serialized MMT-processed Items to Koha.
  -Populates statistics-table entries for old issues and returns.
   Item needs to have an 'issues'-attribute.
  -Detects duplicate barcodes and rebrands duplicates with '_TUPLA'-prefix

    --file filepath
          The perl-serialized HASH of Items.
          Defaults to '$args{itemsFile}'

    -s --statistics
          Populate the koha.statistics-table with dummy rows for each old
          issue. Creating a issue and return -entry for each time an old Item
          has been issued, takes a lot of time and HD space, but makes it much
          harder to accidentally lose this information.

    --bnConversionTable filepath
          From which file to read the converted biblionumber?
          We are adding Biblios to a database with existing Biblios, so we need to convert
          biblionumbers so they won't overlap with existing ones.
          biblionumberConversionTable has the following format, where first column is the original
          biblio id and the second column is the mapped Koha biblionumber:

              id;newid;operation;status
              685009;685009;insert;ok
              685010;685010;insert;ok
              685011;685011;insert;ok
              685012;685012;insert;ok
              ...

          Defaults to '$args{biblionumberConversionTable}'

    --inConversionTable filepath
          To which file to write the itemnumber to barcode conversion. Items are best referenced
          by their barcodes, because the itemnumbers can overlap with existing Items.
          Defaults to '$args{itemnumberConversionTable}'

    -v level
          Verbose output to the STDOUT,
          Defaults to $verbosity, 6 is max verbosity, 0 is fatal only.

HELP
    exit 0;
},
);

require Bulk::Util; #Init logging && verbosity

Bulk::Util::logArgs(\%args);

unless ($args{itemsFile}) {
    die "\n--file is mandatory";
}

use DateTime;
my $today = DateTime->now()->iso8601();
DEBUG "Today is $today";

INFO "Opening BiblionumberConversionTable '$args{biblionumberConversionTable}' for reading";
$args{biblionumberConversionTable} = Bulk::ConversionTable::BiblionumberConversionTable->new( $args{biblionumberConversionTable}, 'read' );
INFO "Opening ItemnumberConversionTable '$args{itemnumberConversionTable}' for writing";
$args{itemnumberConversionTable} = Bulk::ConversionTable::ItemnumberConversionTable->new( $args{itemnumberConversionTable}, 'write' );

sub processRow {
    my $item = Bulk::Util::newFromBlessedMigratemeRow($_);
    TRACE "Got Item '".$item->{itemnumber}.'-'.$item->{barcode}."'";

    ##After a few hundreds of thousands Items, the filehandle gets corrupt and mangles utf8.
    ##If you have trouble with that you can try these snippets to pin-point the issue
    ##It is most likely due to the statistics writing module trying to send too many INSERTs
    ##  at once and crashing repeatedly. MariaDB can't take everything I guess.
    #return if tryToCaptureMangledUtf8InDB($item);


    my $existingBarcodeItem = Bulk::Item::getItem($item->{barcode});
    if ($existingBarcodeItem) {
        $item->{barcode} .= '_TUPLA';
        INFO "\n".'DUPLICATE BARCODE "'.$item->{barcode}.'" FOUND'."\n";
    }
    my $newBiblionumber = $args{biblionumberConversionTable}->fetch($item->{biblionumber});
    if (not($newBiblionumber)) {
        ERROR "Failed to get biblionumber for Item ".$item->{barcode}."\n";
        return;
    }

    $item->{biblionumber} = $newBiblionumber;
    $item->{biblioitemnumber} = $newBiblionumber;


    #Autoconfigure shelving locations
    Bulk::AutoConfigurer::addBranch($item->{homebranch}, $item->{holdingbranch});
    Bulk::AutoConfigurer::shelvingLocation($item->{permanent_location}, $item->{location});
    Bulk::AutoConfigurer::itemType($item->{itype});

    Bulk::Item::set_cn_sort($item);

    my ($newItemnumber, $error);
    eval {
        ($newItemnumber, $error) = Bulk::Item::_koha_new_item($item);
    };
    if ($@ || $error) {
        if (Bulk::AutoConfigurer::item($item, $@ || $error)) { #Try to recover if the error is something the autoconfigurer can deal with
            eval {
                ($newItemnumber, $error) = Koha::Item::_koha_new_item($item);
            };
            if ($@ || $error) {
                warn $@;
                return undef;
            }
        }
        else {
            warn $@;
            return undef;
        }
    }

    $error = "Failed to get itemnumber" if (not($newItemnumber));
    if ($error) {
        ERROR "Error '$error' when INSERT:ing Item:\n".Data::Dumper::Dumper($item);
        return;
    }

    $args{itemnumberConversionTable}->writeRow($item->{itemnumber}, $newItemnumber, $item->{barcode});
    $item->{itemnumber} = $newItemnumber;

    createCheckoutStatistics($item);

}

my $starttime = gettimeofday;

my $i = 0;
my $fh = Bulk::Util::openFile($args{itemsFile}, $i);
while (<$fh>) {
    $i++;
    INFO "Processed $i Items" if ($i % 1000 == 0);
    processRow($_);
}
createCheckoutStatistics( undef, 'lastrun' );

my $timeneeded = gettimeofday - $starttime;
INFO "\n$. Items done in $timeneeded seconds\n";
close $fh;

=head2 createCheckoutStatistics

    +---------------------+--------+----------+--------+----------+-------+----------+------------+----------+----------------+--------------------+-------+
    | datetime            | branch | proccode | value  | type     | other | usercode | itemnumber | itemtype | borrowernumber | associatedborrower | ccode |
    +---------------------+--------+----------+--------+----------+-------+----------+------------+----------+----------------+--------------------+-------+
    | 2013-10-03 10:31:45 | IPT    | NULL     | 0.0000 | issue    |       | NULL     |          4 | BK       |             51 |               NULL | NULL  |
    | 2013-10-03 10:33:38 | IPT    | NULL     | 0.0000 | return   |       | NULL     |          4 | NULL     |             51 |               NULL | NULL  |
    | 2013-10-03 11:14:19 | IPT    | NULL     | 0.0000 | issue    |       | NULL     |          4 | BK       |             51 |               NULL | NULL  |
    | 2013-10-04 11:29:48 | IPT    | NULL     | 0.0000 | issue    |       | NULL     |          2 | BK       |             52 |               NULL | NULL  |

=cut

my $createCheckoutStatistics_sth;
sub createCheckoutStatistics {
    return if $args{populateStatistics};
    my ( $item, $lastrun ) = @_;

    my $dbh = C4::Context->dbh;
    $dbh->{'mysql_enable_utf8'} = 1;
    $dbh->do('SET NAMES utf8');

    my $issues = []; #Collect all the statistics elements here for one huge insertion!

    $createCheckoutStatistics_sth = $dbh->prepare("INSERT INTO statistics (branch, itemnumber, itemtype, type, other) ".
                                                  "VALUES                 (?     , ?         , ?       , ?   , ?)")
        unless $createCheckoutStatistics_sth;

    if ($item) {
        my $issuesCount = $item->{issues};

        if ( defined $issuesCount && $issuesCount > 0 ) {
            foreach ( 0 .. $issuesCount ) {
                push @$issues, [
                    $item->{homebranch},
                    $item->{itemnumber},
                    $item->{itype},
                ];
            }
        }
    }

    if ( scalar(@$issues) > 1000 || $lastrun ) {
        my $star = time;
        INFO "Writing statistics---";

        my $prevAutoCommit = $dbh->{AutoCommit};
        $dbh->{AutoCommit} = 0;
        foreach my $iss (@$issues) {
            $createCheckoutStatistics_sth->execute(@$iss, 'issue',  undef);
            $createCheckoutStatistics_sth->execute(@$iss, 'return', undef);
        }
        $dbh->commit();
        $dbh->{AutoCommit} = $prevAutoCommit;

        $issues  = [];
        INFO "Statistics written in " . ( $star - time ) . "s\n";
        $dbh->disconnect();
        $dbh = C4::Context->dbh; #Refresh the DB handle, because it occasionally gets mangled and spits bad utf8.
    }
}

sub tryToCaptureMangledUtf8InDB {
    my ($item) = @_;
    my $itemnotes = $item->{itemnotes};
    if ($itemnotes) {
        my $hstring = unpack ("H*",$itemnotes);
        #printf( "\n%12d - %20s - %s\n",$item->{biblionumber},$itemnotes,$hstring );

        if ($itemnotes =~ /\xc3\x83\xc2\xa4/ || $item->{itemcallnumber} =~ /\xc3\x83\xc2\xa4/ ||
            $itemnotes =~ /Ã¤/ || $item->{itemcallnumber} =~ /Ã¤/) {

            my $mangled = $item->{itemnotes}." ".$item->{itemcallnumber};
            WARN "Item ".$item->{itemnumber}." mangled like this:\n$mangled\n";
            WARN "Reopen and rewind the filehandle to position '".($i-1)."'.";
            $fh = openItemsFile($args{itemsFile}, $i-1);
            return 1;
        }
    }
    return undef;
}
