use Modern::Perl '2016';

package MMT::Koha::Subscription;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';
use English;

#External modules

#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);
use MMT::Date;
use MMT::Validator;

#Inheritance
use MMT::KohaObject;
use base qw(MMT::KohaObject);

#Exceptions
use MMT::Exception::Delete;

=head1 NAME

MMT::Koha::Subscription - Transforms a bunch of Voyager data into Koha subscriptions

=cut

=head2 build

 @param1 Voyager data object
 @param2 Builder

=cut

sub build($self, $o, $b) {

}

return 1;