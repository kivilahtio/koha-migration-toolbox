#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use YAML::XS qw/LoadFile/;
$|=1;


my $config = LoadFile('config.yaml');

$ENV{ORACLE_SID} = $config->{sid};
$ENV{ORACLE_HOME} = $config->{oracle_home};
our $host = $config->{host};
our $username = $config->{username};
our $password = $config->{password};
our $sid = $config->{sid};
our $port = $config->{port};


my $dbh = DBI->connect("dbi:Oracle:host=$host;sid=$sid;port=$port;", $username, $password) || die "Could no connect: $DBI::errstr";

my $query = "SELECT patron_address.patron_id,
                    patron_address.address_type,
                    patron_address.address_line1,patron_address.address_line2,
                    patron_address.address_line3,patron_address.address_line4,
                    patron_address.address_line5,patron_address.city,
                    patron_address.state_province,patron_address.zip_postal,
                    patron_address.country
               FROM patron_address";

my $sth=$dbh->prepare($query) || die $dbh->errstr;
$sth->execute() || die $dbh->errstr;

my $i=0;
open my $out,">","patron_address_data.csv" || die "Can't open the output!";

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
