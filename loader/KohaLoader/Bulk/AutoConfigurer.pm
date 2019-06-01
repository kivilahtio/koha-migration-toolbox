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

sub addBranch {
  my ($branchcode) = @_;
  return C4::Context->dbh()->do("INSERT IGNORE INTO branches (branchcode, branchname) VALUE ('$branchcode','AUTO-$branchcode')");
}

sub addCategorycode {
  my ($categorycode) = @_;
  return C4::Context->dbh()->do("INSERT IGNORE INTO categories (categorycode,description) VALUE ('$categorycode','AUTO-$categorycode')");
}

1;
