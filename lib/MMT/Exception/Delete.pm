package MMT::Exception::Delete;

use 5.22.1;

use Exception::Class (
    'MMT::Exception::Delete' => {
        isa => 'MMT::Exception',
        description => 'This object is marked for deletion by the receiving Builder-instance',
    },
);

return 1;