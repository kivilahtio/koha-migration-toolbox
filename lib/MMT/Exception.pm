use 5.22.1;

package MMT::Exception;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';

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