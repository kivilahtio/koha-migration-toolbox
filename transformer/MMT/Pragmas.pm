package MMT::Pragmas;

binmode( STDOUT, ":encoding(UTF-8)" ); #Afaik this sets the shared handles for all modules
binmode( STDIN,  ":encoding(UTF-8)" );

=head1 NAME

MMT::Pragmas - Use all the pragmas and typically useful modules in this progam via one handy oneline.

=cut

use Import::Into;

sub import {
  my $target = caller;

  #Pragmas
  Modern::Perl->import::into($target, '2015');
  warnings->import::into($target);
  strict->import::into($target);
  utf8->import::into($target); #This file and all Strings within are utf8-encoded
  Carp::Always::Color->import::into($target);
  experimental->import::into($target, 'smartmatch', 'signatures');
  English->import::into($target);
  Try::Tiny->import::into($target);

  #External modules
  Data::Dumper->import::into($target);
  Data::Printer->import::into($target);
  Scalar::Util->import::into($target, 'blessed', 'weaken');
  Log::Log4perl->import::into($target);
  List::Util->import::into($target);

  #Local modules
  MMT::Config->import::into($target);
  MMT::Validator->import::into($target);
  MMT::Date->import::into($target);
}

return 1;
