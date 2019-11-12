package Bulk::AutoConfigurer;

use Modern::Perl;
use Carp qw(cluck);

use C4::Context;

sub item {
  my ($item, $error) = @_;
  if ($error =~ /Cannot add or update a child row: a foreign key constraint fails.+FOREIGN KEY \(`(homebranch|holdingbranch)`\)/sm) {
    return addBranch($item->{homebranch}) && addBranch($item->{holdingbranch});
  }
}

sub borrower {
  my ($borrower, $error) = @_;
  if ($error =~ /Cannot add or update a child row: a foreign key constraint fails.+FOREIGN KEY \(`(categorycode)`\)/sm) {
    return addCategorycode($borrower->{$1});
  }
}

our %locationsAutoconfigured;
sub shelvingLocation {
  my ($permanent_location, $location) = @_;

  for my $loc (@_) {
    unless ($locationsAutoconfigured{$loc}) {
      my $ary = C4::Context->dbh->selectall_arrayref(
        'SELECT 1 FROM authorised_values WHERE category = "loc" AND authorised_value = ?',
        undef,
        $loc
      );
      unless (ref($ary) eq 'ARRAY' && scalar(@$ary) > 0) {
        C4::Context->dbh()->do("INSERT IGNORE INTO authorised_values (category, authorised_value, lib, lib_opac) ".
                                "VALUE ('LOC','$loc','AUTO-$loc','AUTO-$loc')");
      }
      $locationsAutoconfigured{$loc} = 1;
    }
  }
}

our %itypesAutoconfigured;
sub itemType {
  my ($itype) = @_;

  unless ($itypesAutoconfigured{$itype}) {
    my $ary = C4::Context->dbh->selectall_arrayref(
      'SELECT 1 FROM itemtypes WHERE itemtype = ?',
      undef,
      $itype
    );
    unless (ref($ary) eq 'ARRAY' && scalar(@$ary) > 0) {
      C4::Context->dbh()->do("INSERT IGNORE INTO itemtypes (itemtype, description) ".
                              "VALUE ('$itype','AUTO-$itype')");
    }
    $itypesAutoconfigured{$itype} = 1;
  }
}

our %borcatAutoconfigured;
sub borcat {
  my ($borcat) = @_;

  unless ($borcatAutoconfigured{$borcat}) {
    my $ary = C4::Context->dbh->selectall_arrayref(
      'SELECT 1 FROM categories WHERE categorycode = ?',
      undef,
      $borcat
    );
    unless (ref($ary) eq 'ARRAY' && scalar(@$ary) > 0) {
      C4::Context->dbh()->do("INSERT IGNORE INTO categories (categorycode, description) ".
                              "VALUE ('$borcat','AUTO-$borcat')");
    }
    $borcatAutoconfigured{$borcat} = 1;
  }
}

sub addBranch {
  my ($branchcode) = @_;
  return C4::Context->dbh()->do("INSERT IGNORE INTO branches (branchcode, branchname) VALUE ('$branchcode','AUTO-$branchcode')");
}

sub addCategorycode {
  my ($categorycode) = @_;
  return C4::Context->dbh()->do("INSERT IGNORE INTO categories (categorycode,description) VALUE ('$categorycode','AUTO-$categorycode')");
}

1;
