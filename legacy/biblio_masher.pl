#!/usr/bin/perl
#---------------------------------
# Copyright 2010 ByWater Solutions
#
#---------------------------------
#
# -D Ruth Bavousett
#
#---------------------------------
#
# ./biblio_masher.pl --in=split-00000009 --items=fixed-item-data.csv --out=records-to-koha-09.mrc 
# --lastdate=last_checkout_data.csv --branch_map=branch-mapping.csv --itype_map=item-type-mapping.csv 
# --location_map=location-mapping.csv --debug > split-09.log
#
#-----------
use strict;
use warnings;
use Carp;
use Data::Dumper;
use English qw( -no_match_vars );
use autodie qw(open close);
use Getopt::Long;
use IO::File;
use Readonly;
use Smart::Comments;
use Text::CSV_XS;
use Text::CSV::Simple;
use MARC::Batch;
use MARC::Charset;
use MARC::Field;
use MARC::Record;
use MARC::File::XML;
use XML::Simple;
use version; our $VERSION = qv('1.0.0');

$OUTPUT_AUTOFLUSH = 1;
Readonly my $FIELD_SEPARATOR => q{,};
Readonly my $NULL_STRING     => q{};
my $debug = 0;

my $infile_name  = q{};
my $itemsfiles = q{};
my $outfile_name = q{};
my $branch = q{};
my $lastdatefile = q{};
my %last_seen_map;
my $branch_map_name = "";
my %branch_map;
my $itype_map_name = "";
my %itype_map;
my $location_map_name = "";
my %location_map;
my $item_triplet_map_name = "";
my %item_triplet_map;
my $drop_noitem=0;
my $use_temps=0;
my $drop_types_str = q{};
my %drop_types;
my $repl_price_override = q{};
my $dump_copynums = 0;
my $new942 = 0;


my $csv = Text::CSV_XS->new({binary => 1});
GetOptions(
    # MARC-file
    'in=s'    => \$infile_name,
    #---------------------------
    # items, eg. item-data.csv or 02-items.csv from export scripts. CSV with following columns:
    # bib_id, add_date, barcode, perm_item_type_code, perm_location_code, enumeration chronology,
    # historical_charges, call_no call_no_type, price, copy_number pieces, item_note
    # Items data should be cleaned first using ./item_data_fixer.pl --in=02-items.csv --out=fixed-items.csv
    # to remove newlines
    'items=s' => \$itemsfiles,
    #----------------------------------
    # Output file, to be loaded to Koha
    'out=s'   => \$outfile_name,
    #----------------------------------
    # last_checkout_data.csv or 13-last_borrow_dates.csv. CSV with following columns:
    # barcode, charge_date
    'lastdate=s'  => \$lastdatefile,
    #----------------------------------
    # for dropping items, default 0 eg. no drop.
    'drop_noitem' => \$drop_noitem,
    #----------------------------------
    # for dropping item types; strings separated with comma.
    'drop_types=s' => \$drop_types_str,
    #----------------------------------
    # CSV with following columns:
    # Voyager location code, Koha branch_code
    'branch_map=s' => \$branch_map_name,
    #-----------------------------------
    # CSV with following columns:
    # old_item_type_code, new_item_type_code
    'itype_map=s'       => \$itype_map_name,
    #-----------------------------------
    # Location code and location name for display. CSV with following columns:
    # location_code, location_name
    'location_map=s'       => \$location_map_name,
    #------------------------------------
    # Links together Koha item type code, location code and collection code. CSV with following columns:
    # item_type, location_code, collection_code. Seems to be useful when using lots of item type related
    # location and collection codes.
    'item_trip_map=s'   => \$item_triplet_map_name,
    #-------------------------------------
    # Whether to dump copy numbers from items, default 0 eg. do not drop numbers.
    'dump_copynums=s'   => \$dump_copynums,
    #-------------------------------------
    # Fixed replacement price for items. By default, purchase price is used as replacement price.
    'repl_price=s'      => \$repl_price_override,
    #-------------------------------------
    # Use temporary locations. By default, do not use.
    'use_temps'         => \$use_temps,
    #-------------------------------------
    # Whether to show debug information
    'debug'   => \$debug,
);

if ( ( $infile_name eq $NULL_STRING ) 
     || ( $outfile_name eq $NULL_STRING )
     || ( $itemsfiles eq $NULL_STRING )
     || ( $lastdatefile eq $NULL_STRING)) {
    print "Something's missing.\n";
    exit;
}

if ($drop_types_str){
    foreach my $type (split /,/,$drop_types_str){
        $drop_types{$type} = 1;
    }
}

