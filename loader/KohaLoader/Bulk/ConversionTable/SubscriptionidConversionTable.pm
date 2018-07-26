package Bulk::ConversionTable::SubscriptionidConversionTable;

use Modern::Perl '2015';

BEGIN {
    use FindBin;
    eval { use lib "$FindBin::Bin/../"; };
}

use Bulk::ConversionTable;
our @ISA = qw(Bulk::ConversionTable);

use Carp qw(cluck);

sub readRow {
    my ($self, $textRow) = @_;

    if ( $_ =~ /^(\d+)\s+(\d+)$/ ) {
        my $oldSubscriptionid = $1;
        my $newSubscriptionid = $2;

        $self->{table}->{$oldSubscriptionid} = $newSubscriptionid;
    }
    else {
        print __PACKAGE__.'::'.__SUB__."(): Couldn't parse row: $_\n";
    }
}
sub writeRow {
    my ($self, $oldSubscriptionid, $newSubscriptionid) = @_;

    my $fh = $self->{FILE};
    print $fh "$oldSubscriptionid $newSubscriptionid\n";
}

1;
