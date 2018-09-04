package MMT::Exception::Delete;

use MMT::Pragmas;

use Exception::Class (
    'MMT::Exception::Delete' => {
        isa => 'MMT::Exception',
        description => 'This object is marked for deletion by the receiving Builder-instance',
    },
);

return 1;