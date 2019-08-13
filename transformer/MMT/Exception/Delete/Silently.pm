package MMT::Exception::Delete::Silently;

use MMT::Pragmas;

use Exception::Class (
    'MMT::Exception::Delete::Silently' => {
        isa => 'MMT::Exception::Delete',
        description => 'This object is marked for silent deletion by the receiving Builder-instance',
    },
);

return 1;