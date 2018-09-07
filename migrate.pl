#!/usr/bin/perl
#---------------------------------
# Copyright 2018 National Library of Finland
#

package MAIN;
#Pragmas
use lib qw(lib extlib/lib/perl5);
use MMT::Pragmas;
use MMT::MonkeyPatch;

#External modules
use Getopt::OO;
use IPC::Cmd;

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);
use MMT::Extractor;
use MMT::Loader;
use MMT::Builder;
use MMT::Koha::Biblio;


$log->debug("Starting $0 using config '".MMT::Validator::dumpObject($MMT::Config::config)."'");


my Getopt::OO $opts = Getopt::OO->new(\@ARGV,
  '--help' => {
    help => 'Show this friendly help',
    callback => sub {
      print "\n";
      print $_[0]->Help();
      print "
ENVIRONMENT:
MMT_HOME: ".($ENV{MMT_HOME} || '')."
    Configuration and working space for the specific ETL pipeline.

";
      exit 0;
    },
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
          {name => 'ItemNotes',      file => '02a-item_notes.csv',            keys => ['item_id']},
          {name => 'ItemStats',      file => '02b-item_stats.csv',            keys => ['item_id']},
          {name => 'ItemStatuses',   file => '02-item_status.csv',            keys => ['item_id']},
          {name => "LastBorrowDate", file => '02-items_last_borrow_date.csv', keys => ['item_id']},
        ],
        translationTables => [
          {name => 'LocationId'},
          {name => 'ItemNoteTypes'},
          {name => 'ItemTypes'},
          {name => 'ItemStatistics'},
          {name => 'ItemStatus'},
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
          {name => "addresses",             file => '05-patron_addresses.csv'     , keys => ['patron_id']},
          {name => "Barcodes",              file => '06-patron_barcode_groups.csv', keys => ['patron_id']},
          {name => "notes",                 file => '09-patron_notes.csv'         , keys => ['patron_id']},
          {name => "phones",                file => '10-patron_phones.csv'        , keys => ['patron_id']},
          {name => "statisticalCategories", file => '11-patron_stat_codes.csv'    , keys => ['patron_id']},
        ],
        translationTables => [
          {name => 'PatronCategorycode'},
          {name => 'Branchcodes'},
          {name => 'LocationId'},
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
          {name => "LastRenewDate",             file => '12a-current_circ_last_renew_date.csv', keys => ['circ_transaction_id']},
        ],
        translationTables => [
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
        repositories => [
          {name => "SubscriptionLocation", file => '20a-subscription_locations.csv', keys => ['component_id']},
        ],
        translationTables => [
          {name => 'LocationId'},
        ],
      });
      $builder->build();
    },
  },


  '--branchtransfers' => {
    help => 'Transform scattered data from Voyager extracts to Koha branchtransfers',
    callback => sub {
      my MMT::Builder $builder = MMT::Builder->new({
        type => 'Branchtransfer',
        inputFile => '03-transfers.csv',
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
