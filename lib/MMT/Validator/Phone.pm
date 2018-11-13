package MMT::Validator::Phone;

use MMT::Pragmas;

#External modules
use File::Basename;
use Data::Printer colored => 1;

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::Validator::Phone - Phone number validation strategies

=head1 DESCRIPTION

Contains subroutines implementing various phone number validation strategies.
The desired strategy is chosen via configuration.

So far the only place which uses phone number validations is the MMT::Koha::Patron-transformer.
If different types of data sources need transformation, extend with $kohaObject type checks.

=head1 AVAILABLE STRATEGIES

Finnish
HAMK
International
JYU

=cut

=head2 validate

Validates the given phone number,
in the context of the given related objects.

Validation actually logs and sets different $kohaObject attributes and is more of a
transformation strategy than a simple validator.

Hence the extended context to help solve possibly complex validation and data repair scenarios.


All strategies share the same subroutine interface:

 @param {MMT::KohaObject}
 @param {HASHRef}
 @param {MMT::TBuilder}
 @param {String} Phone number candidate to validate/transform in the context of the given objects.
 @returns {LIST} [0] {String} - The new phone number, depending on the strategy used it might have mutated
                 [1] {Boolean} - Let it pass? Should the given phone number be migrated to Koha, or removed from migration.

=cut

our $validatorStrategy; #Cache the validator strategy. Make it accessible from tests so it can be flushed
sub validate($kohaObject, $voyagerObject, $builder, $phoneCandidate) {
  unless ($validatorStrategy) {
    $validatorStrategy = __PACKAGE__->can('strategy_'.MMT::Config::phoneNumberValidationStrategy());
    die "Unknown phone number validation strategy '".__PACKAGE__.'::strategy_'.MMT::Config::phoneNumberValidationStrategy()."'" unless ($validatorStrategy);
  }
  return $validatorStrategy->(@_);
}

=head2 strategy_Finnish

See. https://en.wikipedia.org/wiki/Telephone_numbers_in_Finland

=cut

sub strategy_Finnish($kohaObject, $voyagerObject, $builder, $phoneCandidate) {
  unless(_isValidFinnishPhoneNumber($phoneCandidate)) {
    $kohaObject->concatenate("Kirjastojärjestelmävaihdon yhteydessä on havaittu, että puhelinnumero '$phoneCandidate' ei ole Suomen viestintäministeriön asettaman Suomalaisen mallin mukainen. Ota yhteyttä kirjastoosi asian korjaamiseksi." => 'opacnote');
    $log->warn($kohaObject->logId()." - Finnish phone number validation failed for number '$phoneCandidate'. opacnote generated.");
    return ($phoneCandidate, 0);
  }
  return ($phoneCandidate, 1);
}

sub _isValidFinnishPhoneNumber($value) {
  return $value =~ m/^((90[0-9]{3})?0|\+358\s?)(?!(100|20(0|2(0|[2-3])|9[8-9])|300|600|700|708|75(00[0-3]|(1|2)\d{2}|30[0-2]|32[0-2]|75[0-2]|98[0-2])))(4|50|10[1-9]|20(1|2(1|[4-9])|[3-9])|29|30[1-9]|71|73|75(00[3-9]|30[3-9]|32[3-9]|53[3-9]|83[3-9])|2|3|5|6|8|9|1[3-9])\s?(\d\s?){4,19}\d$/;
}

sub strategy_HAMK($kohaObject, $voyagerObject, $builder, $phoneCandidate) {
  my ($phoneCandidateTrimmed, $strippedCharactersCount) = _dropNonNumbers($phoneCandidate);
  if ($strippedCharactersCount >= 3) { #Dont complain about every small mistake. Expect large differences to have some special type of information embedded which the librarians might want to manually verify.
    my $msg = "Messy phone number '$phoneCandidate' trimmed as '$phoneCandidateTrimmed'.";
    $kohaObject->concatenate($msg => 'borrowernotes');
    $log->warn($kohaObject->logId().' - '.$msg);
  }

  return strategy_Finnish($kohaObject, $voyagerObject, $builder, $phoneCandidateTrimmed);
}

