package MMT::Exception;

use MMT::Pragmas;

use Exception::Class (
    'MMT::Exception' => {
        description => 'MMT exceptions base class',
    },
);

sub newFromDie {
    my ($class, $die) = @_;
    return Koha::Exception->new(error => "$die");
}

return 1;