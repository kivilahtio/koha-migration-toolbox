package Bulk::Item;

use Modern::Perl;

use C4::Context;
use C4::ClassSource;

use DateTime;
my $nowISO = DateTime->now()->iso8601();

my $getItemSth;
sub getItem {
  my ($barcode) = @_;
  my $dbh = C4::Context->dbh();
  unless($getItemSth) {
    $getItemSth = $dbh->prepare("SELECT * FROM items WHERE barcode = ?");
  }
  $getItemSth->execute($barcode) or die $getItemSth->errstr();
  my $rs = $getItemSth->fetchrow_hashref();
  return $rs;
}
my $getItemInSth;
sub getItemIn {
  my ($itemnumber) = @_;
  my $dbh = C4::Context->dbh();
  unless($getItemInSth) {
    $getItemInSth = $dbh->prepare("SELECT * FROM items WHERE itemnumber = ?");
  }
  $getItemInSth->execute($itemnumber) or die $getItemInSth->errstr();
  my $rs = $getItemInSth->fetchrow_hashref();
  return $rs;
}

sub set_cn_sort {
  my ($item) = @_;
  if ($item->{itemcallnumber} or $item->{cn_source}) {
    my $cn_sort = C4::ClassSource::GetClassSort($item->{cn_source}, $item->{itemcallnumber}, "");
    $item->{cn_sort} = $cn_sort;
  }
}

my $addItemSth;
sub _koha_new_item {
  my ( $item, $barcode ) = @_;
  my $dbh=C4::Context->dbh;  
  my $error;
  $item->{permanent_location} //= $item->{location};
  unless($addItemSth) {
    my $query =
           "INSERT INTO items SET
            itemnumber          = ?,
            biblionumber        = ?,
            biblioitemnumber    = ?,
            barcode             = ?,
            dateaccessioned     = ?,
            booksellerid        = ?,
            homebranch          = ?,
            price               = ?,
            replacementprice    = ?,
            replacementpricedate = ?,
            datelastborrowed    = ?,
            datelastseen        = ?,
            stack               = ?,
            notforloan          = ?,
            damaged             = ?,
            damaged_on          = ?,
            itemlost            = ?,
            itemlost_on         = ?,
            withdrawn           = ?,
            withdrawn_on        = ?,
            itemcallnumber      = ?,
            coded_location_qualifier = ?,
            issues              = ?,
            renewals            = ?,
            reserves            = ?,
            restricted          = ?,
            itemnotes           = ?,
            itemnotes_nonpublic = ?,
            holdingbranch       = ?,
#            $item->{'timestamp'},
            location            = ?,
            permanent_location  = ?,
            onloan              = ?,
            cn_source           = ?,
            cn_sort             = ?,
            ccode               = ?,
            materials           = ?,
            uri                 = ?,
            itype               = ?,
            more_subfields_xml  = ?,
            enumchron           = ?,
            copynumber          = ?,
            stocknumber         = ?,
            new_status          = ?,
            exclude_from_local_holds_priority = ?
    ";
    $addItemSth = $dbh->prepare($query);
  }
    $addItemSth->execute(
            ($main::args{preserveIds}) ? $item->{itemnumber} : undef,
            $item->{'biblionumber'},
            $item->{'biblioitemnumber'},
            $item->{barcode},
            $item->{'dateaccessioned'},
            $item->{'booksellerid'},
            $item->{'homebranch'},
            $item->{'price'},
            $item->{'replacementprice'},
            $item->{'replacementpricedate'},
            $item->{datelastborrowed},
            $item->{datelastseen},
            $item->{stack},
            $item->{'notforloan'} // 0,
            $item->{'damaged'} // 0,
            $item->{'damaged'} && $item->{'damaged_on'} ? $item->{'damaged_on'} : $item->{'damaged'} ? $nowISO : undef,
            $item->{'itemlost'} // 0,
            $item->{'itemlost'} && $item->{'itemlost_on'} ? $item->{'itemlost_on'} : $item->{'itemlost'} ? $nowISO : undef,
            $item->{'withdrawn'} // 0,
            $item->{'withdrawn'} && $item->{'withdrawn_on'} ? $item->{'withdrawn_on'} : $item->{'withdrawn'} ? $nowISO : undef,
            $item->{'itemcallnumber'},
            $item->{'coded_location_qualifier'},
            $item->{'issues'} // 0,
            $item->{'renewals'},
            $item->{'reserves'},
            $item->{'restricted'},
            $item->{'itemnotes'},
            $item->{'itemnotes_nonpublic'},
            $item->{'holdingbranch'},
#            $item->{'timestamp'},
            $item->{'location'},
            $item->{'permanent_location'},
            $item->{'onloan'},
            $item->{'items.cn_source'},
            $item->{'items.cn_sort'},
            $item->{'ccode'},
            $item->{'materials'},
            $item->{'uri'},
            $item->{'itype'},
            $item->{'more_subfields_xml'},
            $item->{'enumchron'},
            $item->{'copynumber'},
            $item->{'stocknumber'},
            $item->{'new_status'},
            $item->{'exclude_from_local_holds_priority'},
    );

    my $itemnumber;
    if ( defined $addItemSth->errstr ) {
        die ("ERROR in _koha_new_item ".$addItemSth->errstr);
    }
    else {
        $itemnumber = $dbh->{'mysql_insertid'};
    }

    return ($itemnumber);
}

return 1;