sub _dropNonNumbers($value) {
  #Drop any non-numberal characters first
  #https://tiketti.koha-suomi.fi:83/issues/3301
  my $number = $value;
  $number =~ s/[^+ 0-9]//gsm;
  my $strippedCharactersCount = length($value) - length($number);
  $number =~ s/\s//gsm; #Ignore whitespace from the stripped characters count, as they are rather meaningless considering the information value contains by themselves, and lead to post-validation issues if leading/trailing whitespace exists.
  return ($number, $strippedCharactersCount);
}

=head2 strategy_International

See. https://www.oreilly.com/library/view/regular-expressions-cookbook/9781449327453/ch04s03.html
See. ITU-T E.164  =>  https://www.itu.int/rec/T-REC-E.164/en

From Wikipedia, the free encyclopedia:
E.164 is an ITU-T recommendation, titled The international public telecommunication numbering plan, that defines a numbering plan for the worldwide public switched telephone network (PSTN) and some other data networks. 

=cut

sub strategy_International($kohaObject, $voyagerObject, $builder, $phoneCandidate) {
  unless (_isValidInternationalPhoneNumber($phoneCandidate)) {
    $kohaObject->concatenate("Kirjastojärjestelmävaihdon yhteydessä on havaittu, että puhelinnumero '$phoneCandidate' on mahdollisesti virheellinen. Ota yhteyttä kirjastoosi asian korjaamiseksi." => 'opacnote');
    $log->warn($kohaObject->logId()." - International phone number validation failed for number '$phoneCandidate'. opacnote generated.");
    return ($phoneCandidate, 0);
  }
  return ($phoneCandidate, 1);
}

sub _isValidInternationalPhoneNumber($value) {
  return $value =~ m!^\+(?:[0-9] ?){6,14}[0-9]$!;
  return $value =~ m!
    ^         # Assert position at the beginning of the string.
    \+        # Match a literal "+" character.
    (?:       # Group but don't capture:
      [0-9]   #   Match a digit.
      \x20    #   Match a space character
        ?     #     between zero and one time.
    )         # End the noncapturing group.
      {6,14}  #   Repeat the group between 6 and 14 times.
    [0-9]     # Match a digit.
    $         # Assert position at the end of the string.
  !x;
}

sub strategy_JYU($kohaObject, $voyagerObject, $builder, $phoneCandidate) {
  my ($phoneCandidateTrimmed, $strippedCharactersCount) = _dropNonNumbers($phoneCandidate);
  if ($strippedCharactersCount >= 3) { #Dont complain about every small mistake. Expect large differences to have some special type of information embedded which the librarians might want to manually verify.
    my $msg = "Messy phone number '$phoneCandidate' trimmed as '$phoneCandidateTrimmed'.";
    $kohaObject->concatenate($msg => 'borrowernotes');
    $log->warn($kohaObject->logId().' - '.$msg);
  }

  # regexp pattern form https://www.regextester.com/97440
  unless ($phoneCandidateTrimmed =~ m/^(([+][(]?[0-9]{1,3}[)]?)|([(]?[0-9]{4}[)]?))\s*[)]?[-\s\.]?[(]?[0-9]{1,3}[)]?([-\s\.]?[0-9]{3})([-\s\.]?[0-9]{3,4})\d$/) {
    my $notification = "JYU phone number validation failed for number '$phoneCandidateTrimmed'. opacnote generated.";
    $log->warn($kohaObject->logId()." - $notification");
    $kohaObject->concatenate($notification => 'borrowernotes');
    $kohaObject->concatenate("Kirjastojärjestelmävaihdon yhteydessä on havaittu, että puhelinnumero '$phoneCandidateTrimmed' on mahdollisesti virheellinen. Ota yhteyttä kirjastoosi asian korjaamiseksi." => 'opacnote');
  }
  return ($phoneCandidateTrimmed, 1);
}

1;
