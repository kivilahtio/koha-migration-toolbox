package Bulk::ConversionTable::BiblionumberConversionTable;

use Modern::Perl;

BEGIN {
    use FindBin;
    eval { use lib "$FindBin::Bin/../"; };
}

use Bulk::ConversionTable;
our @ISA = qw(Bulk::ConversionTable);

use Carp qw(cluck);

sub readRow {
    my ($self, $textRow) = @_;

    if ( $_ =~ /^([0-9A-Z-]+);(\d+);/ ) {
        my $legacy_biblionumber = $1;
        my $koha_biblionumber   = $2;

        $self->{table}->{$legacy_biblionumber} = $koha_biblionumber;
    }
    elsif ($textRow =~ /^id;newid;operation;status/ || $textRow =~ /^file : .*?/ || $textRow =~ /^\d+ MARC records done in / ) {
        #It's ok
    }
    else {
        print "warning: ConversionTable::BiblionumberConversionTable->readRow(): Couldn't parse biblionumber row: $_\n";
    }
}

sub writeRow {
    my ($self, $legacyBiblionumber, $newBiblionumber, $operation, $statusOfOperation) = @_;

    my $fh = $self->{FILE};
    print $fh "$legacyBiblionumber;$newBiblionumber;$operation;$statusOfOperation\n";
}

1;
