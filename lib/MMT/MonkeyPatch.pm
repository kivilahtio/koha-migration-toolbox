package MMT::MonkeyPatch;

=head1 NAME

MMT::MonkeyWrench - Do some very stupid things with Perl

=cut

## Data::Dumper::qquote nor the XS-version of Data::Dumper can serialize utf8 properly. Overload the core module to skip it's heuristics and just dump as is.
## https://www.perlmonks.org/?node_id=759457
{
  no warnings 'redefine';
  package Data::Dumper;
  sub qquote {
    local($_) = shift;
    s/([\\\"\@\$])/\\$1/g;
    s/([\a\b\t\n\f\r\e])/\\$1/g;

    return qq("$_");
  }

}

return 1;