if ($lastdatefile){
    my $csv = Text::CSV_XS->new();
    open my $mapfile,"<$lastdatefile";
    while (my $row = $csv->getline($mapfile)){
        my @data = @$row;
        $last_seen_map{uc($data[0])} = _process_date($data[1]);
    }
    close $mapfile;
}

if ($branch_map_name){
    my $csv = Text::CSV_XS->new();
    open my $mapfile,'<:utf8',$branch_map_name;
    while (my $row = $csv->getline($mapfile)){
        my @data = @$row;
        $branch_map{uc($data[0])} = $data[1];
    }
    close $mapfile;
}

if ($itype_map_name){
    my $csv = Text::CSV_XS->new();
    open my $mapfile,'<:utf8',$itype_map_name;
    while (my $row = $csv->getline($mapfile)){
        my @data = @$row;
        $itype_map{uc($data[0])} = $data[1];
    }
    close $mapfile;
}

if ($location_map_name){
    my $csv = Text::CSV_XS->new();
    open my $mapfile,'<:utf8',$location_map_name;
    while (my $row = $csv->getline($mapfile)){
        my @data = @$row;
        $location_map{$data[0]} = $data[1];
    }
    close $mapfile;
}

if ($item_triplet_map_name){
    my $csv = Text::CSV_XS->new();
    open my $mapfile,"<$item_triplet_map_name";
    while (my $row = $csv->getline($mapfile)){
        my @data = @$row;
        $item_triplet_map{uc($data[0])} = $data[1].'~'.$data[2].'~'.$data[3];
    }
    close $mapfile;
}
$debug and print Dumper(%item_triplet_map);

my $read        = 0;
my $items_found = 0;
my $written     = 0;
my %locations;
my %itypes;
my %branches;
my %collcodes;

## no critic (InputOutput::RequireBriefOpen)
my $infl = IO::File->new($infile_name);
my $batch = MARC::Batch->new('USMARC',$infl);
$batch->warnings_off();
$batch->strict_off();
my $iggy = MARC::Charset::ignore_errors(1);
my $setting = MARC::Charset::assume_encoding('marc8');
open my $out,  '>:utf8', $outfile_name;
# open(my $out, "<:encoding(UTF-8)", $outfile_name);
## use critic
my $last_record;
RECORD:
while ( ) {
    $read++;
    ($read % 100) ? print '.' : print "\r$read";
    #last RECORD if ($debug and $read > 20);
    my $record;
    eval {$record=$batch->next();};

    if ($@){
        print "Bogusness skipped\n";
        next RECORD;
    }
    last RECORD unless ($record);

    #next RECORD if ($debug and $read < 58300);
    #$debug and print $record->as_xml();

    my $id_tag = $record->field('001');
    if (!$id_tag){
       print "Bogus bib skipped\n";
       print "REC NUM $read\nRECORD BEFORE:\n";
       print $last_record->as_xml();
       exit;
       #next RECORD;
    }
    $last_record=$record->clone();
    my $biblio_id = $id_tag->data();
    #$debug and print $biblio_id;
#print "the biblio_id is: $biblio_id\n";

    foreach my $dumpfield($record->field('942')){
        $record->delete_field($dumpfield);
    }
    foreach my $dumpfield($record->field('952')){
        $record->delete_field($dumpfield);
    }
    foreach my $dumpfield($record->field('995')){
        $record->delete_field($dumpfield);
    }
    foreach my $dumpfield($record->field('999')){
        $record->delete_field($dumpfield);
    }
    foreach my $dumpfield($record->field('852')){
        $record->delete_field($dumpfield);
    }
    my @matches = qx(sift "$biblio_id," --no-color $itemsfiles | sift "^$biblio_id");

    next RECORD if ($drop_noitem && scalar(@matches) == 0);

    my $itemcount=0;
$new942=0;
MATCH:
    foreach my $match (@matches){
#print "$biblio_id\n";
#print "$match\n";
        $itemcount++;
        $csv->parse($match);

        my @columns = $csv->fields();
#        if (scalar(@columns) != 16){
#           print "\n$biblio_id\n$match\n";
#           next MATCH;
#           }

        my $barcode = $columns[2];
#        if ($barcode eq q{} || $barcode eq $NULL_STRING ){
        if ($barcode eq $NULL_STRING ){
           $barcode = sprintf "%d-%04d",$read,$itemcount;
        }

        my $date_last_borrowed = $last_seen_map{$barcode} || q{};

        my $itype = uc $columns[3] || 'UNKNOWN';
        if (exists $itype_map{$itype}){
            $itype = $itype_map{$itype};
        }
        next MATCH if $drop_types{$itype};

#try this loop for one 942 field.
        if ( $new942 == 0 ) {
        my $tag942=MARC::Field->new('942',' ',' ', 'c' => $itype);
        $record->insert_grouped_field($tag942);
        $new942++;
        }
#end loop here

        my $branchcode = uc($columns[4]);
        if (exists $branch_map{$branchcode}){
            $branchcode = $branch_map{$branchcode};
        } else {
            $branchcode = 'UNKNOWN';
        }

        my $location = uc($columns[4]);
        # 
        # if (exists $location_map{$location}){
        #    $location = $location_map{$location};
        # } else {
        #     $location = "UNKNOWN";
        # }
        # $debug and print "$location\n";

        my $collcode = uc($columns[4]);
        $debug and print "$collcode\n";
        

        my $enumchron = q{};
        if ($columns[5] ne $NULL_STRING){
           $enumchron .= $columns[6];
        }
        if ($columns[6] ne $NULL_STRING){
           $enumchron .= ' '.$columns[7];
           $enumchron =~ s/^ //;
        }

        $branches{$branchcode}++;
        $itypes{$itype}++;
        if ($location ne $NULL_STRING){
            $locations{$location}++;
        }
        if ($collcode ne $NULL_STRING){
            $collcodes{$collcode}++;
        }

        my $field = MARC::Field->new( '952',' ',' ',
            'a' => $branchcode,
            'b' => $branchcode,
            'p' => $barcode,
            'y' => $itype,
            'o' => $columns[8],
            'd' => _process_date($columns[1]),
        );

        if ($date_last_borrowed ne $NULL_STRING){
            $field->add_subfields( 's' => $date_last_borrowed );
        }

        # if ($location ne $NULL_STRING){
        #    $field->add_subfields( 'c' => $location );
        #}

        if ($collcode ne $NULL_STRING){
            $field->add_subfields( '8' => $collcode );
        }

        if ($enumchron ne $NULL_STRING){
            $field->add_subfields( 'h' => $enumchron );
        }

#        if ($columns[8] ne $NULL_STRING){
#            $field->add_subfields( 'l' => $columns[8] );
#        }


        if ($columns[12] ne $NULL_STRING and 
            (!$dump_copynums || scalar(@matches) > $dump_copynums)){
            $field->add_subfields( 't' => $columns[12] );
        }

        if ($columns[13] ne $NULL_STRING){
            $field->add_subfields( '3' => $columns[13] );
        }
#change column[14] from t to x for CIN- 
        if ($columns[14] ne $NULL_STRING){
            $field->add_subfields( 'x' => $columns[14] );
        }

#        $record->append_fields($field);
$record->insert_grouped_field($field);
        $items_found++;


    }
    eval{ print {$out} $record->as_usmarc();} ;
    if ($@){
      print "\nError in biblio $biblio_id\n";
    }
    else{
      $written++;
    }
}
close $infl;
close $out;

