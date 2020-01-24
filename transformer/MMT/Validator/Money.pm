package MMT::Validator::Money;

use MMT::Pragmas;

#External modules
use Data::Printer colored => 1;

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::Validator::Money - Validators/transformers where money talks

=head1 DESCRIPTION

Contains subroutines implementing various price validation strategies.
The desired strategy is autodetected via configuration 'sourceSystemType'.

=head2 replacementPrice

All strategies share the same subroutine interface:

 @param {MMT::KohaObject}
 @param {HASHRef}
 @param {MMT::TBuilder}
 @param {String} Phone number candidate to validate/transform in the context of the given objects.
 @returns {Float} The new price/value/mmoneyy

=cut

our $replacementPriceValidatorStrategy; #Cache the validator strategy. Make it accessible from tests so it can be flushed
sub replacementPrice($kohaObject, $voyagerObject, $builder, $priceCandidate) {
  unless ($replacementPriceValidatorStrategy) {
    $replacementPriceValidatorStrategy = __PACKAGE__->can('replacementPrice_'.MMT::Config::sourceSystemType());
    die "Unknown replacement price validation strategy '".__PACKAGE__.'::replacementPrice_'.MMT::Config::sourceSystemType()."'" unless ($replacementPriceValidatorStrategy);
  }
  return $replacementPriceValidatorStrategy->(@_);
}

#Alias the replacementPrice-strategies
eval '*'.__PACKAGE__.'::replacementPrice_Voyager = \&'.__PACKAGE__.'::money_Voyager';
eval '*'.__PACKAGE__.'::replacementPrice_PrettyLib = \&'.__PACKAGE__.'::money_PrettyLib';
eval '*'.__PACKAGE__.'::replacementPrice_PrettyCirc = \&'.__PACKAGE__.'::money_PrettyLib';

=head2 money

All strategies share the same subroutine interface:

 @param {MMT::KohaObject}
 @param {HASHRef}
 @param {MMT::TBuilder}
 @param {String} Phone number candidate to validate/transform in the context of the given objects.
 @returns {Float} The new price/value/mmoneyy

=cut

our $moneyValidatorStrategy; #Cache the validator strategy. Make it accessible from tests so it can be flushed
sub money($kohaObject, $voyagerObject, $builder, $priceCandidate) {
  unless ($moneyValidatorStrategy) {
    $moneyValidatorStrategy = __PACKAGE__->can('money_'.MMT::Config::sourceSystemType());
    die "Unknown money validation strategy '".__PACKAGE__.'::money_'.MMT::Config::sourceSystemType()."'" unless ($moneyValidatorStrategy);
  }
  return $moneyValidatorStrategy->(@_);
}

=head2 money_Voyager

Receives different types of inputs that represent a price, tries it's best to parse it into a number.
Detects currency signs and could do currency conversion in place.

 @returns {Float} Price exchanged to the current Koha valuation.
 @throws die, if Voyager money is not a valid number.

=cut

sub money_Voyager($kohaObject, $voyagerObject, $builder, $priceCandidate) {
  die "Fiscal value '$priceCandidate' is not a valid number" unless ($priceCandidate =~ /^[-+]?\d+\.?\d*$/);
  return sprintf("%.2f", $priceCandidate / 100); #Voyager has cents instead of the "real deal". This might be smart after all.
}

sub money_PrettyLib($kohaObject, $voyagerObject, $builder, $priceCandidate) {
  return undef unless $priceCandidate;

  $priceCandidate =~ s/\s//gsm;

  if ($priceCandidate =~ /^
                           (?<SYMBOL>    [-+]       )?
                           (?<PRICE>     \d+\.?\d*  )
                           (?<CURRENCY>  \D+)?
                          $/x) {
    my ($symbol, $price, $currency) = @+{qw(SYMBOL PRICE CURRENCY)};
    $symbol //= '';
    $price //= '';
    $currency //= '';
    $log->trace($kohaObject->logId()." - \$symbol='$symbol' \$price='$price' \$currency='$currency'");

    $symbol = '' if $symbol eq '+';

    # deal with currencies here
    if ($currency) {
      if ($currency =~ /^(?:€|eur)$/i) {
        return "$symbol$price";
      }
      else {
        $log->error($kohaObject->logId()." - Unknown currency '$currency'");
        return "$symbol$price";
      }
    }
    else {
      return "$symbol$price";
    }
  }
  else {
    $log->error("Failed to parse Pretty* money '$priceCandidate'");
    return undef;
  }
}

1;
