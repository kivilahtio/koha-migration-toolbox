# This file is part of koha-migration-toolbox
#
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with koha-migration-toolbox; if not, see <http://www.gnu.org/licenses>.
#

package Exp::Strategy::BoundRecords;

#Pragmas
use warnings;
use strict;

#External modules
use Carp;

=head2 NAME

Exp::Strategy::BoundRecords

=head2 DESCRIPTION

Exports bound MFHD records (sidotut saatavuustietueet).
Takes all bound MFHD records and creates a parent bibliographic record to collect all bound records.
Bound records are linked to it using MARC 776.
Bound records from Voyager lose their holdings records as they are moved under the new parent bound record.

=cut

use Exp::DB;
use Exp::Config;
use Exp::nvolk_marc21;

our %boundRecordIds;

=head2 createBoundMfhdParentRecord

https://www.kiwi.fi/display/kumea/2015-03-26

The bound mfhd parent biblio is built based on the first bound bib instance (eg. having the smallest bib_id in the DB)
Others are linked to it.

=cut

sub createBoundMfhdParentRecord($$) {
  my ($mfhdId, $boundParentId) = @_;
  my $dbh = Exp::DB::dbh();

  my $bibIds = Exp::DB::mfhd_id2bib_ids($mfhdId);
  # Parent is arbitrarily picked from the smallest bib_id
  my $boundParentRecord = Exp::DB::bib_id2bib_record($bibIds->[0]);
  if ( !defined($boundParentRecord) || !$boundParentRecord ) {
    print STDERR "MFHD-$mfhdId\tERROR\tRefers to a missing bib ", $bibIds->[0], ", check BIB_MFHD table...\n";
  }
  # Set the new parent's $001 to the reused bib id
  $boundParentRecord = Exp::nvolk_marc21::marc21_record_replace_field($boundParentRecord, '001', $boundParentId);


  my @boundChildRecords = map { Exp::DB::bib_id2bib_record($_) } @$bibIds;

  warn "Merging records '@$bibIds' under a new parent '$boundParentId'\n";

  _linkChildToParent(\$boundParentRecord, $bibIds, \@boundChildRecords);
  _mergeChildMetadataToParent(\$boundParentRecord, $bibIds, \@boundChildRecords);

  return ($boundParentRecord, $bibIds, \@boundChildRecords);
}

=head2 _linkChildToParent

 @param1 Pointer to String, MARC Record as ISO, as moving a big string around is slow

=cut

sub _linkChildToParent($$$) {
  my ($boundParentRecord, $boundChildIds, $boundChildRecords) = @_;

  my @bCR = @$boundChildRecords;
  for (my $j = 0; $j <= $#bCR; $j++) {
    my $boundChildId = $boundChildIds->[$j];
    my $boundChildRecord = $boundChildRecords->[$j];

    my $nimeke = Exp::nvolk_marc21::marc21_record_get_title($boundChildRecord);
    $$boundParentRecord = Exp::nvolk_marc21::marc21_record_add_field($$boundParentRecord, '776', "08\x1FiYksittäiskappale\x1Ft$nimeke\x1FcPainettu\x1Fw$boundChildId");
  }
}

=head2 _mergeChildMetadataToParent

 @param1 Pointer to String, MARC Record as ISO, as moving a big string around is slow

=cut

