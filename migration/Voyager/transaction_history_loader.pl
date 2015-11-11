#!/usr/bin/perl
#---------------------------------
# Copyright 2010 ByWater Solutions
#
#---------------------------------
#
# -D Ruth Bavousett
#
#---------------------------------

use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;
use Text::CSV;
use C4::Context;
use C4::Items;
$|=1;
my $debug=0;
my $doo_eet=0;

my $infile_name = "";

GetOptions(
    'in=s'            => \$infile_name,
    'debug'           => \$debug,
    'update'          => \$doo_eet,
);

if (($infile_name eq '') ){
  print "Something's missing.\n";
  exit;
}

my $csv = Text::CSV->new();
open my $in,"<$infile_name";
my $i=0;
my $j=0;
my $problem=0;
my $dbh = C4::Context->dbh();
my $sth = $dbh->prepare("INSERT INTO old_issues (borrowernumber, itemnumber, date_due, returndate, renewals, issuedate) VALUES (?, ?, ?, ?, ?, ?)");
my $borr_sth = $dbh->prepare("SELECT borrowernumber FROM borrowers WHERE cardnumber=?");
my $item_sth = $dbh->prepare("SELECT itemnumber,homebranch FROM items WHERE barcode=?");
my $thisborrower;
my $dum = $csv->getline($in);
RECORD:
while (my $line = $csv->getline($in)) {
   my @data = @$line;
   $i++;
   print ".";
   print "\r$i" unless $i % 100;

   my $thisborrowerbar = $data[0];
   
   $borr_sth->execute($thisborrowerbar);
   my $hash=$borr_sth->fetchrow_hashref();
   $thisborrower=$hash->{'borrowernumber'};

   my $thisitembar = $data[2];
   $item_sth->execute($thisitembar);
   $hash=$item_sth->fetchrow_hashref();
   my $thisitem = $hash->{'itemnumber'};
   my $branch = $hash->{'homebranch'};
  
   my $thisdateout = _process_date($data[3]);
   my $thisdatedue = _process_date($data[4]);
   my $thisdatereturn = _process_date($data[5]);

   my $renewals = 0;
   if ($data[6] ne q{}){
      $renewals = $data[6];
   }

   if ($thisborrower && $thisitem){
      $j++;
      $debug and print "B:$thisborrowerbar I:$thisitembar O:$thisdateout D:$thisdatedue DC:$thisdatereturn R:$renewals\n";
      if ($doo_eet){
         $sth->execute($thisborrower,
                       $thisitem,
                       $thisdatedue,
                       $thisdatereturn,
                       $renewals,
                       $thisdateout,);
         C4::Items::ModItem({itemlost         => 0,
                             datelastborrowed => $thisdateout,
                             datelastseen     => $thisdatereturn
                            },undef,$thisitem);
      }
   }
   else{
      print "\nProblem record:\n";
      print "B:$thisborrowerbar I:$thisitembar O:$thisdateout D:$thisdatedue DC:$thisdatereturn R:$renewals\n";
      $problem++;
   }
   last if ($debug && $j>20);
   next;
}

close $in;

print "\n\n$i lines read.\n$j issues loaded.\n$problem problem issues not loaded.\n";
exit;

sub _process_date {
   my $datein = shift;
   return undef if !$datein;
   return undef if $datein eq "";
   return $datein;

}