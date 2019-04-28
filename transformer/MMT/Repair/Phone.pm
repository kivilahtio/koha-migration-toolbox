package MMT::Repair::Phone;

use MMT::Pragmas;

#External modules
use File::Basename;
use Data::Printer colored => 1;

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::Repair::Phone - Phone number repair strategies

=head1 DESCRIPTION

Contains subroutines implementing various phone number validation strategies.
The desired strategy is chosen via configuration.

So far the only place which uses phone number validations is the MMT::Voyager2Koha::Patron-transformer.
If different types of data sources need transformation, extend with $kohaObject type checks.

=head1 AVAILABLE STRATEGIES

FMA

=cut

=head2 repair

Repairs the given phone number, if needed.

All strategies share the same subroutine interface:

 @param {MMT::KohaObject}
 @param {HASHRef}
 @param {MMT::TBuilder}
 @param {String} Phone number candidate to validate/transform in the context of the given objects.
 @returns {LIST} [0] {String} - The new phone number, depending on the strategy used it might have mutated
                 [1] {Boolean} - Let it pass? Should the given phone number be migrated to Koha, or removed from migration.

=cut

sub repair($kohaObject, $voyagerObject, $builder, $phoneNumber) {
  return 0.$phoneNumber if length($phoneNumber) == 8 && $phoneNumber !~ /^0/;
  return $number =~ /
    (?<MOBILE>:40|44|45|50)
    (?:                         # +358408281247
      ^
      \+\d{3}[ -]\g{MOBILE}
    )|(?:                       # (0)?40 8281247
      0?\g{MOBILE}\d{7}
    )
  /x;
  ##TODO
}

1;
