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
use IPC::Cmd;

#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);
use MMT::Validator;
use MMT::Extractor;
use MMT::Loader;
use MMT::Builder;
use MMT::Koha::Biblio;


$log->debug("Starting $0 using config '".MMT::Validator::dumpObject($MMT::Config::config)."'");


my Getopt::OO $opts = Getopt::OO->new(\@ARGV,
  '--help' => {
    help => 'Show this friendly help',
    callback => sub {print $_[0]->Help(); exit 0;},
  },


  '--extract' => {
    help => "Runs the extract-phase using the script configured in 'exportPipelineScript'",
    callback => sub {MMT::Extractor::extract()},
  },


  '--biblios' => {
    help => "Transform biblios using ./usemarcon/rules-*/rules.ini",
    callback => sub {MMT::Koha::Biblio::transform()},
  },


  '--items' => {
    help => 'Transform items from Voyager extracts to Koha',
    callback => sub {
      my MMT::Builder $builder = MMT::Builder->new({
        type => 'Item',
        inputFile => '02-items.csv',
        repositories => [
          {name => 'ItemStats', file => '18-item_stats.csv', keys => ['item_id']},
          {name => 'ItemStatuses', file => '02-item_status.csv', keys => ['item_id']},
        ],
        translationTables => [
          {name => 'Branchcodes'},
          {name => 'LocationId'},
          {name => 'ItemTypes'},
          {name => 'ItemNoteTypes'},
        ],
      });
      $builder->build();
    },
  },


  '--patrons' => {
    help => 'Transform patrons from Voyager extracts to Koha',
    callback => sub {
      my MMT::Builder $builder = MMT::Builder->new({
        type => 'Patron',
        inputFile => '07-patron_names_dates.csv',
        repositories => [
          {name => "addresses",             file => '05-patron_addresses.csv'   , keys => ['patron_id']},
          {name => "groups",                file => '06-patron_groups.csv'      , keys => ['patron_id']},
          {name => "groups_nulls",          file => '08-patron_groups_nulls.csv', keys => ['patron_id']},
          {name => "notes",                 file => '09-patron_notes.csv'       , keys => ['patron_id']},
          {name => "phones",                file => '10-patron_phones.csv'      , keys => ['patron_id']},
          {name => "statisticalCategories", file => '11-patron_stat_codes.csv'  , keys => ['patron_id']},
        ],
        translationTables => [
          {name => 'PatronCategorycode'},
          {name => 'Branchcodes'},
          {name => 'NoteType'},
          {name => 'PatronStatistics'},
        ],
      });
      $builder->build();
    },
  },


  '--issues' => {
    help => 'Transform issues from Voyager extracts to Koha',
    callback => sub {
      my MMT::Builder $builder = MMT::Builder->new({
        type => 'Issue',
        inputFile => '12-current_circ.csv',
        repositories => [
          {name => "LastBorrowDates", file => "13-last_borrow_dates.csv", keys => ['barcode']},
        ],
        translationTables => [
          {name => 'Branchcodes'},
          {name => 'LocationId'},
        ],
      });
      $builder->build();
    },
  },


  '--fines' => {
    help => 'Transform fines from Voyager extracts to Koha',
    callback => sub {
      my MMT::Builder $builder = MMT::Builder->new({
        type => 'Fine',
        inputFile => '14-fines.csv',
        repositories => [
        ],
        translationTables => [
          {name => 'FineTypes'},
        ],
      });
      $builder->build();
    },
  },


  '--reserves' => {
    help => 'Transform reserves from Voyager extracts to Koha',
    callback => sub {
      my MMT::Builder $builder = MMT::Builder->new({
        type => 'Reserve',
        inputFile => '29-requests.csv',
        repositories => [
        ],
        translationTables => [
          {name => 'HoldStatuses'},
          {name => 'LocationId'},
        ],
      });
      $builder->build();
    },
  },


  '--serials' => {
    help => 'Transform serials from Voyager extracts to Koha',
    callback => sub {
      my MMT::Builder $builder = MMT::Builder->new({
        type => 'Serial',
        inputFile => '21-ser_issues.csv',
        repositories => [],
        translationTables => [],
      });
      $builder->build();
    },
  },


  '--subscriptions' => {
    help => 'Transform subscriptions from Voyager extracts to Koha',
    callback => sub {
      my MMT::Builder $builder = MMT::Builder->new({
        type => 'Subscription',
        inputFile => '20-subscriptions.csv',
        repositories => [],
        translationTables => [
          {name => 'LocationId'},
        ],
      });
      $builder->build();
    },
  },


  '--load' => {
    help => "Runs the load-phase using the script configured in 'importPipelineScript'",
    callback => sub {MMT::Loader::load()},
  },
);
