#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use YAML::XS qw/LoadFile/;
$|=1;

$ENV{ORACLE_SID} = $config->{sid};
$ENV{ORACLE_HOME} = $config->{oracle_home};
our $host = $config->{host};
our $username = $config->{username};
our $password = $config->{password};
our $sid = $config->{sid};
our $port = $config->{port};

my $dbh = DBI->connect("dbi:Oracle:host=$host;sid=$sid;port=$port;", $username, $password) || die "Could no connect: $DBI::errstr";
my $query = "SELECT patron_barcode.patron_barcode,patron.institution_id,fine_fee.patron_id,
                    item_barcode.item_barcode,fine_fee.fine_fee_type,
                    fine_fee.create_date,fine_fee.fine_fee_balance,
                    fine_fee.fine_fee_note
               FROM fine_fee
               JOIN patron ON (fine_fee.patron_id=patron.patron_id)
          LEFT JOIN patron_barcode ON (fine_fee.patron_id=patron_barcode.patron_id)
          LEFT JOIN item_barcode ON (fine_fee.item_id=item_barcode.item_id)
              WHERE patron_barcode.barcode_status = 1 and patron_barcode.patron_barcode is not null
                AND item_barcode.barcode_status = 1
                AND fine_fee.fine_fee_balance != 0
                AND fine_fee.fine_fee_type in ('2','3')";

my $sth=$dbh->prepare($query) || die $dbh->errstr;
$sth->execute() || die $dbh->errstr;

my $i=0;
open my $out,">","fine_data.csv" || die "Can't open the output!";

while (my @line = $sth->fetchrow_array()){
   $i++;
   print ".";
   print "\r$i" unless ($i % 100);
   for my $k (0..scalar(@line)-1){
      if ($line[$k]){
         $line[$k] =~ s/"/'/g;
         if ($line[$k] =~ /,/){
            print $out '"'.$line[$k].'"';
         }
         else{
            print $out $line[$k];
         }
      }
      print $out ',';
   }
   print $out "\n";
}   

close $out;
print "\n\n$i patrons exported\n";