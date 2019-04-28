package MMT::Exception::SSN;

use MMT::Pragmas;

use Exception::Class (
    'MMT::Exception::SSN' => {
        isa => 'MMT::Exception',
        description => 'There is something wrong with the SSN',
    },
);

return 1;