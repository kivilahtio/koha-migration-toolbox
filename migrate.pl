#!/usr/bin/perl
#---------------------------------
# Copyright 2018 National Library of Finland
#

use 5.22.1;

package MAIN;
#Pragmas
use lib qw(lib extlib/lib/perl5);
use experimental 'smartmatch', 'signatures';
use Carp::Always::Color;

#External modules
use Getopt::OO;

#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);
use MMT::Validator;
use MMT::Koha::Patron::Builder;
use MMT::Koha::Issue::Builder;

my Getopt::OO $opts = Getopt::OO->new(\@ARGV,
  '--help' => {
    help => 'Show this friendly help',
    callback => sub {print $_[0]->Help(); exit 0;},
  },
  '--patrons' => {
    help => 'Transform patrons from Voyager extracts to Koha',
  },
  '--issues' => {
    help => 'Transform issues from Voyager extracts to Koha',
  },
);

$log->debug("Starting $0 using config '".MMT::Validator::dumpObject($MMT::Config::config)."'");

if ($opts->Values('--patrons')) {
  my MMT::Koha::Patron::Builder $builder = MMT::Koha::Patron::Builder->new();
  $builder->build();
}

if ($opts->Values('--issues')) {
  my MMT::Koha::Issue::Builder $builder = MMT::Koha::Issue::Builder->new();
  $builder->build();
}