sub _mergeChildMetadataToParent($$$) {
  my ($boundParentRecord, $boundChildIds, $boundChildRecords) = @_;

  my @other_books;
  my @bCI = @$boundChildIds;
  for ( my $j = 1; $j <= $#bCI; $j++ ) {
    my $boundChildId = $boundChildIds->[$j];
    my $boundChildRecord = $boundChildRecords->[$j];

    # Äh, tämä ei ole ihan sama kuin $nimeke...
    my $a = Exp::nvolk_marc21::marc21_record_get_title_and_author($boundChildRecord);

    if ( $a !~ /\.$/ ) { $a .= "."; }

    my $kustannuspaikka = Exp::nvolk_marc21::marc21_record_get_place_of_publication($boundChildRecord);
    my $kustantaja = Exp::nvolk_marc21::marc21_record_get_publisher($boundChildRecord);
    my $julkaisuvuosi = Exp::nvolk_marc21::marc21_record_get_publication_year($boundChildRecord);
    if ( $julkaisuvuosi =~ /u/ ) { # 'uuuu'=tuntematon
      $julkaisuvuosi = '';
    }

    if ( $kustannuspaikka && $kustantaja && $julkaisuvuosi ) {
      $a .= " KP".$kustannuspaikka." : ".$kustantaja.", ".$julkaisuvuosi.".";
    }
    elsif ( $kustannuspaikka && $kustantaja && !$julkaisuvuosi) {
      $a .= " KP".$kustannuspaikka." : ".$kustantaja.".";
    }
    elsif ( $kustantaja && $julkaisuvuosi ) {
      $a .= " KP".$kustantaja.", ".$julkaisuvuosi.".";
    }
    elsif ( $kustannuspaikka && !$kustantaja && $julkaisuvuosi) {
      $a .= " KP".$kustannuspaikka." : $julkaisuvuosi.";
    }
    elsif ( !$kustannuspaikka && !$kustantaja && $julkaisuvuosi) {
      $a .= " $julkaisuvuosi.";
    }
    elsif ( !$kustannuspaikka && !$kustantaja && !$julkaisuvuosi) {
    }
    else {
      confess("KP: $kustannuspaikka, K:$kustantaja, V:$julkaisuvuosi");
    }
    print STDERR "  $boundChildId: $a\n";
    $other_books[$#other_books+1] = $a;
  }
  my $f501 = join(" ", @other_books);
  if ( $f501 ) {
    #my $content = "  \x1Fa".Encode::encode_utf8("Yhteensidottuna lisäksi: ").$f501;
    #my $content = Encode::encode_utf8("  \x1FaYhteensidottuna lisäksi: ");
    my $content = "  \x1FaYhteensidottuna: ".$f501;
    $content = Exp::nvolk_marc21::unicode_fixes2($content, 0);
    #print STDERR "$content\n\n";
    if ( 0 && $content =~ /: :/ ) {
      exit();
    }

    $$boundParentRecord = Exp::nvolk_marc21::marc21_record_add_field($$boundParentRecord, '501', $content);
  }
}

=head2 export

 @returns HASHRef of bound record id keys pointing to undef or the newly created bound parent record as MARC21 ISO

=cut

sub export() {
  my $dbh = Exp::DB::dbh();

  my $boundMfhdIds = _getBoundMfhdIds();
  my @boundMfhdIds = keys %$boundMfhdIds;
  if (@boundMfhdIds) {
    warn scalar(@boundMfhdIds)." bound MFHDs found!\n";
    _getFreeBibIdSpace();
    open(my $FH, ">:raw", Exp::Config::exportPath('bound.mrc')) or confess "Opening the export file '".Exp::Config::exportPath('bound.mrc')."' failed: ".$!;

    for my $mfhdId (@boundMfhdIds) {
      my $boundParentId = _getFreeBibId();
      my ($boundParentRecord, $boundChildIds, $boundChildRecords) = createBoundMfhdParentRecord($mfhdId, $boundParentId);
      $boundRecordIds{$boundParentId} = $boundParentRecord;
      $boundRecordIds{$_} = undef for(@$boundChildIds);


      print $FH $boundParentRecord."\n";
      print $FH $_."\n" for @$boundChildRecords;
    }

    close $FH;
  }
  return \%boundRecordIds;
}

=head2 _getBoundMfhdIds

 @returns HASHRef of MFHD Ids that refer|share multiple bibliographic records, and the count of how many bibliographic records they refer to.

=cut

sub _getBoundMfhdIds() {
  my $dbh = Exp::DB::dbh();
  my $sth = $dbh->prepare(" select *
                              from (
                                select mfhd_id, count(mfhd_id) as c
                                from bib_mfhd
                                group by mfhd_id
                              )
                            where c > 1
                            order by c desc, mfhd_id"
    ) || confess($dbh->errstr);

  $sth->execute() || confess($dbh->errstr);

  my %countBoundBibliosByMfhdId;
  my @row;
  while ( ( @row ) = $sth->fetchrow_array ) {
    $countBoundBibliosByMfhdId{$row[0]} = $row[1];
  }
  return \%countBoundBibliosByMfhdId;
}

=head2 _getFreeBibIdSpace

Reuses deleted biblio ids.

 @returns ARRAYRef of free bibliographic record ids.

=cut

my @usedBibIds; my $usedBibIdsPtr = 0; my $usedBibIdsNextCandidateValue = 1;
sub _getFreeBibIdSpace() {
  my $dbh = Exp::DB::dbh();
  my $query = "select bib_id from bib_text order by bib_id asc";
  my $sth = $dbh->prepare($query) or confess($dbh->errstr);
  $sth->execute() || confess($dbh->errstr);
  #@usedBibIds = $sth->selectall_array(); #DBD::Oracle doesn't recognize selectall_array??? It is the latest version and docs say it should
  while (my @row = $sth->fetchrow_array) {
    push(@usedBibIds, $row[0]);
  }
}

=head2 _getFreeBibId

 @returns Integer, a reused deleted biblio id, or a brand new one if none available

=cut

sub _getFreeBibId {
  my $lastExistingId = $usedBibIds[ $usedBibIdsPtr ];
  my $nextExistingId = $usedBibIds[ $usedBibIdsPtr+1 ];
  if ($usedBibIdsNextCandidateValue < $lastExistingId) {
    return $usedBibIdsNextCandidateValue++;
  }
  return $usedBibIdsNextCandidateValue++ if (not($nextExistingId)); #We have ran out of existing ids, just keep introducing new ones

  # Look for the next available opening between existing ids
  while (not($lastExistingId < $usedBibIdsNextCandidateValue && $usedBibIdsNextCandidateValue < $nextExistingId)) {
    $usedBibIdsNextCandidateValue++;
    if ($nextExistingId <= $usedBibIdsNextCandidateValue) {
      $lastExistingId = $usedBibIds[ ++$usedBibIdsPtr ];
      $nextExistingId = $usedBibIds[ $usedBibIdsPtr+1 ];
    }
    return _getFreeBibId() if (not($nextExistingId)); #Exit the loop if existing ids ran out
  }
}

return 1;
