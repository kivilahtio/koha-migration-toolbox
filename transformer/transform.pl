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
my Log::Log4perl $log = Log::Log4perl->get_logger(__PACKAGE__);
use MMT::Extractor;
use MMT::Loader;
use MMT::Builder;
use MMT::TBuilder;
use MMT::Voyager2Koha::Biblio;


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
    help => "Transform biblios",
    #callback => sub {MMT::Voyager2Koha::Biblio::usemarcon()},
    callback => sub {
      my $confBase = {
        type => 'Biblio',
        outputFile => 'biblios.marcxml',
      };
      my $conf;

      if (MMT::Config->sourceSystemType eq 'Voyager') {
        $conf = {
          inputFile => 'biblios.marcxml',
          repositories => [
            {name => 'SuppressInOpacMap', file => '00-suppress_in_opac_map.csv',       keys => ['bib_id', 'mfhd_id', 'location_id']},
            {name => 'BibLinkRelationsBySource', file => '00b-bib_link_relations.csv', keys => ['source_bibid']}, # Load the repo by the parent biblionumber, so we adjust child keys to target the parent the Koha-way
            {name => 'BibLinkRelationsByDest',   file => '00b-bib_link_relations.csv', keys => ['dest_bibid']}, # Some link types are only indexed from parent to child. The link MARC Fields are typically in the child. Have a reverse lookup cache for that.
            {name => 'BoundBibParent',    file => '00c-bound_bibs-bib_to_parent.csv',  keys => ['bound_bib_id']},
          ],
          translationTables => [
            {name => 'BibLinkTypes'},
          ],
        };
      }
      elsif (MMT::Config->sourceSystemType eq 'PrettyLib') {
        $conf = {
          inputFile => 'Title.csv',
          repositories => [
            {name => 'Titles', file => 'Title.csv', keys => ['Id']},
            {name => 'Documents', file => 'Document.csv', keys => ['Id_Title']},
            {name => 'Authors', file => 'Author.csv', keys => ['Id']},
            {name => 'AuthorCross', file => 'AuthorCross.csv', keys => ['Id_Title']},
            {name => 'Subjects', file => 'Subject.csv', keys => ['Id']},
            {name => 'SubjectCross', file => 'SubjectCross.csv', keys => ['Id_Title']},
            {name => 'Publishers', file => 'Publisher.csv', keys => ['Id']},
            {name => 'PublisherCross', file => 'PublisherCross.csv', keys => ['Id_Title']},
            {name => 'Series', file => 'Series.csv', keys => ['Id']},
            {name => 'SeriesCross', file => 'SeriesCross.csv', keys => ['Id_Title']},
          ],
        };
      }

      build($confBase, $conf);
    },
  },


  '--holdings' => {
    help => "Transform holdings",
    callback => sub {
      my $builder = MMT::TBuilder->new({
        type => 'Holding',
        inputFile => 'holdings.marcxml',
        outputFile => 'holdings.marcxml',
        repositories => [
          {name => 'BibSubFrequency',   file => '00-bib_sub_frequency.csv',    keys => ['bib_id']}, #This is actually the newest subscription/component's publication frequency.
          {name => 'BibText',           file => '00-bib_text.csv',             keys => ['bib_id']},
          {name => 'MFHDMaster',        file => '00-mfhd_master.csv',          keys => ['mfhd_id']},
          {name => 'SuppressInOpacMap', file => '00-suppress_in_opac_map.csv', keys => ['bib_id', 'mfhd_id', 'location_id']},
          {name => 'BoundBibParent',    file => '00c-bound_bibs-bib_to_parent.csv', keys => ['bound_bib_id']},
        ],
        translationTables => [
          {name => 'LocationId'},
        ],
      });
      $builder->build();
    },
  },


  '--items' => {
    help => 'Transform items from Voyager extracts to Koha',
    callback => sub {
      my $confBase = {
        type => 'Item',
      };
      my $conf;

      if (MMT::Config->sourceSystemType eq 'Voyager') {
        $conf = {
          inputFile => '02-items.csv',
          repositories => [
            {name => 'BibSubFrequency',file => '00-bib_sub_frequency.csv',      keys => ['bib_id']}, #This is actually the newest subscription/component's publication frequency.
            {name => 'MFHDMaster',     file => '00-mfhd_master.csv',            keys => ['mfhd_id']},
            {name => 'ItemNotes',      file => '02a-item_notes.csv',            keys => ['item_id']},
            {name => 'ItemStats',      file => '02b-item_stats.csv',            keys => ['item_id']},
            {name => 'ItemStatuses',   file => '02-item_status.csv',            keys => ['item_id']},
            {name => "LastBorrowDate", file => '02-items_last_borrow_date.csv', keys => ['item_id']},
            {name => 'BibText',        file => '00-bib_text.csv',               keys => ['bib_id']},
            {name => 'BoundBibParent', file => '00c-bound_bibs-bib_to_parent.csv', keys => ['bound_bib_id']},
          ],
          translationTables => [
            {name => 'LocationId'},
            {name => 'ItemNoteTypes'},
            {name => 'ItemTypes'},
            {name => 'ItemStatistics'},
            {name => 'ItemStatus'},
          ],
        };
      }
      elsif (MMT::Config->sourceSystemType eq 'PrettyLib') {
        $conf = {
          inputFile => 'Item.csv',
          repositories => [
            {name => 'LoanByItem', file => 'Loan.csv',  keys => ['Id_Item']},
            {name => 'Shelf',      file => 'Shelf.csv', keys => ['Id']},
          ],
          translationTables => [
            {name => 'LocationId'},
            {name => 'Branchcodes'},
          ],
        };
      }
      build($confBase, $conf);
    },
  },


  '--patrons' => {
    help => 'Transform patrons from Voyager extracts to Koha',
    callback => sub {
      my $confBase = {
        outputFile => 'Borrower.migrateme',
      };
      my $conf;

      if (MMT::Config->sourceSystemType eq 'Voyager') {
        $conf = {
          type =>    'Patron',
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
        };
      }
      elsif (MMT::Config->sourceSystemType eq 'PrettyLib') {
        $conf = {
          type =>    'Customer',
          inputFile => 'Customer.csv',
          repositories => [],
          translationTables => [
            {name => 'Branchcodes'},
            {name => 'PatronCategorycode'},
          ],
        };
      }
      build($confBase, $conf);
    },
  },


  '--issues' => {
    help => 'Transform issues from Voyager extracts to Koha',
    callback => sub {
      my $confBase = {
        outputFile => 'Issue.migrateme',
      };
      my $conf;

      if (MMT::Config->sourceSystemType eq 'Voyager') {
        $conf = {
          type => 'Issue',
          inputFile => '12-current_circ.csv',
          repositories => [
            {name => "LastRenewDate", file => '12a-current_circ_last_renew_date.csv', keys => ['circ_transaction_id']},
          ],
          translationTables => [
            {name => 'LocationId'},
          ],
        };
      }
      elsif (MMT::Config->sourceSystemType eq 'PrettyLib') {
        $conf = {
          type => 'Loan',
          inputFile => 'Loan.csv',
          translationTables => [
            {name => 'Branchcodes'},
          ],
        };
      }
      build($confBase, $conf);
    },
  },


  '--fines' => {
    help => 'Transform fines from Voyager extracts to Koha',
    callback => sub {
      my $confBase = {
        outputFile => 'Fine.migrateme',
      };
      my $conf;

      if (MMT::Config->sourceSystemType eq 'Voyager') {
        $conf = {
          type => 'Fine',
          inputFile => '14-fines.csv',
          repositories => [
          ],
          translationTables => [
            {name => 'FineTypes'},
          ],
        };
      }
      elsif (MMT::Config->sourceSystemType eq 'PrettyLib') {
        $conf = {
          type => 'Fee',
          inputFile => 'Fee.csv',
        };
      }
      build($confBase, $conf);
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
          {name => 'CallSlipStatuses'},
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

sub build($confBase, $conf) {
  @{$confBase}{keys %{$conf}} = values %{$conf}; #Merge HASH slices
  my MMT::TBuilder $builder = MMT::TBuilder->new($confBase);
  $builder->build();
}