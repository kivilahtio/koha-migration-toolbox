BEGIN {
  use FindBin;
  use lib "$FindBin::Bin/../lib";
  $ENV{MMT_HOME} = "$FindBin::Bin/../";
  print "# MMT_HOME => $FindBin::Bin/../\n";
}

use MMT::Pragmas;

use DateTime;

use Test::Most tests => 2;
use Test::Differences;
use Test::MockModule;

use MMT::TBuilder;
use MMT::Voyager2Koha::Patron;

use MMT::TranslationTable::Branchcodes;
use MMT::TranslationTable::NoteType;

my $builder = bless({
#  LocationId => MMT::TranslationTable::LocationId->new(),
   Branchcodes => MMT::TranslationTable::Branchcodes->new(),
}, 'MMT::TBuilder');

subtest "Add Popup notes via the translation table", sub {

  ok(my $patron = MMT::Voyager2Koha::Patron->new(),
    "Given a patron");

  ok(! MMT::TranslationTable::NoteType->popUp($patron, {}, $builder, '', '', [{
    patron_note_id => 1,
    note => 'message1',
    modify_date => '2018-01-01',
  }]),
    "When a popup note is added");

  cmp_deeply($patron->{popup_message}, {
      message => 'message1',
      branchcode => 'HAMK',
      message_date => '2018-01-01',
    },
    "Then the first pop-up note is inside the Patron insides");

  ok(! MMT::TranslationTable::NoteType->popUp($patron, {}, $builder, '', '', [{
    patron_note_id => 2,
    note => 'message2',
    modify_date => '2018-01-02',
  }]),
    "When the second popup note is added");

  cmp_deeply($patron->{popup_message}, {
      message => 'message1 | message2',
      branchcode => 'HAMK',
      message_date => '2018-01-01',
    },
    "Then the second pop-up note is inside the Patron insides");
};

subtest "Add Popup note with missing details", sub {
  ok(my $patron = MMT::Voyager2Koha::Patron->new(),
    "Given a patron");
  ok($patron->_addPopUpNote($builder, 'message1', undef, undef),
    "When a popup note without a date or branch is added");

  cmp_deeply(
    $patron->{popup_message},
    {
      message => 'message1',
      branchcode => 'HAMK',
      message_date => re(DateTime->now->ymd()),
    },
    "Then the first pop-up note is inside the Patron insides");

  ok($patron->_addPopUpNote($builder, 'message2', 'JYU', '2018-01-02'),
    "When the second popup note without a date of branch is added");
  cmp_deeply($patron->{popup_message}, {
      message => 'message1 | message2',
      branchcode => 'HAMK',
      message_date => re(DateTime->now->ymd()),
    },
    "Then the second pop-up note is inside the Patron insides");
};
