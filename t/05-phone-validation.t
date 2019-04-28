BEGIN { #Make the example config and translation tables available
  use FindBin;
  use lib "$FindBin::Bin/../lib";
  $ENV{MMT_HOME} = "$FindBin::Bin/../";
  print "# MMT_HOME => $FindBin::Bin/../\n";
}

use MMT::Pragmas;

use Test::Most tests => 5;

use MMT::Validator::Phone;

ok(my $builder = bless({}, 'MMT::TBuilder'),
  "Given a builder");

subtest "Finnish phone number validation strategy", sub {
  plan tests => 9;

  setPhoneNumberValidationStrategy('Finnish');

  my $pc; # $phoneNumberCandidate, $valid?, $kohaObject, $voyagerObject, $expectedKohaObject
  $pc = '+358 40 123 5432'; test($pc, 1, ko(),        {},             ko());
  $pc = '+3584544487653';   test($pc, 1, ko(),        {},             ko());
  $pc = '013 896 096';      test($pc, 1, ko(),        {},             ko());
  $pc = '3584544487653';    test($pc, 0, ko(),        {},             ko({opacnote => "Kirjastojärjestelmävaihdon yhteydessä on havaittu, että puhelinnumero '$pc' ei ole Suomen viestintäministeriön asettaman Suomalaisen mallin mukainen. Ota yhteyttä kirjastoosi asian korjaamiseksi."}));
};

subtest "International phone number validation strategy", sub {
  plan tests => 9;

  setPhoneNumberValidationStrategy('International');

  my $pc;    # $phoneNumberCandidate, $valid?, $kohaObject, $voyagerObject, $expectedKohaObject
  $pc = '+358 40 123 5432'; test($pc, 1, ko(),        {},             ko());
  $pc = '+4 455574586';     test($pc, 1, ko(),        {},             ko());
  $pc = '+22487653';        test($pc, 1, ko(),        {},             ko());
  $pc = '358 45 444 8765';  test($pc, 0, ko(),        {},             ko({opacnote => "Kirjastojärjestelmävaihdon yhteydessä on havaittu, että puhelinnumero '$pc' on mahdollisesti virheellinen. Ota yhteyttä kirjastoosi asian korjaamiseksi."}));
};

subtest "HAMK phone number validation strategy", sub {
  plan tests => 9;

  setPhoneNumberValidationStrategy('HAMK');

  my $pc;    # $phoneNumberCandidate, $valid?, $kohaObject, $voyagerObject, $expectedKohaObject
  $pc = '+358 40 123 5432';    test($pc, 1, ko(),        {},             ko());
  $pc = '013 896 096!';        test($pc, 1, ko(),        {},             ko());
  $pc = 'vaimon 040 554 3321'; test($pc, 1, ko(),        {},             ko({borrowernotes => "Messy phone number '$pc' trimmed as '0405543321'."}));
  $pc = '3584544487653';       test($pc, 0, ko(),        {},             ko({opacnote => "Kirjastojärjestelmävaihdon yhteydessä on havaittu, että puhelinnumero '$pc' ei ole Suomen viestintäministeriön asettaman Suomalaisen mallin mukainen. Ota yhteyttä kirjastoosi asian korjaamiseksi."}));
};

subtest "JYU phone number validation strategy", sub {
  plan tests => 9;

  setPhoneNumberValidationStrategy('JYU');

  my $pc;    # $phoneNumberCandidate, $valid?, $kohaObject, $voyagerObject, $expectedKohaObject
  TODO: {
    local $TODO = 'JYU tests';

    $pc = '+358 40 123 5432';    test($pc, 1, ko(),        {},             ko());
    $pc = '013 896 096!';        test($pc, 1, ko(),        {},             ko());
    $pc = 'vaimon 040 554 3321'; test($pc, 1, ko(),        {},             ko({borrowernotes => "Messy phone number '$pc' trimmed as '0405543321'."}));
    $pc = '3584544487653';       test($pc, 0, ko(),        {},             ko({opacnote => "Kirjastojärjestelmävaihdon yhteydessä on havaittu, että puhelinnumero '$pc' ei ole Suomen viestintäministeriön asettaman Suomalaisen mallin mukainen. Ota yhteyttä kirjastoosi asian korjaamiseksi."}));
  };
};

sub setPhoneNumberValidationStrategy($strategy) {
  $MMT::Validator::Phone::validatorStrategy = undef;
  $MMT::Config::config->{phoneNumberValidationStrategy} = $strategy;
  is(MMT::Config::phoneNumberValidationStrategy(), $strategy,
    "Given the 'phoneNumberValidationStrategy' is '$strategy'");
}

=head2 test

Making deep inspections just in case to catch unexpected attribute mutations

=cut

sub test($phoneCandidate, $valid, $kohaObject, $voyagerObject, $expectedKohaObject) {
  is(MMT::Validator::Phone::validate($kohaObject, $voyagerObject, $builder, $phoneCandidate), $valid,
    "$phoneCandidate validity '$valid'");
  cmp_deeply($kohaObject, $expectedKohaObject,
    "$phoneCandidate \$kohaObjects match");
}

# Factory for building test objects
use MMT::Voyager2Koha::Patron;
sub ko($args={}) {
  my $ko = MMT::Voyager2Koha::Patron->new();
  $ko->{borrowernumber} = 1;
  do {$ko->{$_} = $args->{$_}} for (keys(%$args));
  return $ko;
}
