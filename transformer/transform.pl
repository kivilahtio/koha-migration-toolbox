#!/usr/bin/perl
#---------------------------------
# Copyright 2018 National Library of Finland
#

package MAIN;
#Pragmas
use FindBin qw($Bin);
use lib ("$Bin", "$Bin/../lib", "$Bin/extlib/lib/perl5");
use MMT::Pragmas;
use MMT::MonkeyPatch;

#External modules
use Getopt::OO;
use IPC::Cmd;

#Local modules
my Log::Log4perl $log = Log::Log4perl->get_logger(__PACKAGE__);
use MMT::AutoConfigurer;
use MMT::Builder;
use MMT::Extractor;
use MMT::Loader;
use MMT::TBuilder;
use MMT::Usemarcon;
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


  '--autoconfig' => {
    help => "AutoConfigures translation tables from extracted data sets",
    callback => sub {
      if (MMT::Config->sourceSystemType eq 'Voyager') {
        MMT::AutoConfigurer::configure([
          {

          }
        ]);
      }
      elsif (MMT::Config->sourceSystemType =~ /PrettyLib|PrettyCirc/) {
        MMT::AutoConfigurer::configure([
          {
            description => "This mapping table is used by the module MMT::TranslationTable::Branchcodes, it defines mappings from PrettyLib.Library to Koha's branchcode used in various tables.",
            sourceFile => 'Library.csv',
            destinationFile => 'branchcodes.yaml',
            sourcePrimaryKeyColumn => sub { return $_[0]->{Id} },
            translationTemplate => sub { return substr($_[0]->{Name},0,12) },
          }, {
            description => "This mapping table is used by the module MMT::TranslationTable::LocationId, it defines mappings from location column to Koha's shelving_location",
            sourceFile => 'Location.csv',
            destinationFile => 'location_id.yaml',
            sourcePrimaryKeyColumn => sub { return $_[0]->{Id} },
            translationTemplate => sub { return "branchLoc(,".substr($_[0]->{Location},0,12).")" },
          }, {
            description => "This mapping table is used by the module MMT::TranslationTable::PatronCategorycode, it defines mappings from PrettyLib.Customer.Id_Group to koha.borrowers.categorycode",
            sourceFile => 'Groups.csv',
            destinationFile => 'borrowers.categorycode.yaml',
            sourcePrimaryKeyColumn => sub { return $_[0]->{Id} },
            translationTemplate => sub { return substr($_[0]->{Name},0,12) },
          },
        ]);
      }
      return undef;
    },
  },


  '--biblios' => {
    help => "Transform biblios",
    callback => sub {
      MMT::DeleteList::FlushDeleteList();
      my $confBase = {
        type => 'Biblio',
        outputFile => 'biblios.marcxml.finmarc',
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
            {name => 'BigText', file => 'BigText.csv', keys => ['Id_Title']},
            {name => 'Class', file => 'Class.csv', keys => ['Id']},
            {name => 'ClassCross', file => 'ClassCross.csv', keys => ['Id_Title']},
            {name => 'Location',   file => 'Location.csv', keys => ['Id']},
            {name => 'Subjects', file => 'Subject.csv', keys => ['Id']},
            {name => 'SubjectCross', file => 'SubjectCross.csv', keys => ['Id_Title']},
            {name => 'Publishers', file => 'Publisher.csv', keys => ['Id']},
            {name => 'PublisherCross', file => 'PublisherCross.csv', keys => ['Id_Title']},
            {name => 'Series', file => 'Series.csv', keys => ['Id']},
            {name => 'SeriesCross', file => 'SeriesCross.csv', keys => ['Id_Title']},
            {name => 'TitleExtension', file => 'TitleExtension.csv', keys => ["Id_Title"]},
            {name => 'Items', file => 'Item.csv', keys => ['Id_Title']},
          ],
          translationTables => [
            {name => 'ItemTypes'},
            {name => 'LocationId'},
          ],
        };
      }
      elsif (MMT::Config->sourceSystemType eq 'PrettyCirc') {
        $conf = {
          inputFile => 'Title.csv',
          repositories => [
            {name => 'Titles', file => 'Title.csv', keys => ['Id']},
            {name => 'Documents', file => 'Document.csv', keys => ['Id_Title']},
            {name => 'Authors', file => 'Author.csv', keys => ['Id']},
            {name => 'AuthorCross', file => 'AuthorCross.csv', keys => ['Id_Title']},
            {name => 'CircleStorage', file => 'CircleStorage.csv', keys => ['Id_Title']}, # One title can have many serial holdings entries
            {name => 'Class', file => 'Class.csv', keys => ['Id']},
            {name => 'Class', file => 'Class.csv', keys => ['Id']},
            {name => 'ClassCross', file => 'ClassCross.csv', keys => ['Id_Title']},
            {name => 'Location',   file => 'Location.csv', keys => ['Id']},
            {name => 'Subjects', file => 'Subject.csv', keys => ['Id']},
            {name => 'SubjectCross', file => 'SubjectCross.csv', keys => ['Id_Title']},
            {name => 'Publishers', file => 'Publisher.csv', keys => ['Id']},
            {name => 'PublisherCross', file => 'PublisherCross.csv', keys => ['Id_Title']},
            {name => 'Series', file => 'Series.csv', keys => ['Id']},
            {name => 'SeriesCross', file => 'SeriesCross.csv', keys => ['Id_Title']},
            #{name => 'TitleExtension', file => 'TitleExtension.csv', keys => ["Id_Title", "iMarc", "strSubField"]}, # PrettyCirc is missing this Table
            {name => 'Items', file => 'Item.csv', keys => ['Id_Title']},
          ],
          translationTables => [
            {name => 'ItemTypes'},
            {name => 'LocationId'},
          ],
        };
      }

      build($confBase, $conf);
      MMT::Usemarcon::usemarcon();
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
            {name => 'LoanByItem', file => 'Loan.csv',     keys => ['Id_Item']},
            {name => 'Location',   file => 'Location.csv', keys => ['Id']},
            {name => 'Shelf',      file => 'Shelf.csv',    keys => ['Id']},
            {name => 'Title',      file => 'Title.csv',    keys => ['Id']},
            {name => 'Suppliers',  file => 'Supplier.csv', keys => ['Id']},
          ],
          translationTables => [
            {name => 'LocationId'},
            {name => 'Branchcodes'},
            {name => 'ItemTypes'},
          ],
        };
      }
      elsif (MMT::Config->sourceSystemType eq 'PrettyCirc') {
        $conf = {
          inputFile => 'Item.csv',
          repositories => [
            {name => 'CircleStorage', file => 'CircleStorage.csv', keys => ['Id_Title']}, # One title can have many serial holdings entries
            {name => 'LoanByItem', file => 'Loan.csv',  keys => ['Id_Item']},
            {name => 'Location',   file => 'Location.csv', keys => ['Id']},
            {name => 'Shelf',      file => 'Shelf.csv', keys => ['Id']},
            {name => 'Title',      file => 'Title.csv', keys => ['Id']},
            {name => 'Suppliers',  file => 'Supplier.csv', keys => ['Id']},
          ],
          translationTables => [
            {name => 'LocationId'},
            {name => 'Branchcodes'},
            {name => 'ItemTypes'},
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
          repositories => [
            {name => 'Groups', file => 'Groups.csv',  keys => ['Id']},
          ],
          translationTables => [
            {name => 'Branchcodes'},
            {name => 'PatronCategorycode'},
          ],
        };
      }
      elsif (MMT::Config->sourceSystemType eq 'PrettyCirc') {
        $conf = {
          type =>    'Customer',
          inputFile => 'Customer.csv',
          repositories => [
            {name => 'Groups', file => 'Groups.csv',  keys => ['Id']},
            {name => 'Address', file => 'Address.csv',  keys => ['Id']},
          ],
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
      elsif (MMT::Config->sourceSystemType eq 'PrettyCirc') {
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
      elsif (MMT::Config->sourceSystemType eq 'PrettyCirc') {
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
      my $confBase = {
        outputFile => 'Reserve.migrateme',
      };
      my $conf;

      if (MMT::Config->sourceSystemType eq 'Voyager') {
        $conf = {
          type => 'Reserve',
          inputFile => '29-requests.csv',
          repositories => [
          ],
          translationTables => [
            {name => 'HoldStatuses'},
            {name => 'CallSlipStatuses'},
            {name => 'LocationId'},
          ],
        };
      }
      elsif (MMT::Config->sourceSystemType eq 'PrettyLib') {
        $conf = {
          type => 'Reserve',
          inputFile => 'Reservation.csv',
          translationTables => [
            {name => 'Branchcodes'},
          ],
        };
      }
      elsif (MMT::Config->sourceSystemType eq 'PrettyCirc') {
        $conf = {
          type => 'Reserve',
          inputFile => 'Reservation.csv',
          translationTables => [
            {name => 'Branchcodes'},
          ],
        };
      }

      build($confBase, $conf);
    },
  },


  '--booksellers' => {
    help => 'Transform Suppliers from Pretty extracts to Koha',
    callback => sub {
      my $confBase = {
        outputFile => 'Bookseller.migrateme',
      };
      my $conf;

      if (MMT::Config->sourceSystemType eq 'Voyager') {
        die "--bookseller not supported for Voyager";
      }
      elsif (MMT::Config->sourceSystemType eq 'PrettyLib') {
        $conf = {
          type => 'Supplier',
          inputFile => 'Supplier.csv',
        };
      }
      elsif (MMT::Config->sourceSystemType eq 'PrettyCirc') {
        $conf = {
          type => 'Supplier',
          inputFile => 'Supplier.csv',
        };
      }
      build($confBase, $conf);
    },
  },


  '--serials' => {
    help => 'Transform serials from Voyager extracts to Koha',
    callback => sub {
      my $confBase = {
        outputFile => 'Serial.migrateme',
      };
      my $conf;

      if (MMT::Config->sourceSystemType eq 'Voyager') {
        $conf = {
          type => 'Serial',
          inputFile => '21-ser_issues.csv',
          repositories => [],
          translationTables => [],
        };
      }
      elsif (MMT::Config->sourceSystemType eq 'PrettyCirc') {
        $conf = {
          type => 'Periodical',
          inputFile => 'Periodical.csv',
          repositories => [
            {name => "Items", file => 'Item.csv', keys => ['Id']}, # Translate the biblionumber from the attached items
          ],
          translationTables => [],
        };
      }

      build($confBase, $conf);
    },
  },


  '--subscriptions' => {
    help => 'Transform subscriptions from Voyager extracts to Koha',
    callback => sub {
      my $confBase = {
        type => 'Subscription',
      };
      my $conf;
      if (MMT::Config->sourceSystemType eq 'Voyager') {
        $conf = {
          inputFile => '20-subscriptions.csv',
          repositories => [
            {name => "SubscriptionLocation", file => '20a-subscription_locations.csv', keys => ['component_id']},
          ],
          translationTables => [
            {name => 'LocationId'},
          ],
        };
        build($confBase, $conf);
      }
      elsif (MMT::Config->sourceSystemType eq 'PrettyCirc') {
        $conf = {
          inputFile => 'Periodical.csv',
          repositories => [
            {name => "Items", file => 'Item.csv', keys => ['Id']}, # Translate the biblionumber from the attached items
            {name => "CircleNewOrder", file => 'CircleNewOrder.csv', keys => ['Id_Item']}, # Subscription information
          ],
          translationTables => [
            {name => 'LocationId'},
            {name => 'Branchcodes'},
          ],
        };
        require MMT::PrettyCirc2Koha::Subscription;
        @{$confBase}{keys %{$conf}} = values %{$conf}; #Merge HASH slices
        my MMT::TBuilder $builder = MMT::TBuilder->new($confBase);
        MMT::PrettyCirc2Koha::Subscription::analyzePeriodicals($builder);
        MMT::PrettyCirc2Koha::Subscription::createFillerSubscriptions($builder);
        $builder->close();
        return 0;
      }
    },
  },


  '--routinglists' => {
    help => 'Transform Circle from PrettyCirc extracts to Koha.subscriptionroutinglist',
    callback => sub {
      my $confBase = {
        outputFile => 'Subscriptionroutinglist.migrateme',
      };
      my $conf;

      if (MMT::Config->sourceSystemType eq 'PrettyCirc') {
        $conf = {
          type => 'Circle',
          inputFile => 'Circle.csv',
          repositories => [
            {name => "circleList", file => 'CircleList.csv', keys => ['Id_Item']},
          ],
          translationTables => [],
        };
      }

      build($confBase, $conf);
    },
  },


  '--history' => {
    help => 'Transform Transact history from Pretty* extracts to Koha.statistics',
    callback => sub {
      my $confBase = {
        outputFile => 'Statistics.migrateme',
      };
      my $conf;

      if (MMT::Config->sourceSystemType eq 'PrettyLib') { # PrettyCirc has the same table but it is empty.
        $conf = {
          type => 'Transact',
          inputFile => 'Transact.csv',
          repositories => [
            {name => "Items",     file => 'Item.csv',     keys => ['Id']},
            {name => "Customers", file => 'Customer.csv', keys => ['Id']},
          ],
          translationTables => [
            {name => 'Branchcodes'},
          ],
        };
        build($confBase, $conf);
      }
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