print "$read lines read.\n$written biblios written, with $items_found embedded items.\n";

open $out,">biblio_codes.sql";

print {$out} "# Branches \n";
print "\nBRANCH COUNT:\n";
foreach my $key (sort keys %branches){
   print {$out} "INSERT INTO branches (branchcode,branchname) VALUES ('$key','$key');\n";
   print "$key:  $branches{$key}\n";
}

print {$out} "# I-Types \n";
print "\nITEM TYPE COUNTS:\n";
foreach my $key (sort keys %itypes){
   print {$out} "INSERT INTO itemtypes (itemtype,description) VALUES ('$key','$key');\n";
   print "$key:  $itypes{$key}\n";
}

print {$out} "# Locations \n";
print "\nLOCATION CODE COUNTS:\n";
foreach my $key (sort keys %locations){
   print {$out} "INSERT INTO authorised_values (category,authorised_value,lib) VALUES ('LOC','$key','$key');\n";
   print "$key:  $locations{$key}\n";
}

print {$out} "# Collection Codes \n";
print "\nCOLLECTION CODE COUNTS:\n";
foreach my $key (sort keys %collcodes){
   print {$out} "INSERT INTO authorised_values (category,authorised_value,lib) VALUES ('CCODE','$key','$key');\n";
   print "$key:  $collcodes{$key}\n";
}

exit;

sub _process_date {
   my $datein=shift;
   return undef if $datein eq $NULL_STRING;
   my %months =( 
                  JAN => 1, FEB => 2,  MAR => 3,  APR => 4,
                  MAY => 5, JUN => 6,  JUL => 7,  AUG => 8,
                  SEP => 9, OCT => 10, NOV => 11, DEC => 12
               );
   my ($day,$monthstr,$year) = split /\-/, $datein;
   if ($year < 40){
       $year +=2000;
   }
   else{
       $year +=1900;
   }
   return sprintf "%4d-%02d-%02d",$year,$months{$monthstr},$day;
}

