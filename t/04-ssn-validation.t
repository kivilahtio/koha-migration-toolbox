use MMT::Pragmas;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::Most tests => 10;

use MMT::Validator;

#These tests fail, SSN is invalid                       This is the SSN      This is what the validator says about the SSN                           This is the name of the test when the test suite is ran
throws_ok( sub { MMT::Validator::checkIsValidFinnishSSN('via Hetula' ) },    qr/Given ssn 'via Hetula' is not well formed/,                          'via Hetula is not well formed');
throws_ok( sub { MMT::Validator::checkIsValidFinnishSSN('300499-1803221') }, qr/Given ssn '300499-1803221' is not well formed/,                      '300499-1803221 is not well formed');
throws_ok( sub { MMT::Validator::checkIsValidFinnishSSN('090900-1803232') }, qr/Given ssn '090900-1803232' is not well formed/,                      '090900-1803232 is not well formed');
throws_ok( sub { MMT::Validator::checkIsValidFinnishSSN('221285-125Q') },    qr/Given ssn '221285-125Q' has a bad checksum-component. Expected 'U'/, '221285-125Q should have checksum U');
throws_ok( sub { MMT::Validator::checkIsValidFinnishSSN('101010-101A') },    qr/Given ssn '101010-101A' has a bad checksum-component. Expected 'B'/, '101010-101A should have checksum B');
throws_ok( sub { MMT::Validator::checkIsValidFinnishSSN('331012-554K') },    qr/Given ssn '331012-554K' has a bad day-component/,                    '331012-554K has a bad day');
throws_ok( sub { MMT::Validator::checkIsValidFinnishSSN('235012-004S') },    qr/Given ssn '235012-004S' has a bad month-component/,                  '235012-004S has a bad month');

#These tests pass, SSN is valid
lives_ok( sub { MMT::Validator::checkIsValidFinnishSSN('031289-124K') }, '031289-124K is valid');
lives_ok( sub { MMT::Validator::checkIsValidFinnishSSN('311055-234T') }, '311055-234T is valid');
lives_ok( sub { MMT::Validator::checkIsValidFinnishSSN('120408+4108') }, '120408+4108 is valid');
