package MMT::Validator::Barcode;

use MMT::Pragmas;

#External modules
use File::Basename;
use Data::Printer colored => 1;

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::Validator::Barcode - Barcode validation strategies

=head1 DESCRIPTION

Code39 has only a small set of characters allowed. Make sure the migrated barcodes are ok to avoid surprises when printing Code39's.

=head1 AVAILABLE STRATEGIES

Code39

=cut

=head2 validate

Validates the given barcode,
in the context of the given related objects.

Validation actually logs and sets different $kohaObject attributes and is more of a
transformation strategy than a simple validator.

Hence the extended context to help solve possibly complex validation and data repair scenarios.


All strategies share the same subroutine interface:

 @param {MMT::KohaObject}
 @param {HASHRef}
 @param {MMT::TBuilder}
 @param {String} Barcode candidate to validate/transform in the context of the given objects.
 @returns {LIST} [0] {String} - The new barcode, depending on the strategy used it might have mutated
                 [1] {Boolean} - Let it pass? Should the given barcode be migrated to Koha, or removed from migration.

=cut

our $validatorStrategy; #Cache the validator strategy. Make it accessible from tests so it can be flushed
sub validate($kohaObject, $voyagerObject, $builder, $barcodeCandidate) {
  unless ($validatorStrategy) {
    $validatorStrategy = __PACKAGE__->can('strategy_'.'Code39');
    die "Unknown Barcode validation strategy '".__PACKAGE__.'::strategy_'.'Code39'."'" unless ($validatorStrategy);
  }
  return $validatorStrategy->(@_);
}

=head2 strategy_Code39

See. https://en.wikipedia.org/wiki/Code_39

=cut

sub strategy_Code39($kohaObject, $prettyObject, $builder, $barcodeCandidate) {
  if ($barcodeCandidate =~ /^[a-zA-Z0-9\-\.\$\/\+\%\ ]+$/) {
      return (uc($barcodeCandidate), 1)
  }
  return ($barcodeCandidate, 0);
}

1;
