#!/usr/bin/perl -w
#
# nvolk_marc21.pm - Library for manipulation MARC21 input, mainly records
#
# Copyright (c) 2011-2018 Kansalliskirjasto/National Library of Finland
# All Rights Reserved.
#
# Author(s): Nicholas Volk (nicholas.volk@helsinki.fi)
#
# TODO:
# o Add a (MIT?) license
# o Add object-oriented alternative alternative (then composing and
#   decomposing the MARC21 string would need to be done only at the
#   beginning and the end => way faster)
# o Move validation part to a separate file
#
# Yet another Marc21 processor. The main advantage with this version is that
# one can delete fields and subfields from a record pretty easily.
#
# Used by:
# - marc2dc2.pl (Marc21 -> DublinCore) converter (todo: test latest version)
#   (removes "used up" components from the record, so that we'll know what
#    parts (if any) of the input were not converted.)
# - viola_auktoriteet.perl (auktoriteettikonversioskripti)
# - Fono-konversio (voyager/viola/scripts/fono/)
# - multiple other scripts by Nicholas and Leszek..
#
# NB! There are various other conversion tools out there as well...
#
# TODO: Object Oriented approach...
# We could just convert each record to header + array for tag names
# + array for tag contents
#
# TODO: wrapper (get field + change indicator(s) + put back)
# for indicator manipulation.
#
# KK version control (SVN): stored under voyager/viola/scripts/fono/
# Will move to Github eventually...
#
# 2015-04-27: initial Melinda/Aleph support, not all alphabetical tags yet supported...
#
# NB! XML::XPath and XML::XPath::XMLParser do evil things to input string!
# Bad because of \x1F etc:
#  my $original_size = bytes::length(Encode::encode_utf8($record));
#  my $original_size = bytes::length($record);
# For parsing oai_marcxml

#use XML::XPath;
#use XML::XPath::XMLParser;

use Encode;
use strict;
my $debug = 0;

package Exp::nvolk_marc21;

#########################################
sub ere_get_field($$) {
  my ($a_marc, $a_field) = @_;
  print STDERR "ere_get_field($$) is deprecated. Use marc21_record_get_field($$$) instead...\n";
  return marc21_record_get_field($a_marc, $a_field, '');
}

#########################################
sub _ere_get_all_fields($) {
  #print STDERR "egaf()\n";
  # Modified from Ere Maijala's code taken from $somewhere.
  # Might be deprecated eventually...
  my ($a_marc) = @_;
  my @fields;
  my $dirpos = 24;
  my $base = substr($a_marc, 12, 5); # This does not work with our rebuild stuff
  #print STDERR "BASE '$base'\n$a_marc\n";
  my $a_marc_len = marc21_length($a_marc);
  #my $a_marc_len = bytes::length(Encode::encode_utf8($a_marc));
  #my $a_marc_len = bytes::length($a_marc);
  #my $a_marc_len = length($a_marc);
  my $result = 1;
  while ( substr($a_marc, $dirpos, 1) ne "\x1E" && $dirpos < $a_marc_len ) {
    my $tag = substr($a_marc, $dirpos, 3);
    my $len = substr($a_marc, $dirpos + 3, 4);
    my $pos = substr($a_marc, $dirpos + 7, 5);
    if ( $base +
	 $pos <
	 $a_marc_len ) {
      my $field = bytes::substr($a_marc, $base + $pos, $len);
      #my $field = substr($a_marc, $base + $pos, $len);
      if ( $tag =~ /^00[0-9]$/ ) { $field =~ s/\x1e$//g; }
      push (@fields, $field);
    }
    else {
      print STDERR "$tag/$len/$pos+$base points outside of the record (size $a_marc_len) (" . ($#fields+1) . ")...\n";
      print STDERR "$a_marc\n";
      die();
      push (@fields, "");
      $result = 0;
    }
    $dirpos += 12;
  }
  return ( $result, @fields );
}

sub nvolk_get_all_fields($) {
  my ( $record ) = @_;
  return _ere_get_all_fields($record);


  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
  my @directory_tags = marc21_directory2array($directory);
  my @fields  = split(/\x1E/, $cfstr);
  if ( $#directory_tags != $#fields ) {
    print STDERR "Mismatch $#directory_tags vs $#fields!\n";
    my $i=0;
    for ( ; $i <= $#directory_tags; $i++ ) {
      print STDERR "'$i\t$directory_tags[$i]'\n";
    }
    print STDERR "$cfstr\n";

    # Heh, hacky...
    return _ere_get_all_fields($record);
  }
  # Tämä höhlyys olettaa, että kentät tulevat oikeassa järjestyksessä...
  return ( 1, @fields );
}

#########################################

sub marc21_field_get_subfield($$) {
  my ( $field, $subfield ) = @_;
  if ( $field =~ /\x1F${subfield}([^\x1D\x1E\x1F]*)/ ) {
    return $1;
  }
  # return ''; # there can be subfields with no content so this must be undef...
  return undef;
}

sub marc21_field_remove_subfield_once($$) {
  # "_once" as there may be multiple instances of same subfield
  my ( $field, $subfield ) = @_;
  $field =~ s/\x1F${subfield}([^\x1D\x1E\x1F]+)//;
  # This was the only subfield, so dump the whole field:
  if ( bytes::length($field) == 2 ) {
    return '';
  }
  return $field;
}

sub marc21_field_remove_subfields($$) {
  my ( $field, $subfield ) = @_;
  $field =~ s/\x1F${subfield}([^\x1D\x1E\x1F]+)//g;
  if ( bytes::length($field) == 2 ) {
    return '';
  }
  return $field;
}


# convert directory into three arrays...
sub marc21_directory2tag_len_pos($) {
  my $directory = $_[0];
  my @tag = ();
  my @len = ();
  my @pos = ();
  while ( $directory ) {
    if ( $directory =~ s/^(...)(....)(.....)// ) {
      my $t = $1; # keeps the inital zeroes: "008", "045"
      my $l = $2;
      my $p = $3;
      $l =~ s/^0+(\d)/$1/; # leave the final 0
      $p =~ s/^0+(\d)/$1/; # leave the final 0
      push(@tag, $t);
      push(@len, $l);
      push(@pos, $p);
    }
    else {
      die("oops2 '$directory'\n");
    }
  }
  return (\@tag, \@len, \@pos );
}

sub marc21_reset_record_length($) {
  my $record = $_[0];
  ## Update the leader 0-4 (record length)
  #my $length = bytes::length(Encode::encode_utf8($record));
  my $length = marc21_length($record);
  while ( length($length) < 5 ) { $length = "0$length"; }
  #$length = ( (5-length($length)) x '0' ) . $length;
  #$length = sprintf("%.5d", $length);
  $record =~ s/^(.....)/$length/;
  ## Update the leader 12-16 (base address of data)
  my $tmp = $record;
  $tmp =~ s/\x1e.*$/\x1e/s; # säilytetään itse erotin

    # $length = bytes::length(Encode::encode_utf8($tmp));
    $length = marc21_length($tmp);
  #$length = ( (5-length($length)) x '0' ) . $length;
  while ( length($length) < 5 ) { $length = "0$length"; }
  #$length = sprintf("%.5d", $length);
  $record =~ s/^(.{12})(.....)/$1$length/;
  return $record;
}

sub marc21_dir_and_fields2arrays($$) {
  my $directory = $_[0];
  my $cfstr = $_[1];

  my ($tag_ref, $len_ref, $pos_ref) = marc21_directory2tag_len_pos($directory);
  #print STDERR " DAF1\n$cfstr\n";
  my @tag = @$tag_ref;
  my @len = @$len_ref;
  my @pos = @$pos_ref;

  my $i;
  my @contents;
  my $tmp;
  for ( $i=0; $i <= $#tag; $i++ ) {
    #print STDERR "POS $pos[$i] LEN $len[$i]\n";
    $tmp = bytes::substr($cfstr, $pos[$i], $len[$i]);
    #print STDERR "$tmp\n";
    $tmp =~ s/\x1e$//; # vai lyhennetäänkö yhdellä?
    push(@contents, $tmp); # NB! includes \x1f
  }
  return(\@tag, \@contents);
}



#sub marc21_get_directory($) { # probably unused by all
#  my $record = $_[0];
#  $record =~ s/^.{24}//;
#}

sub marc21_get_leader($) { # name: drop 21, add record_ before "get"
  $_[0] =~ /^(.{24})/;
  if ( $1 ) { return $1; }
  return "";
}



# get a single record from <>
sub marc21_read_record_from_stdin() {
  my $tmp = $/;
  $/ = "\x1D";
  my $record = <>; # TODO: name has stdin ja this uses <>...
  $/ = $tmp;
  return $record;
}


# Split records in the same input string into an array of records.
# This may use loads of memory depending on the input string
sub marc21_get_record_array($) {
  my @array = split(/\x1D/, $_[0]);
  return @array;
}

# Split a given record into 3 parts: leader, directory and fields
sub marc21_record2leader_directory_fields($) {
  my $record = $_[0];
  my $leader = '';
  my $directory = '';
  my $fields = '';

  $record =~ s/\x1D$//; # remove separator

  my $i = index($record, "\x1E");
  if ( $i >= 24 ) { # 1st \x1E comes after directory
    # 2015-11-16: removed $' and $` stuff which seemed to perform unexpectedly
    # with  utf8::is_utf8(). Anyway, this is more effective as well.
    $directory = substr($record, 0, $i);
    $fields = substr($record, $i+1);
    # separate leader and directory
    $directory =~ s/^(.{24})// or die();
    $leader = $1;
    return ( $leader, $directory, $fields );
  }
  elsif ( $i == -1 && length($record) == 24 ) { # only directory (future new record?)
    return ( $record, '', '' );
  }
  
  print STDERR "ERROR: No delimeter found within record:\n'$record'!\n";
  return ();
}

sub marc21_leader_directoryarr_fieldsarr2record($$$) {
  my ( $leader, $dir_ref, $field_ref ) = @_;
  # 20151118: force tail ( removed parameter)

  my @contents = @$field_ref;
  my @tags = @$dir_ref;

  my $starting_pos = 0;
  my $new_dir = '';
  my $new_fields = '';
  my $new_cfstr = '';
  my $i;
  for ( $i=0; $i <= $#contents; $i++ ) {
    # sometimes tags are actually full 12 char long entries
    if ( $tags[$i] =~ s/^(...)(.+)/$1/ ) { # make this more robust
      #print STDERR "Omitted suffix $1/$2 from tag #$i\n";
    }
    my $data = $contents[$i];
    if ( $data !~ /\x1e$/ ) { # add field separator when necessary
      $data .= "\x1e";
    }

    ## Directory:
    #my $flen = bytes::length(Encode::encode_utf8($data));
    #my $flen = bytes::length($data);
    my $flen = marc21_length($data);

    #$starting_pos = bytes::length(Encode::encode_utf8($new_cfstr));
    #$starting_pos = bytes::length($new_cfstr);
    $starting_pos = marc21_length($new_cfstr);

    #my $row = $tags[$i] . sprintf("%.4d", $flen) . sprintf("%.5d", $starting_pos);
    #print STDERR "REBUILDING $tags[$i]\t'$contents[$i]'\t$tags[$i]\t$starting_pos\t$flen\n";
    while ( length($flen) < 4 ) { $flen = "0$flen"; }
    while ( length($starting_pos) < 5 ) { $starting_pos = "0$starting_pos"; }
    my $row = $tags[$i] . $flen . $starting_pos;
    $new_dir .= $row;

    ## Contents:
    $new_cfstr .= $data;



  }
  # rebuild the record string
  my $new_record = $leader . $new_dir . "\x1E" . $new_cfstr . "\x1D";
  $new_record = &marc21_reset_record_length($new_record);

  return $new_record;
  # TODO: a lot...
}

# Split the fields string into an array of fields
sub marc21_record2fields($) {
  my $record = $_[0];
  my @fields = split(/\x1e/, $record);
  shift(@fields); # 1st is leader+dir (rubbish here)
  return @fields;
}

# For validation only (we could this better)...
sub marc21_initial_field_to_leader_and_directory($) {
  my $data = $_[0];
  my @array = ();
  $data =~ s/^(.{24})//;
  push(@array, $1);
  while ( $data =~ s/^(.{12})// ) {
    push(@array, $1);
  }
  return @array;
}


sub marc21_compare_records($$) {


  my ( $record1, $record2 ) = @_;
  my ( $leader1, $directory1, $cfstr1 ) = marc21_record2leader_directory_fields($record1);
  my ( $leader2, $directory2, $cfstr2 ) = marc21_record2leader_directory_fields($record2);

  my ( $cf1_ok, @fields1 ) = _ere_get_all_fields($record1);

  my ( $cf2_ok, @fields2 ) = _ere_get_all_fields($record2);
  my @tags1 = marc21_directory2array($directory1);
  my @tags2 = marc21_directory2array($directory2);

  my $output = "FAILURE $cf1_ok/$#fields1 $cf2_ok/$#fields2\n";
  if ( $cf1_ok && $cf2_ok ) {
    $output = "COMPARING $cf1_ok/$#fields1 $cf2_ok/$#fields2\n";
    my ( $i1, $i2 );
    for ( $i1 = 0, $i2 = 0; $i1 <= $#fields1 && $i2 <= $#fields2; ) {
      
      if (  $i1 <= $#fields1 && $i2 <= $#fields2 ) {
	$fields1[$i1] =~ s/\x1E$//;
	$fields2[$i2] =~ s/\x1E$//;

	my $t1 = substr($tags1[$i1], 0, 3);
	my $t2 = substr($tags2[$i2], 0, 3);

	if ( $t1 eq $t2 ) {
	  $tags1[$i1] =~ s/^(...)(\S...)/$1 $2 /;
	  $tags2[$i2] =~ s/^(...)(\S...)/$1 $2 /;
	  if ( $fields1[$i1] eq $fields2[$i2] ) {
	    $output .= "a1&2:\t$tags1[$i1]$fields1[$i1]\n";
	  }
	  # #2 has $9 FENNI<KEEP>
	  elsif ( $fields1[$i1] eq "$fields2[$i2]\x1F9FENNI<KEEP>" ) {
	    $output .= "b1&2:\t$tags2[$i2]$fields2[$i2]\n";
	  }
	  elsif ( $fields2[$i2] eq "$fields1[$i1]\x1F9FENNI<KEEP>" ) {
	    $output .= "c1&2:\t$tags1[$i1]$fields1[$i1]\n";
	  }
	  else {
	    $output .= "*1 vs 2:\t'$tags1[$i1]'\t'$fields1[$i1]'\n";
	    $output .= "1 vs *2:\t'$tags2[$i2]'\t'$fields2[$i2]'\n";
	  }
	  $i1++;
	  $i2++;

	}
	elsif ( $t1 lt $t2 ) {
	  $tags1[$i1] =~ s/^(...)(....)/$1 $2 /;
	  $output .= "1:\t$tags1[$i1]\t$fields1[$i1]\n";
	  $i1++;
	}
	elsif ( $t1 gt $t2 ) {
	  $tags2[$i2] =~ s/^(...)(....)/$1 $2 /;

	  $output .= "2:\t$tags2[$i2]\t$fields2[$i2]\n";
	  $i2++;
	}
	else {
	  die();
	  $output .= "1 vs 2:\t$tags1[$i1]\t$fields1[$i1]\n";
	  $output .= "2:\t$tags2[$i2]\t$fields2[$i2]\n";

	}
      }
      elsif ( $i1 <= $#fields1 ) {
	$tags1[$i1] =~ s/^(...)(....)/$1 $2 /;
	$output .= "1:\t$tags1[$i1]\t$fields1[$i1]\n";
	$i1++;
      }
      else { # ( $i2 <= $#fields2 ) {
	$tags2[$i2] =~ s/^(...)(....)/$1 $2 /;
	$output .= "2:\t$tags2[$i2]\t$fields2[$i2]\n";
	$i2++;
      }
    }
  }
  return $output;
}


sub marc21_record_is_valid($$$) {
  # Pretty shit template...
  my ( $record, $item, $tolerant ) = @_;
  $record =~ s/(\x1D)$//;
  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);

  if ( !$leader || $leader !~ /^.{24}$/ ) {
    if ( !$leader ) { print STDERR "$item: Void Record!\n"; }
    else { print STDERR "$item: Corrupted leader: '$leader'\n"; }
    if ( $debug ) {
      print STDERR "$record";
    }
    return 0;
  }

  if ( length($directory) % 12 != 0 ) {
    print STDERR "$item: Unexpected directory, length " . length($directory) . ":\n";
    if ( $debug ) {
      print STDERR $directory;
    }
    return 0;
  }

  my @directory_tags = marc21_directory2array($directory);
  my @fields  = split(/\x1E/, $cfstr);
  my ( $cf2_ok, @fields2 ) = _ere_get_all_fields($record);
  if ( $#directory_tags != $#fields ) {
    print STDERR "$item: Pointers: $#directory_tags+1 Fields: $#fields+1!\n";

    my $i=0;
    while ( $i <= $#directory_tags || $i <= $#fields ) {
      if ( $directory_tags[$i] ) {
	print STDERR "$directory_tags[$i] $fields2[$i]\n";
      }
      else { print STDERR '>' x 25; }
      if ( $fields[$i] ) {
	print STDERR "$fields[$i]\n";
      }
      if ( $fields[$i] =~ /[\x1D\x1E]/ ) {
	# DO SOMETHING
      }
      $i++;

    }
    if ( $debug ) {
      print STDERR "0: $directory_tags[0]\n";
      print STDERR "N: $directory_tags[$#directory_tags]\n";
      print STDERR $record;
    }
    # BUGGY, but maybe we can still get something out of it
    if ( $tolerant && $#directory_tags < $#fields ) {
      return 1;
    }
    return 0;
  }
  else {
    # TODO: Compare Ere's results with my results...
  }



  return 1;
}


sub marc21_check_field_008($) { # Validation-only
  my $f008 = $_[0];
  if ( length($f008) != 40 ) {
    return 0;
  }
  return 1;
}

sub record_merge_two_records($$) {
  print STDERR "TODO: record_merge_two_records()\n";
  # TÄMÄ PITÄISI TEHDÄ OLIONA!
}

sub marc21_record_remove_duplicate_fields($$) {
  my ( $record, $tag ) = @_;
  my ( $i, $j );
  my @fields = marc21_record_get_fields($record, $tag, '');
  for ( $i=$#fields-1; $i >= 0; $i-- ) {
    my $field = $fields[$i];
    for ( $j=$#fields; $j > $i; $j-- ) {
      if ( $field eq $fields[$j] ) {
	$record = marc21_record_remove_nth_field($record, $tag, '', $j);
	# splice() would probably be fine, but just to be on the safe side:
	@fields = &marc21_record_get_fields($record, $tag, undef);
      }
    }
  }
  return $record;
}


sub marc21_sanity_check_record($) {
  my $record = $_[0];

  # 1. Check size
  my $size = 0;
  if ( $record =~ /^(\d{5})/ ) {
    $size = $1;
    $size =~ s/^0+//;
    #if ( $size != bytes::length(Encode::encode_utf8($record)) ) { return 0; }
    if ( $size != bytes::length($record) ) { return 0; }
  }
  my @fields = marc21_record2fields($record);
  my @directory = marc21_initial_field_to_leader_and_directory($fields[0]);
  my $leader = shift(@directory);
  ## ... N-1. There are multiple other tests that should be included...
}

sub marc21_get_control_fields($$$) {
  if ( $debug ) { print STDERR "marc21_get_control_fields()\n"; }
  my ( $directory, $fields, $id ) = @_;
  my @result = ();
  while ( $directory =~ s/^(\d{3}|CAT|COR|DEL|FMT|LID|LKR|LOW|OWN|SID|TPL)(\d{4})(\d{5})// ) {
    my $tag = $1;
    my $flen = $2;
    my $start = $3;
    $tag =~ s/^0+(\d)/$1/; # leave the final 0
    $flen =~ s/^0+//;
    $start =~ s/^0+(\d)/$1/; # leave the final 0
    if ( $id == $tag ) {
      #if ( bytes::length(Encode::encode_utf8($fields)) >= $start+$flen-1 ) {
      if ( bytes::length($fields) >= $start+$flen-1 ) {
	# 1. get the data from fields
	# ($flen-1 omits the \x1E delimiter)
	my $hit = bytes::substr($fields, $start, $flen-1);
	# 2. push it into @result;
	push(@result, $hit);
      }
      else {
	#print STDERR "Problematic sizes: " . bytes::length(Encode::encode_utf8($fields)) . " vs $start+$flen\n";
	print STDERR "Problematic sizes: " . bytes::length($fields) . " vs $start+$flen\n";
      }
    }
  }
  #if ( $#result >= 0 ) { print STDERR  "$id; ", ($#result+1), " hit(s)\n"; }
  return @result;
}

sub marc21_get_control_field($$$) {
  if ( $debug ) { print STDERR "marc21_get_control_field()\n"; }
  my @result = marc21_get_control_subfields($_[0], $_[1], $_[2], "");
  # sanity checks:
  if ( $#result == -1 ) {
    if ( $debug ) { print STDERR "Warning: $_[2] not found!\n"; }
    return ();
  }
  if ( $#result > 0 ) {
    print STDERR "Warning: $_[2] has multiple values, return only one of them!\n";
  }
  if ( $result[0] =~ s/(\x1E.*)$// ) {
    print STDERR "\\x1E found within a field (field position and size based on the directory): $result[0]$1\n";
  }
  return $result[0];
}

sub marc21_get_control_subfields($$$$) {
  if ( $debug ) { print STDERR "marc21_get_control_subfields()\n"; }
  my @result = ();
  my @fields = marc21_get_control_fields($_[0], $_[1], $_[2]);
  my $subfield;
  my $field;

  if ( $_[3] eq "" ) { return @fields; }

  foreach $field ( @fields ) {
    my @subfields = split(/\x1F/, $field);
    foreach $subfield ( @subfields ) {
      if ( $subfield =~ s/^$_[3]// ) {
	if ( $subfield =~ /\S/ ) {
	  push(@result, $subfield);
	}
      }
    }
  }
  return @result;
}


sub marc21_get_control_subfield($$$$) {
  if ( $debug ) { print STDERR "marc21_get_control_subfield()\n"; }
  my @result = marc21_get_control_subfields($_[0], $_[1], $_[2], $_[3]);
  # sanity checks:
  if ( $#result == -1 ) {
    if ( $debug ) { print STDERR "Warning: $_[2]$_[3] not found!\n"; }
    return @result;
  }
  if ( $#result > 0 ) {
    print STDERR "Warning: $_[2]$_[3] has multiple values, return only one of them!\n";
  }
  return ( $result[0] );
}

sub marc21_directory2array($) {
  my $directory = $_[0];
  my $original = $directory;
  # TODO: length(directory)%12 sanity check
  my @array = ();
  while ( $directory =~ s/^(.{12})// ) {
    my $hit = $1;
    #print STDERR ".: '$hit'\n";
    push(@array, $hit);
    #print STDERR "=: '$array[$#array]'\n";
  }
  if ( $directory ne "" ) {
    return ();

  }
  #print STDERR "\n";
  return @array;
}

# splice can be used to add elements to an array:
#
#  splice(@array,$i,0,"New value");

sub marc21_fields2array($) {
  my $cfstr = $_[0];
  $cfstr =~ s/^\x1E//;
  $cfstr =~ s/\x1E$//;
  return split(/\x1E/, $cfstr);
}



sub marc21_record_get_fields($$$) {
  my ( $record, $field, $subfield ) = @_;
  # TODO: modernize this (compare with marc21_record_add_field()
  $record =~ s/(\x1D)$//;
  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  if ( defined($subfield) && length($subfield) > 1 ) {
    die("Overlong subfield: '$subfield'\n");
  }
  my @tags = @$tags_ref;
  my @contents = @$contents_ref;

  my @results = ();
  my $i;
  my $pos = 0;
  for ( $i=0; $i <= $#tags; $i++ ) {
    if ( $field eq $tags[$i] ) {

      my $fc = $contents[$i];
      if ( !defined($subfield) || $subfield eq '' ) { # The whole field
	$results[$pos] = $fc;
      }
      else { # Subfield only
	my $sf = &marc21_field_get_subfield($fc, $subfield);
	#print STDERR "$field vs $tags[$i]\n";
	#print STDERR " $subfield: '$sf'\n";
	$results[$pos] = $sf;
      }
      $pos++;
    }
  }
  return @results;
}

sub normalize_tag($) {
  # Korjaa esmes joku virheellinen  "24"-kenttä "024":ksi:
  my $tag = $_[0];
  if ( $tag =~ /^\d$/ ) {
    return "00$tag";
  }
  if ( $tag =~ /^\d\d$/ ) {
    return "0$tag";
  }
  return $tag;
}

sub marc21_record_get_nth_field($$$$) {
  my ( $record, $field, $subfield, $skip ) = @_;

  $field = &normalize_tag($field);


  my @array = marc21_record_get_fields($record, $field, $subfield);
  if ( defined($array[$skip]) ) {
    return $array[$skip];
  }
  return undef; # 20161124: replace original ''...
}

sub marc21_record_get_field($$$) {
  return marc21_record_get_nth_field($_[0], $_[1], $_[2], 0);
}


sub marc21_to_sequential($$) {
  my ( $record, $prefix ) = @_;
  if ( !defined($prefix) ) {
    $prefix = marc21_record_get_field($record, '001', '');
  }
  # säv. säv.
  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  my @tags = @$tags_ref;
  my @contents = @$contents_ref;
  my ($i, $j);
  my $seq = '';
  for ( $i=0; $i < $#tags; $i++ ) {
    $seq .= "$prefix ";
    $seq .= $tags[$i];
    my @sf = split(/\x1F/, $contents[$i]);
    if ( $#sf > 0 ) {
      $seq .= $sf[0]; # indicaattorit
      $seq .= ' L ';
      for ( $j=1; $j<=$#sf; $j++ ) {
	$seq .= "\$\$$sf[$j]";
      }
    }
    else {
      $seq .= '  ';
      $seq .= ' L ';
      $seq .= $contents[$i];
    }
    $seq .= "\n";
    
  }
  return $seq;
}


sub marc21_debug_record($$) {
  my ( $record, $id ) = @_;
  my $str = '';

  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);


  my @directory_tags = marc21_directory2array($directory);
  if ( $#directory_tags == -1 ) {
    $str .= "$id: Corrupted directory (probably wrong size): '$directory'" . length($directory) . "\n";
  }

  my ( $cf2_ok, @fields2 ) = _ere_get_all_fields($record);
  my @fields  = split(/\x1E/, $cfstr);

  if ( $#directory_tags > $#fields ) {
    $str .= "0: $directory_tags[0]\n";
    $str .= "N: $directory_tags[$#directory_tags]\n";
    $str .= "$record\n";
    #die;
  }
  elsif ( $#directory_tags != $#fields ) {
    $str .= "$id: directory does not contain all the tags: $#directory_tags+1 vs $#fields+1!\n";
    $str .= "$record\n";
  }


  my ( $tag, $length, $starting_pos );
  $starting_pos = 0;
  my $i = 0;
  
  my $new_cfstr = "";
  my $erestr = '';
  #$str .= "## $id ##\n$record\n## $id ##\n";
  $str .= "\n## $id ##\n";
  $str .= "LDR\t'$leader'\n";

  for ( $i = 0; $i <= $#directory_tags; $i++ ) {
    $directory_tags[$i] =~ /^(...)(....)(.....)$/ or die("oops $i: '$directory_tags[$i]'");
    my $tag = $1;
    my $flen = $2;
    my $start = $3;
    # print STDERR "TAG $tag FLEN $flen START $start\t'$fields2[$i]'\n";
    $flen =~ s/^0+//;
    $start =~ s/^0+(\d)/$1/; # leave the final 0
    #print STDERR "TAG $tag FLEN $flen START $start\n";
    # 1) get the field contents
    #my $field_data = ( $is_utf8 ? bytes::substr(Encode::encode_utf8($cfstr), $start, $flen) : substr($cfstr, $start, $flen));
    my $field_data = bytes::substr($cfstr, $start, $flen); # ( $is_utf8 ? bytes::substr($cfstr, $start, $flen) : substr($cfstr, $start, $flen));
    #my $field_data = length($cfstr, $start, $flen); # ( $is_utf8 ? bytes::substr($cfstr, $start, $flen) : substr($cfstr, $start, $flen));

    my $dt = $directory_tags[$i];
    $dt =~ s/^(\d{3}|CAT|COR|DEL|FMT|LID|LKR|LOW|OWN|SID|TPL)(\d{4})(\d{5})/$1 $2 $3/;
    $str .= "#$i\t$dt\t'$field_data' ($flen)\n";
    if ( $debug ) {
      $erestr .= "$directory_tags[$i] $fields2[$i]\n";
    }
  }
  $str .= $erestr;
  return $str;
}

sub marc21_field_get_subfields($$) {
  my ( $field, $sf_code ) = @_;

  my @subfields = split(/\x1F/, $field);
  shift(@subfields); # skip indicators
  if ( !$sf_code ) {
    return @subfields
  }
  my @sf2 = ();
  my $i;
  for ( $i = 0; $i <= $#subfields; $i++ ) {
    my $sf = $subfields[$i];
    if ( $sf =~ s/^$sf_code// ) { # removes subfield code, should it?
      push(@sf2, $sf);
    }
  }
  return @sf2;
}

sub marc21_rebuild($) {
  print STDERR "marc21_rebuild(\$record)\n";
  my $record = shift();

  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);

  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  my @tags = @$tags_ref;
  my @contents = @$contents_ref;

  # my $i; for ( $i=0; $i <= $#tags; $i++ ) { print STDERR "$tags[$i]\t'$contents[$i]'\n"; }

  my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader, \@tags, \@contents);

  return $new_record;
}


# TODO: nth
sub marc21_record_add_field($$$) {
  # Meillä on bugi, jos tietueella ei ole utf-8-lippua päällä (vaikka siellä
  # olisi utf-8:aa), mutta uudella kentällä on, niin ylikonvertointia tapahtuu..
  my ( $original_record, $new_field, $new_data ) = @_;

  if ( $debug ) {
    print STDERR "marc21_record_add_field(record, $new_field, '$new_data')\n";
  }

  # print STDERR "$original_record\n\n";

  #my $original_size = bytes::length(Encode::encode_utf8($original_record));
  #my $original_size = bytes::length($original_record);
  my $original_size = marc21_length($original_record);

  my $record = $original_record;

  
  $new_data =~ s/\x1e$//;

  my $added_len = 0;
  if ( $new_field ne '' ) {
    #$added_len = bytes::length(Encode::encode_utf8($new_data))+12+1; # 1 is for the (new) \x1e
    #$added_len = bytes::length($new_data)+12+1; # 1 is for the new \x1e
    $added_len = marc21_length($new_data)+12+1; # 1 is for the new \xe1
    if ( $added_len > 9999 ) { # TOO LONG
      $new_data = substr($new_data, 0, (9999-12-1-3));
      $new_data =~ s/[ .]*$/.../;
      $added_len = marc21_length($new_data)+12+1; # 1 is for the new \xe1
    }
  }
  else {
    # Mikä idiotismi tuo ehto oli=
    die();
  }

  if ( $original_size == 24 ) {
    # $record has only directory, so it will get a \x1e as well:
    $added_len++;
  }


  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);

  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  my @tags = @$tags_ref;
  my @contents = @$contents_ref;


  ## Old version without reordering
  #push(@tags, $new_field);
  #push(@contents, $new_data);
  ## New version with reordering (new tag goes after identical tags)
  my $i;
  if ( $new_field ne '' ) {
    my $new_position = $#tags+1; # add to tail by default
    # Numerokenttä tulee ennen Alephin lopussa olevia kirjainkenttiä.
    # Siirrä takaraja niiden edelle:
    if ( $new_field =~ /^\d\d\d$/ ) {
      while ( $new_position > 1 && $tags[$new_position-1] =~ /^[A-Z]{3}$/ ) {
	$new_position--;
      }
    }

    for ( $i=0; $i<$new_position; $i++ ) {
      if ( $tags[$i] eq $new_field ) {
	# Tarkista, ettei samaa lisätä kahdesti
	# NB! Kenttää 952 saa toistaa!
	# 952 on ruma Koha-hack!
	if ( $new_field ne '952' && $contents[$i] eq $new_data ) {
	  if ( $tags[0] eq '001' ) {
	    print STDERR "NB: no need to add field $new_field: duplicate '$new_data' (001=", $contents[0], ")!\n";
	  }
	  else {
	    print STDERR "NB: no need to add field $new_field: duplicate '$new_data'!\n";
	  }
	  return $original_record;
	}
      }

      if ( $tags[$i] =~ /^[A-Z]{3}$/ ) {
	# skip aleph tags
      }
      elsif ( $tags[$i] gt $new_field ) {
	$new_position = $i;
      }
    }
    #print STDERR "POS $new_position/$#tags $new_field/'$new_data'\n";
    if ( $new_position == $#tags+1 ) {
      $tags[$new_position] = $new_field;
      $contents[$new_position] = $new_data;
    }
    else {
      splice(@tags, $new_position, 0, $new_field);
      splice(@contents, $new_position, 0, $new_data);
    }
  }



  # DEBUG:
  if ( 0 ) {
    print STDERR "NRE LEADER '$leader'\n";
    for ( $i=0; $i <= $#tags || $i <= $#contents; $i++ ) {
      print STDERR "$i\t$tags[$i]\t$contents[$i]\n";
    }
  }
  # update directory and contents:
  my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader, \@tags, \@contents);

  

  # print STDERR "NEW TEST\n$new_record\n\n";

  #my $length = bytes::length(Encode::encode_utf8($new_record));
  #my $length = bytes::length($new_record);
  my $length = marc21_length($new_record);
  if ( $length != $original_size + $added_len ) {
    print STDERR "WARNING: size $original_size + $added_len != $length (12+length('$new_data'))\n";
    print STDERR "\n### raf ORIG\n'$original_record'\n### raf NEW\n'$new_record'\n###\n";
    print STDERR "TAGS 1+$#tags CONTENTS 1+$#contents\n";

    #print STDERR marc21_debug_record($original_record, "ORIGINAL RECORD");
    #print STDERR "\n\n";
    print STDERR marc21_debug_record($new_record, "NEW RECORD");
    print STDERR "\n\n";

    die("DOOM");
  }
  return $new_record;
}


sub marc21_record_always_add_field($$$) {
  # Meillä on bugi, jos tietueella ei ole utf-8-lippua päällä (vaikka siellä
  # olisi utf-8:aa), mutta uudella kentällä on, niin ylikonvertointia tapahtuu..
  my ( $original_record, $new_field, $new_data ) = @_;

  if ( $debug ) {
    print STDERR "marc21_record_always_add_field(record, $new_field, '$new_data')\n";
  }

  my $original_size = marc21_length($original_record);
  my $record = $original_record;
  $new_data =~ s/\x1e$//;

  my $added_len = 0;
  if ( $new_field ne '' ) {
    $added_len = marc21_length($new_data)+12+1; # 1 is for the new \xe1
  }

  if ( $original_size == 24 ) {
    # $record has only directory, so it will get a \x1e as well:
    $added_len++;
  }


  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);

  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  my @tags = @$tags_ref;
  my @contents = @$contents_ref;




  # TODO: add field separators to the end if new field does not have them
  ## New version with reordering (new tag goes after identical tags)
  my $i;
  if ( $new_field ne '' ) {
    my $new_position = $#tags+1; # add to tail by default

    for ( $i=0; $i<$new_position; $i++ ) {
      if ( $tags[$i] gt $new_field ) {
	$new_position = $i;
      }
    }
    #print STDERR "POS $new_position/$#tags $new_field/'$new_data'\n";
    if ( $new_position == $#tags+1 ) {
      $tags[$new_position] = $new_field;
      $contents[$new_position] = $new_data;
    }
    else {
      splice(@tags, $new_position, 0, $new_field);
      splice(@contents, $new_position, 0, $new_data);
    }
  }
  # update directory and contents:
  my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader, \@tags, \@contents);

  return $new_record;
}

sub marc21_record_replace_nth_field($$$$) {
  my ( $record, $field, $new_data, $nth ) = @_;
  if ( !defined($new_data) || $new_data eq '' ||
       # Viimeinen osakenttä poistettu
       ( $field =~ /^[0-9][0-9][0-9]$/ && $field !~ /^00.$/ &&
	 length($field) == 2 ) ) {

    
    return marc21_record_remove_nth_field($record, $field, '', $nth);
  }
  #my $original_size = length($record);

  # Validate new field (well, almost)
  if ( $new_data !~ /\x1e$/ ) { $new_data .= "\x1e"; }

  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);
  my @tags = @$tags_ref;
  my @contents = @$contents_ref;

  my $new_position = $#tags+1; # last
  my $i = 0;
  for ( $i=0; $i<$new_position; $i++ ) {
    if ( $tags[$i] eq $field ) {
      if ( $nth > 0 ) {
	$nth--;
      }
      else {
	if ( $debug ) {
	  print STDERR " replace $field '$contents[$i]' with '$new_data'\n";
	}
	$contents[$i] = $new_data;
	my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader, \@tags, \@contents);

	return $new_record;
      }
    }
  }

  print STDERR "Warning! No replacement done for $field.\n";
  return $record;
}

sub marc21_fix_composition($) {
  my ( $record ) = @_;

  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);
  my @tags = @$tags_ref;
  my @contents = @$contents_ref;

  my $changes = 0;
  for ( my $i=0; $i <= $#tags; $i++ ) {
    my $tmp = unicode_fixes2($contents[$i], 1);
    if ( $tmp ne $contents[$i] ) {
      $changes++;
      $contents[$i] = $tmp;
    }
  }
  if ( $changes ) {
    $record = &marc21_leader_directoryarr_fieldsarr2record($leader, \@tags, \@contents);
  }
  
  return $record;
}

sub marc21_record_replace_field($$$) {
  my ( $record, $new_field, $new_data ) = @_;
  return marc21_record_replace_nth_field($record, $new_field, $new_data, 0);
}


# remove nth $field or part of it
sub marc21_record_remove_nth_field($$$$) {
  my ( $record, $field, $subfield, $nth) = @_;

  #print STDERR "Removing $field$subfield from\n$record\n";

  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  my @tags = @$tags_ref;
  my @contents = @$contents_ref;

  my $carry_on = 1;
  my $i;
  for ( $i = 0; $carry_on && $nth >= 0 && $i <= $#tags; $i++ ) {
    #print STDERR "'$field' vs '$tags[$i]', $nth\n";
    if ( $tags[$i] eq $field ) {
      #print STDERR "HIT $field vs $tags[$i], $nth\n";
      if ( $nth == 0 ) {
	if ( $subfield ) {
	  # remove the subfield
	  if ( $contents[$i] =~ s/(\x1F$subfield[^\x1F\x1E]+)// ) {


	    # if it is the last subfield, remove the whole field
	    if ( $contents[$i] !~ /\x1F/ ) {
	      if ( $debug ) { print STDERR "Removing $field from the record\n"; }
	      splice(@contents, $i, 1);
	      splice(@tags, $i, 1);
	    }
	    else {
	      # 2013-02-07: due to a deletion, remove the now-unneeded ','
	      # (This is probably way more generic, but I need for only f400
	      # now). Mayve there should be a '.' instead?
	      if ( $field eq '400' ) {
		$contents[$i] =~ s/[, ]+$//;
	      }
	      if ( $debug ) {
		print STDERR "Removing subfield $field|$subfield ('$1'), now: '$contents[$i]'\n";
	      }
	    }

	    $carry_on = 0;
	  }
	}
	else { # remove whole field
	  if ( $debug ) { print STDERR "Removing $field from the record (no subfield)\n"; }
	  splice(@contents, $i, 1);
	  splice(@tags, $i, 1);
	  $carry_on = 0;
	}
      }
      $nth--;
    }
  }
  if ( !$carry_on ) {
    my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader, \@tags, \@contents);
    return $new_record;
  }
  print STDERR "Removal done...\n";
  return $record;
}



sub marc21_record_remove_field($$$) {
  my ( $record, $field, $subfield) = @_;
  return marc21_record_remove_nth_field($record, $field, $subfield, 0);
}

sub marc21_record_remove_fields($$$) {
  my ( $record, $field, $subfield ) = @_;

  my @fields = marc21_record_get_fields($record, $field, '');
  my $i;
  # NB! Removal of fields begins from the last!
  for ( $i=$#fields; $i >= 0; $i-- ) {
    if ( !defined($subfield) || $subfield eq '' ) {
      $record = marc21_record_remove_nth_field($record, $field, undef, $i);
    }
    else {
      my $fieldata = $fields[$i];
      $fieldata = marc21_field_remove_subfields($fieldata, $subfield);
      if ( $fieldata ne $fields[$i] ) {
	$record = marc21_record_replace_nth_field($record, $field, $fieldata, $i);
	if ( $debug ) {
	  print STDERR " SUBFIELD MAGIC: '$fields[$i]' => '$fieldata'\n";
	}
      }
    }
  }
  return $record;
}


sub marc21_is_utf8($) { # po. is_utf8
  use bytes;
  my ($val, $msg ) = @_;
  my $original_val = $val;
  my $i = 1;
  while ( $i ) {
    $i = 0;
    if ( $val =~ s/^[\000-\177]+//s ||
         $val =~ s/^([\300-\337][\200-\277])//s ||
         $val =~ s/^([\340-\357][\200-\277]{2})+//s ||
         $val =~ s/^([\360-\367][\200-\277]{3})+//s ) {
       $i=1;
    }
  }
  no bytes;
  if ( $val eq '' ) {
    return 1;
  }
#  #if ( $val !~ /^([\000-\177\304\326\344\366])+$/s ) {
#  my $reval = $val;
#  $reval =~ s/[\000-177]//g;
#  unless ( $reval =~ /^[\304\326\344\366]+$/ ) {
#    $i = ord($val);
#    my $c = chr($i);
#    #print STDERR "$msg: UTF8 Failed: '$c'/$i/'$val'\n$original_val\n";
#
#  }
  return 0;
}

sub marc21_length($) {
  my $data = $_[0];

  return length($data);

#  my $l = $data =~ tr/\x1D\x1E\x1F//d;
#  return $l + bytes::length(Encode::encode('UTF-8', $data));

##  if ( length($data) !=  bytes::length($data) ) {
##    print STDERR "\nCHECK LENGTHS...\n$data\n", "LEN\t", length($data), "\tLEN B\t", bytes::length($data), "\n\n";
##  }
##  return $l + bytes::length($data);
  
}

sub string_replace($$$) {
  my ( $string, $find, $replace ) = @_;
  my $original_string = $string;
    
  my $pos = index($string, $find);
  
  while($pos > -1) {
    substr($string, $pos, length($find), $replace);
    $pos = index($string, $find, $pos + length($replace));
  }


  return $string;
}


sub unicode_strip_diacritics($) {
  my $str = $_[0];

  $str =~ s/́//g;
  $str =~ s/̆//g;   $str =~ s/̌//g;


  $str =~ s/̂//g;
  $str =~ s/̀//g;
  $str =~ s/̈//g; $str =~ s/̈//g;
  $str =~ s/̊//g;

  $str =~ s/̄//g;

  $str =~ s/̧//g;
  $str =~ s/̣//g;

  $str =~ s/̃//g;

  return $str;
}

sub unicode_fixes2($$) {
  # Finns use char+diacritic version of various characters
  my ( $str, $warn ) = @_;
  my $orig_str = $str;

  my @debug_stack = ();
  # a #
  if ( $str =~ s/ầ/ầ/g ) { $debug_stack[$#debug_stack+1] = "a-multiple"; }

  if ( $str =~ s/á/á/g ) { $debug_stack[$#debug_stack+1] = "a-acute"; }
  if ( $str =~ s/Á/Á/g ) { $debug_stack[$#debug_stack+1] = "A-acute"; }
  if ( $str =~ s/ă/ă/g ) { $debug_stack[$#debug_stack+1] = "a-breve"; }
  if ( $str =~ s/â/â/g ) { $debug_stack[$#debug_stack+1] = "a-creve"; }
  if ( $str =~ s/à/à/g ) { $debug_stack[$#debug_stack+1] = "a-grave"; }
  if ( $str =~ s/ä/ä/g ) { $debug_stack[$#debug_stack+1] = "a-umlaut"; }


  if ( $str =~ s/å/å/g ) { $debug_stack[$#debug_stack+1] = "a-ring"; }
  # A #

  if ( $str =~ s/À/À/g ) { $debug_stack[$#debug_stack+1] = "A-grave"; }
  if ( $str =~ s/Ä/Ä/g ) { $debug_stack[$#debug_stack+1] = "A-umlaut"; }

  if ( $str =~ s/Å/Å/g ) { $debug_stack[$#debug_stack+1] = "A-ring"; }

  if ( $str =~ s/ā/ā/g ) { $debug_stack[$#debug_stack+1] = "a-line"; }


  if ( $str =~ s/č/č/g  ) { $debug_stack[$#debug_stack+1] = "c-caron"; }

  if ( $str =~ s/ç/ç/g ) { $debug_stack[$#debug_stack+1] = "c-cedilla"; }

  if ( $str =~ s/ḍ/ḍ/g ) { $debug_stack[$#debug_stack+1] = "d-dot"; }
  # e #
  if ( $str =~ s/é/é/g ) { $debug_stack[$#debug_stack+1] = "e-acute"; }
  if ( $str =~ s/É/É/g ) { $debug_stack[$#debug_stack+1] = "E-acute"; }
  if ( $str =~ s/è/è/g ) { $debug_stack[$#debug_stack+1] = "e-grave"; }
  if ( $str =~ s/È/È/g ) { $debug_stack[$#debug_stack+1] = "E-grave"; }
  if ( $str =~ s/ê/ê/g ) { $debug_stack[$#debug_stack+1] = "e-circum"; }
  if ( $str =~ s/ē/ē/g ) { $debug_stack[$#debug_stack+1] = "e-line"; }
  if ( $str =~ s/ė/ė/g ) { $debug_stack[$#debug_stack+1] = "e-upper dot"; }
  if ( $str =~ s/ĕ/ĕ/g  ) { $debug_stack[$#debug_stack+1] = "e-breve"; }
  if ( $str =~ s/ë/ë/g ) { $debug_stack[$#debug_stack+1] = "e-umlaut"; }
  if ( $str =~ s/Ë/Ë/g ) { $debug_stack[$#debug_stack+1] = "E-umlaut"; }

  # select count(*) from patron where patron_pin is null;
  # update patron set patron_pin='11111' where patron_pin is null;
  if ( 0 && $str =~ s/ǧ/ǧ/g ) { $debug_stack[$#debug_stack+1] = "g-carot"; }

  if ( $str =~ s/ğ/ğ/g  ) { $debug_stack[$#debug_stack+1] = "g-breve"; }

  if ( $str =~ s/í/í/g ) { $debug_stack[$#debug_stack+1] = "i-acute"; }
  if ( $str =~ s/ì/ì/g ) { $debug_stack[$#debug_stack+1] = "i-grave"; }
  if ( $str =~ s/ī/ī/g ) { $debug_stack[$#debug_stack+1] = "i-line"; }
  if ( $str =~ s/î/î/g ) { $debug_stack[$#debug_stack+1] = "i-creve"; }
  if ( $str =~ s/ï/ï/g ) { $debug_stack[$#debug_stack+1] = "i-umlaut"; }

  if ( $str =~ s/ṇ/ṇ/g ) {
    $debug_stack[$#debug_stack+1] = "n-dot";
  }

  if ( $str =~ s/ñ/n̄/g ) {
    $debug_stack[$#debug_stack+1] = "n-line";
  }

  if ( $str =~ s/ṅ/ṅ/g ) {
    $debug_stack[$#debug_stack+1] = "n-upper dot";
  }

  if ( $str =~ s/ó/ó/g ) { $debug_stack[$#debug_stack+1] = "o-acute"; }

  if ( $str =~ s/ò/ò/g ) { $debug_stack[$#debug_stack+1] = "o-grave"; }


  if ( $str =~ s/õ/õ/g ) {
    $debug_stack[$#debug_stack+1] = "o-tilde";
  }

  # wīlwīl'tĕlhuku
  # wīlwīl'tĕlhuku

  if ( $str =~ s/ō/ō/g ) { $debug_stack[$#debug_stack+1] = "o-line"; }
  if ( $str =~ s/ô/ô/g ) { $debug_stack[$#debug_stack+1] = "o-^"; }
  if ( $str =~ s/ŏ/ŏ/g  ) { $debug_stack[$#debug_stack+1] = "o-breve"; }

  if ( $str =~ s/ś/ś/g ) { $debug_stack[$#debug_stack+1] = "s-acute"; }
  if ( $str =~ s/ş/ş/g ) { $debug_stack[$#debug_stack+1] = "s-cedilla"; }
  if ( $str =~ s/š/š/g  ) { $debug_stack[$#debug_stack+1] = "s-caron"; }

  if ( $str =~ s/ṭ/ṭ/g ) { $debug_stack[$#debug_stack+1] = "t-dot"; }

  if ( $str =~ s/ú/ú/g ) { $debug_stack[$#debug_stack+1] = "u-acute"; }
  if ( $str =~ s/Ú/Ú/g ) { $debug_stack[$#debug_stack+1] = "U-acute"; }
  if ( $str =~ s/ŭ/ŭ/g  ) { $debug_stack[$#debug_stack+1] = "u-breve"; }
  if ( $str =~ s/û/û/g ) { $debug_stack[$#debug_stack+1] = "u-creve"; }
  if ( $str =~ s/ù/ù/g ) { $debug_stack[$#debug_stack+1] = "u-grave"; }
  if ( $str =~ s/Ù/Ù/g ) { $debug_stack[$#debug_stack+1] = "U-grave"; }
  if ( $str =~ s/ū/ū/g ) { $debug_stack[$#debug_stack+1] = "u-line"; }
  if ( $str =~ s/ü/ü/g ) { $debug_stack[$#debug_stack+1] = "u-umlaut"; }
  if ( $str =~ s/Ü/Ü/g ) { $debug_stack[$#debug_stack+1] = "U-umlaut"; }


  if ( 0 && $str =~ s/XXX/ǔ/g ) { # ǎ breve ǔ
    $debug_stack[$#debug_stack+1] = "u-carot";
  }






  # Ei tunnu tällä korjaantuvan...
  if ( $str =~ s/ý/ý/g ) { $debug_stack[$#debug_stack+1] = "y-acute"; }
  if ( $str =~ s/ỳ/ỳ/g ) { $debug_stack[$#debug_stack+1] = "y-grave"; }
  if ( $str =~ s/ÿ/ÿ/g ) { $debug_stack[$#debug_stack+1] = "y-umlaut"; }

  if ( $str =~ s/ž/ž/g  ) { $debug_stack[$#debug_stack+1] = "z-caron"; }

  # Mystisestä syystä nämä aiheuttivat virheen s///-muodossa.
  # Tutki myöhemmin paremmin...
  $orig_str = $str;
  $str = &string_replace($str, "ö", "ö");
  if ( $str ne $orig_str ) { $debug_stack[$#debug_stack+1] = "o-umlaut"; }


  $orig_str = $str;
  $str = &string_replace($str, "Ö", "Ö");
  if ( $str ne $orig_str ) {
    $debug_stack[$#debug_stack+1] = "O-umlaut";
  }

  if ( $warn && $#debug_stack > -1 ) {
    print STDERR "Fixed ", join(", ", @debug_stack), " in '$str'...\n";
  }
  
  return $str;
}

sub unicode_fixes($) {
  my $str = $_[0];
  return unicode_fixes2($str, 1);
}

sub encoding_fixes($) {
  my $str = $_[0];
  $str =~ s/\&amp;/\&/g;
  $str =~ s/\&apos;/'/g;
  $str =~ s/\&lt;/</g;
  $str =~ s/\&gt;/>/g;
  $str =~ s/\&quot;/\'/g;

  $str = &unicode_fixes($str);

  return $str;
}


sub html_escapes($) {
  my $str = $_[0];
  if ( $str =~ /[<>&]/ ) { # trying to optimize...
    $str =~ s/\&/\&amp;/g;
    $str =~ s/</\&lt;/g;
    $str =~ s/>/\&gt;/g;
  }
  return $str;
}

sub marc21_record_is_deleted($) {
  my $record = shift();
  if ( $record =~ /^.....d/ ) {
    return 1;
  }
  # Aleph-juttuja:
  my @sta = marc21_record_get_fields($record, 'STA', 'a');
  for ( my $i=0; $i <= $#sta; $i++ ) {
    if ( defined($sta[$i]) && $sta[$i] eq 'DELETED' ) {
      return 1;
    }
  }
  my @del = marc21_record_get_fields($record, 'DEL', undef);
  if ( $#del > -1 ) {
    return 1;
  }

  return 0;
}

sub nvolk_marc212oai_marc($) {
  my $record = shift();
  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  my @tags = @$tags_ref;
  my @contents = @$contents_ref;

  my $n_tags = $#tags + 1;
  if ( $n_tags == 0 ) { die(); }



  my $clean_up = ( $record =~ /[\x00-\x08\x0B\x0C\x0E-\x1C]/ ? 1 : 0 );
  my $clean_up2 = ( $record =~ /[<>&]/ ? 1 : 0 );

  my $output = "<record xmlns=\"http://www.loc.gov/MARC21/slim\">\n<leader>$leader</leader>\n";

  my $id = '???'; # marc21_record_get_field($record, '001', undef);

  for ( my $i=0; $i < $n_tags; $i++ ) {
    my $tag = $tags[$i];
    my $content = $contents[$i];
    if ( $tag =~ /^00[1-9]$/ ) {
      if ( $tag eq "001" ) { $id = $content; }
      if ( $content =~ /[\x00-\x08\x0B\x0C\x0E-\x1F]/ ) {
	print STDERR "WARNING: Removing wierd characters from '$content' (record: $id, tag: $tag) \n";
	$content =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
	$clean_up = 1;
      }
      # Normalisoidaanko entiteetit, ei niitä pitäisi olla, mutta
      # toisaalta kiinteämittaisia kenttiä on niin vähän, ettei tehojutut
      # haittaa...
      if ( $clean_up2 ) {
	$content = html_escapes($content);
	$clean_up = 1;
      }
      $output .= "<controlfield tag=\"$tag\">$content</controlfield>\n";
    }
    else {
      my $sep = substr($content, 2, 1);
      if ( $sep eq "\x1F" ) {
	my $i1 = substr($content, 0, 1);
	my $i2 = substr($content, 1, 1);
	# TODO: indicator sanity checks?
	$content = substr($content, 3); # the rest: subfield contents

	# Tee osakentät:
	my $subfield_contents = '';
	my @subs = split(/\x1F/, $content);
	my $n_subs = $#subs+1;

	for ( my $j=0; $j < $n_subs; $j++ ) {
	  my $sf = $subs[$j];
	  if ( length($sf) ) {
	    # I assume that my earlier /^(.)(.*)$/ was way slower than
	    # the substr()-based solution below:
	    my $sf_code = substr($sf, 0, 1); # first char: subfield code
	    my $sf_data = substr($sf, 1); # the rest: subfield contents
	    if ( $sf_code =~ /^[a-z0-9]$/ ) {
	      if ( $sf_data =~ /[\x00-\x08\x0B\x0C\x0E-\x1F]/ ) {
		print STDERR "WARNING: Removing wierd characters from '$sf_data' (record: $id, tag: $tag$sf_code)\n";
		$sf_data =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
	      }
	      if ( $clean_up2 ) {
		$sf_data = html_escapes($sf_data);
	      }
	      $subfield_contents .= " <subfield code=\"$sf_code\">".$sf_data."</subfield>\n";
	    }
	    else {
	      $clean_up = 1;
	      print STDERR "WARNING: Skipping subfield '$sf_code' (record $id)\n";
	    }
	  }
	}
	if ( length($subfield_contents) ) {
	  $output .= "<datafield tag=\"$tag\" ind1=\"$i1\" ind2=\"$i2\">\n" .
	    $subfield_contents .
	    "</datafield>\n";
	}
      }
      else {
	print STDERR "WARNING: Skipping subfield '$content' due to erronous marc21 (record $id)\n";
	$clean_up = 1;
      }
    }
  }

  $output .= "</record>\n";
  # Pitääkö nämä klaarata täällä vai missä?
  $output =~ s/'/&#39;/g;
  return $output;
}


sub nvolk_marc212aleph($) {
  # TODO: optimize the code here as well, see nvolk_marc212oai_marc($).
  my $record = shift();
  $record = marc21_record_target_aleph($record);
  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  my @tags = @$tags_ref;
  my @contents = @$contents_ref;

  my $output = '<?xml version = "1.0" encoding = "UTF-8"?>
<find-doc 
  xmlns="http://www.loc.gov/MARC21/slim" 
  xmlns:slim="http://www.loc.gov/MARC21/slim" 
  xmlns:oai="http://www.openarchives.org/OAI/1.1/oai_marc">
  <record>
    <metadata>
      <oai_marc>
';

  $output .= "        <fixfield id=\"LDR\">" . $leader . "</fixfield>\n";
  my $i;
  for ( $i=0; $i <= $#tags; $i++ ) {
    my $tag = $tags[$i];
    my $content = $contents[$i];
    if ( $tag =~ /^00[1-9]$/ ) {
      $output .= "        <fixfield id=\"$tag\">$content</fixfield>\n";
    }
    elsif ( $content =~ s/^(.)(.)\x1F// ) {
      my $i1 = $1;
      my $i2 = $2;
      $output .= "        <varfield id=\"$tag\" i1=\"$i1\" i2=\"$i2\">\n";
      my @subs = split(/\x1F/, $content);
      for ( my $j=0; $j <= $#subs; $j++ ) {
	my $sf = $subs[$j];
	$sf =~ /^(.)(.*)$/;
	my $sf_code = $1;
	my $sf_data = $2;
	if ( $sf_data eq "" ) {
	  $output .= "          <subfield label=\"$sf_code\"/>\n";
	}
	else {
	  $output .= "          <subfield label=\"$sf_code\">".html_escapes($sf_data)."</subfield>\n";
	}
      }
      $output .= "        </varfield>\n";
    }
    else {
      die("$tag\t'$content'");
    }
  }
  if ( $i == 0 ) { die(); }
  $output .= "      </oai_marc>
    </metadata>
  </record>
</find-doc>
";
  return $output;
}

sub nvolk_oai_marc2marc21($) {
  # FFS! XML::XPath converts perfectly valid utf-8 (bytes) to a "string".
  # NB! Makes too many assumptions with regexps... Needs improving!
  my $xml = shift();

  my $leader1 = undef;
  my @tags1 = ();
  my @contents1 = ();


  if ( 1 ) {
    my $record = &xml_get_first_instance($xml, 'record');
    $record = &xml_get_first_instance($record, 'oai_marc');
    $record = &only_contents($record);
    my $proceed = 1;
    while ( $proceed ) {
      $record = &trim($record);
      $proceed = 0;

      if ( !defined($leader1) && $record =~ s/^<fixfield id=\"LDR\">([^<]+)<\/fixfield>\s*//s ) {
	$leader1 = $1;
	$leader1 =~ s/\#/ /g; # TAV2-data, Mintun bugiraportti, Melinda 7322871:
	$proceed = 1;
      }
      elsif ( $record =~ s/^<fixfield id=\"(...)\">([^<]+)<\/fixfield>\s*//s ) {
	my $tag = $1;
	my $content = $2;
	$content =~ s/\#/ /g; # TAV2-data, Mintun bugiraportti, Melinda 7322871:
	push(@tags1, $tag);
	push(@contents1, $content);
	$proceed = 1;
      }
      elsif ( $record =~ s/^<varfield id=\"(...)\" i1=\"(.)\" i2=\"(.)\">\s*<\/varfield>\s*//s ) {
	print STDERR "TAG $1 has no content. Not bringing it along...\n";
	$proceed = 1;
      }
      elsif ( $record =~ /^<varfield id=\"(...)\" i1=\"(.)\" i2=\"(.)\">/ ) {
	my $tag = $1;
	my $ind1 = $2;
	my $ind2 = $3;
	my $str = '';
	my $varfield = &xml_get_first_instance($record, 'varfield');
	$record = &remove_data_from_xml($record, $varfield);

	$varfield = &only_contents($varfield);

	my $proceed2 = 1;
	while ( $proceed2 ) {
	  $varfield = &trim($varfield);
	  $proceed2 = 0;
	  if ( $varfield !~ /\S/ ) { }
	  elsif ( $varfield =~ s/^<subfield label=\"(.)\">(.*?)<\/subfield>\s*// ) {
	    my $sfcode = $1;
	    my $sfvalue = $2;
	    if ( !marc21_is_utf8($sfvalue) ) {
	      print STDERR "Encoding '$sfvalue' to ";
	      die();
	      $sfvalue = Encode::encode('UTF-8', $sfvalue);
	      print STDERR "'$sfvalue'\n";
	    }

	    $str .= "\x1F${sfcode}${sfvalue}";
	    $proceed2 = 1;
	  }
	  else {
	    die($varfield);
	  }
	}

	if ( $str ne '' ) {
	  $str = &encoding_fixes($str);
	  push(@tags1, $tag);
	  push(@contents1, "$ind1$ind2$str");
	  $proceed = 1;
	}
	else {
	  die("TAG $tag\n$record\nTAG $tag");
	  #die($record);
	}
      }
      elsif ( $record =~ /\S/ ) {
	die("Unhandled stuff: ".$record);
      }
    }

    if ( $leader1 && $#tags1 > -1 ) {
      my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader1, \@tags1, \@contents1);
      return $new_record;
    }
    print STDERR "$leader1\n$#tags1 tags\n";
    die("TODO: TEST");
  }
  
  die("KESKEN");

  my $xp = XML::XPath->new( $xml );
  my $nodeset = $xp->find('/present/record/metadata/oai_marc');
  my $leader = undef;
  my @tags = ();
  my @contents = ();

  my %skipped;

  foreach my $node ( $nodeset->get_nodelist ) {

    my $contents = XML::XPath::XMLParser::as_string($node);
    # print "FOO: $contents";
    my $xpp = XML::XPath->new($contents);
    my $nodeset2 = $xpp->find('/oai_marc/*');
    foreach my $node2 ( $nodeset2->get_nodelist ) {
      my $contents2 = XML::XPath::XMLParser::as_string($node2);
      if ( !marc21_is_utf8($contents2) ) {
	$contents2 = Encode::encode('UTF-8', $contents2);
      }

      if ( $contents2 =~ /^<fixfield id=\"(...)\">([^<]+)<\/fixfield>\s*$/ ) {
	my $tag = $1;
	my $content = $2;
	if ( $tag eq "LDR" ) {
	  $leader = $content;
	}
	else {
	  push(@tags, $tag);
	  push(@contents, $content);
	}
      }
      elsif ( $contents2 =~ /^<varfield id=\"(...)\" i1=\"(.)\" i2=\"(.)\">/ ) {
	my $tag = $1;
	my $ind1 = $2;
	my $ind2 = $3;
	my $str = "";
	my $xppp = XML::XPath->new($contents2);
	my $nodeset3 = $xppp->find('/varfield/subfield');
	foreach my $node3 ( $nodeset3->get_nodelist ) {
	  #my $contents3 = Encode::encode('UTF-8', XML::XPath::XMLParser::as_string($node3));
	  my $contents3 = XML::XPath::XMLParser::as_string($node3);
	  if ( !marc21_is_utf8($contents3) ) {
	    $contents3 = Encode::encode('UTF-8', $contents3);
	  }

	  print "FOO: $contents3\n";
	  if ( $contents3 =~ /^<subfield label=\"(.)\" \/>\s*$/ ) {
	    my $sfcode = $1;
	    if ( 1 ) { # Säilytä tyhjä
	      $str .= "\x1F${1}";
	    }
	    else {
	      if ( !defined($skipped{"$tag$sfcode"}) ) {
		print STDERR " $tag: skip empty subfield '$tag$sfcode' (warn only once)\n";
		$skipped{"$tag$sfcode"} = 1;
	      }
	    }
	    # print STDERR "'$contents2'\n";
	  }
	  elsif ( $contents3 =~ /^<subfield label="(.)">([^<]+)<\/subfield>\s*$/ ) {
	    $str .= "\x1F${1}${2}";
	  }
	  else {
	    die();
	  }
	}
	if ( $str ne '' ) {
	  $str = &encoding_fixes($str);

	  push(@tags, $tag);
	  push(@contents, "$ind1$ind2$str");
	}
	else {
	  die("No content");
	}
      }
    }
    if ( $leader && $#tags > -1 ) {
      my $i;

      for ( $i=0; $i<=$#tags;$i++ ) {
	print STDERR "NV$i\t$tags[$i]\t$contents[$i]\n";
      }

      my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader, \@tags, \@contents);
      #exit();
      return $new_record;
    }
  }

  die();


}

sub nvolk_split_marcxml($) {

  my $xml = shift();
  my @arr = ();

  my $start;
  my $end;

  my $end_tag_length = length("</record>");

  if ( $xml =~ s|(<record(( [^>]+)+)>)|<record>|g ) {
    print STDERR "Simplified $1 as <record>\n";
  }
  while ( ($start = index($xml, '<record>') ) ) {
    $xml = substr($xml, $start);
    $end = index($xml, '</record>');
    print STDERR "FOO START $start END $end\n";
    if ( $end < 0 ) {
      return @arr;
    }
    $end += $end_tag_length;
    my $elem = substr($xml, 0, $end);
    push(@arr, $elem);
    $xml = substr($xml, $end);
  }
  return @arr;


  if ( 0 ) { # corrupts charset! don't use!
    my $xp = XML::XPath->new( $xml );
    # Using // as we have some partial files from mets...
    my $nodeset = $xp->find('//record');
    foreach my $node ( $nodeset->get_nodelist ) {
      my $contents = XML::XPath::XMLParser::as_string($node);
      push(@arr, $contents);
    }
    return @arr;
  }
}

sub xml_get_first_instance($$) {
  my ( $data, $tag ) = @_;
  if ( $data =~ /(<$tag(\s[^>]*)?>)/s ) {

    my $target = $1;
    #print STDERR "Found '$target'\n";
    my $start = index($data, "$target");
    if ( $start < 0 ) { die(); }
    # TODO: handle <foo attr="s" />
    my $len;
    if ( $target =~ /\/>$/ ) {
      $len = length($target);
    }
    else {

      $target = "</$tag>";
      #print STDERR "Looking for '$target'\n";


      my $end = index($data, $target);
      if ( $end < $start ) { die("DATA:".$data); }
      $len = $end - $start + length($target);
    }
    my $contents = substr($data, $start, $len);

    #print STDERR "CON $contents CON";
    return $contents;
  }

  return undef;
}

sub only_contents($) {
  my $xml = $_[0];
  $xml =~ s/^\s*<.*?>\s*//s or die("OC1: $xml");
  $xml =~ s/\s*<\/[^<]+>\s*$//s or die("OC2: $xml");
  return $xml;
}

sub remove_data_from_xml($$) {
  my ( $str, $stuff ) = @_;
  my $i = index($str, $stuff);
  if ( $i < 0 ) { return $str; }
  substr($str, $i, length($stuff)) = "";
  return $str;
}

sub trim($) {
  my $data = $_[0];
  $data =~ s/^\s*//s;
  $data =~ s/\s*$//s;
  return $data;
}


sub nvolk_marcxml2marc21($) {
  # NB! Return but one (first) record
  # FFS! XML::XPath converts perfectly valid utf-8 (bytes) to a "string".
  # NB! Makes too many assumptions with regexps... Needs improveing!
  my $xml = shift();

  my $leader1 = undef;
  my @tags1 = ();
  my @contents1 = ();

  my $leader2 = undef;
  my @tags2 = ();
  my @contents2 = ();

  my $record = &xml_get_first_instance($xml, 'record');
  $record = &only_contents($record);
  print STDERR "GOT RECORD '$record'\n";
  # PROCESS LEADER:
  my $ldr = &xml_get_first_instance($record, 'leader');
  if ( $ldr ) {
    $record = &remove_data_from_xml($record, $ldr);
    $ldr = &only_contents($ldr);
    $leader1 = $ldr;
    $leader1 =~ s/\#/ /g; # TAV2-data, Mintun bugiraportti, Melinda 7322871:
  }
  $record = &trim($record);
  
  my $proceed = 1;
  while ( $proceed ) {
    $record = &trim($record);
    $proceed = 0;
    if ( $record =~ s/^<controlfield tag=\"(...)\">([^<]+)<\/controlfield>\s*//s ) {
      my $tag = $1;
      my $content = $2;
      
      $content =~ s/\#/ /g; # TAV2-data, Mintun bugiraportti, Melinda 7322871:
      #print STDERR "GOT CONTROLFIELD $tag: '$content'\n";
      push(@tags1, $tag);
      push(@contents1, $content);
      $proceed = 1;
    }
    elsif ( $record =~ /^<datafield tag=\"(...)\" ind1=\"(.)\" ind2=\"(.)\">/ ) {

      my $tag = $1;
      my $ind1 = $2;
      my $ind2 = $3;
      my $str = '';
      my $datafield = &xml_get_first_instance($record, 'datafield');

      print STDERR "GOT DATAFIELD $tag i1 '$ind1' i2 '$ind2'\n";
      #print STDERR "DF v1 '$datafield'\n";
      $record = &remove_data_from_xml($record, $datafield);
      $datafield = &only_contents($datafield);
      #print STDERR "DF v2 '$datafield'\n";
      my $proceed2 = 1;
      while ( $proceed2 ) {
	$datafield = &trim($datafield);
	print STDERR "DATAFIELD: '$datafield'\n";
	$proceed2 = 0;
	if ( $datafield !~ /\S/ ) { }
	elsif ( $datafield =~ s/^<subfield code=\"(.)\">(.*?)<\/subfield>\s*// ) {
	  my $sfcode = $1;
	  my $sfvalue = $2;
	  if ( 0 && !marc21_is_utf8($sfvalue) ) {
	    $sfvalue = Encode::encode('UTF-8', $sfvalue);
	  }
	  
	  $str .= "\x1F${sfcode}${sfvalue}";
	  #print STDERR "IS NOW '$str'\n";
	  $proceed2 = 1;
	}
	else {
	  die($datafield);
	}
      }
      if ( $str ne '' ) {
	$str = &encoding_fixes($str);
	print STDERR "NVV $tag $ind1 $ind2 '$str'\n";
	push(@tags1, $tag);
	push(@contents1, "$ind1$ind2$str");
	$proceed = 1;
      }
      else {
	die();
      }
      
    }
  }

  if ( $leader1 && $#tags1 > -1 ) {
    my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader1, \@tags1, \@contents1);
    print STDERR marc21_debug_record($new_record, "NEW MARCXML IMPORT");
    #exit();
    return $new_record;
  }

  die("LEFT: '$record'");
  #print STDERR marc21_debug_record($new_record, "NEW v2");
}

sub marc21_record_get_publication_country($) {
  my $record = $_[0];
  my $f008 = marc21_record_get_field($record, '008', '');
  if ( $f008 ) {
    return substr($f008, 15, 3);
  }
  return 'xx ';
}

sub marc21_record_get_publication_language($) {
  my $record = $_[0];
  my $f008 = marc21_record_get_field($record, '008', '');
  if ( $f008 ) {
    return substr($f008, 35, 3);
  }
  return '   ';
}

sub marc21_record_get_publication_year_008($) {
  my $record = $_[0];
  my $f008 = marc21_record_get_field($record, '008', '');
  if ( defined($f008) ) {
    return substr($f008, 7, 4);
  }
  return 'uuuu';
}

sub marc21_record_get_publication_year {
    my $record = $_[0];
    my $ydebug = 1;
    my $y008 = marc21_record_get_publication_year_008($record);
    if ( $y008 =~ /^[0-9]{4}$/ ) {
	return $y008;
    }
    #print STDERR " Warninging: 008 fail failed: '$year'\n";
    my $cand = marc21_record_get_field($record, '260', 'c');
    if ( defined($cand) && $cand =~ /^\D*([0-9]{4})\D*$/ ) {
	my $y260 = $1;
	my $id = marc21_record_get_field($record, '001', undef);
	print STDERR "$id\t260\$c '$cand' overrides 008 '$y008'\n";
	return $y260;
    }

    my @cands = marc21_record_get_fields($record, '264', undef);
    for ( my $i=0; $i <= $#cands; $i++ ) {
	my $f = $cands[$i];
	if ( defined($f) && $f =~ /^.1/ ) {
	    $cand = marc21_field_get_subfield($f, 'c');

	    if ( defined($cand) && $cand =~ /^\D*([0-9]{4})\D*$/ ) {
		my $y264 = $1;
		my $id = marc21_record_get_field($record, '001', undef);
		if ( $y008 ne 'uuuu'&& $y008 ne '    ' ) {
		  print STDERR "$id\t264 I2=1\$c '$cand' overrides 008 '$y008'\n";
		}
		return $y264;
	    }
	}
    }

    for ( my $i=0; $i <= $#cands; $i++ ) {
	my $f = $cands[$i];
	if ( defined($f) && $f =~ /^.4/ ) {
	    $cand = marc21_field_get_subfield($f, 'c');

	    if ( $cand =~ /^\D*([0-9]{4})\D*$/ ) {
		my $y264 = $1;
		my $id = marc21_record_get_field($record, '001', undef);
		print STDERR "$id\t264 I2=4\$c '$cand' overrides 008 '$y008'\n";
		return $y264;
	    }
	}
    }

    return $y008;
}

# Tämä ei kuuluisi tänne, mutta olkoon...
sub _publisher_b($) {
  my $field = $_[0];
  my $b = marc21_field_get_subfield($field, 'b');
  if ( defined($b) && $b =~ /\S/ ) {
    if ( $b !~ /tuntematon/i ) {
      $b =~ s/( *:|,)$//;
      return $b;
    }
  }
  return undef;
}

sub marc21_record_get_publisher_field($) {
  my $record = $_[0];
  my $publisher = marc21_record_get_field($record, '260', undef);

  my @cands = marc21_record_get_fields($record, '264', undef);

  for ( my $i=$#cands; $i >= 0; $i-- ) {
    my $cand = $cands[$i];
    if ( $cand !~ /^.1/ ) {
      splice(@cands, $i, 1)
    }
  }

  # Käytä 260-kenttää vain jos 264 on tyhjä:
  if ( defined($publisher) ) {
    if ( $#cands == -1 && defined(_publisher_b($publisher)) ) {
      return $publisher;
    }
  }

  for ( my $i=0; $i <= $#cands; $i++ ) {
    my $cand = $cands[$i];
    if ( defined(_publisher_b($cand)) ) {
      return $cands[$i];
    }
  }

  if ( $#cands > -1 ) { return $cands[0]; }
  return undef;
}


sub marc21_record_get_publisher_new($) {
  my $record = $_[0];

  my $publisher_data = marc21_record_get_publisher_field($record);

  if ( defined($publisher_data) ) {
    print STDERR " '$publisher_data'\n";
    my $b = marc21_field_get_subfield($publisher_data, 'b');
    if ( defined($b) && $b !~ /tuntematon/i ) {
      $b =~ s/( *:|,)$//;
      return $b;
    }
  }
  return undef;
}

sub marc21_record_get_publisher_old($) {
  my $record = $_[0];

  # old version
  my $publisher = marc21_record_get_field($record, '260', 'b');

  if ( defined($publisher) && $publisher =~ /\S/ ) {
    if ( $publisher !~ /tuntematon/i ) {
      $publisher =~ s/( *:|,)$//;
      return $publisher;
    }
  }
  my @cands = marc21_record_get_fields($record, '264', undef);
  for ( my $i=0; $i <= $#cands; $i++ ) {
    if ( $cands[$i] =~ /^.1/ ) {
      $publisher = marc21_field_get_subfield($cands[$i], 'b');
      if ( defined($publisher) && $publisher =~ /\S/ &&
	   $publisher !~ /tuntematon/i ) {
	$publisher =~ s/( *:|,) *$//;
	return $publisher;
      }
    }
  }
  return undef;
}

sub marc21_record_get_publisher($) {
  my $record = $_[0];
  my $new = marc21_record_get_publisher_new($record);
  return $new;
  my $old = marc21_record_get_publisher_old($record);
  
  
  if ( !defined($old) && !defined($new) ) {
    return undef;
  }
  
  if ( $old ne $new ) {
    die("'$old' vs '$new'");
  }
  return $old;
}

sub marc21_record_get_title($) {
  my $record = $_[0];
  my $f245 = marc21_record_get_field($record, '245', undef);
  my $a = marc21_field_get_subfield($f245, 'a');
  my $b = marc21_field_get_subfield($f245, 'b');
  if ( defined($b) ) {
    $a .= " " . $b;
  }
  my $n = marc21_field_get_subfield($f245, 'n');
  if ( defined($n) ) {
    $a .= " " . $n;
  }
  $a =~ s/\s*[\.\/:]\s*$//;

  return $a;
}

sub marc21_record_get_title_and_author($) {
  my $record = $_[0];
  my $f245 = marc21_record_get_field($record, '245', undef);
  my $a = marc21_field_get_subfield($f245, 'a');
  my $b = marc21_field_get_subfield($f245, 'b');
  if ( defined($b) ) {
    $a .= " " . $b;
  }
  my $n = marc21_field_get_subfield($f245, 'n');
  if ( defined($n) ) {
    $a .= " " . $n;
  }
  my $c = marc21_field_get_subfield($f245, 'c');
  if ( defined($c) ) {
    $a .= " " . $c;
  }

  $a =~ s/\s*[\.\/]$//;

  return $a;
}


sub marc21_record_get_place_of_publication($) {
  my $record = $_[0];
  # ennen RDA-konversiota:
  my $place_of_pub = marc21_record_get_field($record, '260', 'a');
  if ( defined($place_of_pub) && $place_of_pub =~ /\S/ ) {
    $place_of_pub =~ s/( *:|,) *$//;
    if ( $place_of_pub !~ /tuntematon/i ) {
      return $place_of_pub;
    }
  }
  # RDA-konversion jälkeen:
  my @cands = marc21_record_get_fields($record, '264', undef);
  for ( my $i=0; $i <= $#cands; $i++ ) {
    if ( $cands[$i] =~ /^.1/ ) {
      $place_of_pub = marc21_field_get_subfield($cands[$i], 'a');
      if ( defined($place_of_pub) && $place_of_pub =~ /\S/ ) {
	$place_of_pub =~ s/( *:|,) *$//;
	if ( $place_of_pub !~ /tuntematon/i ) {
	  return $place_of_pub;
	}
      }
    }
  }
  return undef;
}

sub marc21_record_get_date_of_publication($) {
  my $record = $_[0];
  # ennen RDA-konversiota:
  my $place_of_pub = marc21_record_get_field($record, '260', 'c');
  if ( defined($place_of_pub) && $place_of_pub =~ /\S/ ) {
    $place_of_pub =~ s/,$//;
    return $place_of_pub;
  }
  # RDA-konversion jälkeen:
  my @cands = marc21_record_get_fields($record, '264', undef);
  for ( my $i=0; $i <= $#cands; $i++ ) {
    if ( $cands[$i] =~ /^.1/ ) {
      $place_of_pub = marc21_field_get_subfield($cands[$i], 'c');
      if ( defined($place_of_pub) && $place_of_pub =~ /\S/ ) {
	$place_of_pub =~ s/,$//;
	return $place_of_pub;
      }
    }
  }
  return undef;
}

sub marc21_record_target_aleph($) {
  # Aleph haluaa kiinteämittaisten kenttien tyhjät caretteina...
  my $record = $_[0];
  $record =~ s/^(.{24})//;
  my $leader = $1;
  $leader =~ s/#/\^/g; # Hack, some data contain this bug
  $leader =~ s/ /\^/g;
  $record = $leader . $record;
  my ( $i, $j );
  for ( $i = 1; $i < 10; $i++ ) {
    my $tag = "00$i";
    my @fields = &marc21_record_get_fields($record, $tag);
    for ( $j=$#fields; $j >= 0; $j-- ) {
      if ( $fields[$j] =~ s/ /\^/g ) {
	$record = marc21_record_replace_nth_field($record, $tag, $fields[$j], $j);
      }
    }
  }
  return $record;
}


sub marc21_field_has_subfield($$$) {
  my ( $kentta, $osakentta, $arvo ) = @_;
  #print STDERR "marc21_field_has_subfield('$kentta', '$osakentta', '$arvo')\n";
  if ( !defined($osakentta) || $osakentta eq '' ) {
    #print STDERR "marc21_field_equals_field('$kentta', '$arvo')\n";
    if ( $kentta eq $arvo ) { return 1; }
    return 0;
  }

  if ( !defined($arvo) || $arvo eq '' ) {
    if ( $kentta =~ /\x1F$osakentta/ ) { return 1; }
    return 0;
  }

  my @osakenttien_arvot = marc21_field_get_subfields($kentta, $osakentta);
  for ( my $i=0; $i <= $#osakenttien_arvot; $i++ ) {
    if ( $arvo eq $osakenttien_arvot[$i] ) {
      return 1;
    }
  }
  return 0;
}

sub marc21_record_has_field($$$$) {
  #print STDERR "HF\n";
  my ( $tietue, $kentta, $osakentta, $arvo ) = @_;
  my $val = marc21_record_has_field_at($tietue, $kentta, $osakentta, $arvo);
  if ( $val == -1 ) {
    return 0;
  }
  return 1;
}


sub marc21_record_has_field_at($$$$) {
  #print STDERR "HFA\n";
  my ( $tietue, $kentta, $osakentta, $arvo ) = @_;

  my @kentat = marc21_record_get_fields($tietue, $kentta, '');

  if ( $#kentat < 0 ) {
    return -1;
  }

  if ( ( !defined($osakentta) || $osakentta eq '' ) &&
       ( !defined($arvo) || $arvo eq '' ) ) {
    # die();
    # kenttä on olemassa...
    return 1;
  }

  my $i;
  for ( $i=0; $i<=$#kentat; $i++ ) {
    if ( marc21_field_has_subfield($kentat[$i], $osakentta, $arvo) ) {
      return $i;
    }
  }
  return -1;
}

sub marc21_record_remove_content($$$$) {
  my ( $tietue, $kentta, $osakentta, $arvo ) = @_;
  my @kentat = marc21_record_get_fields($tietue, $kentta, undef);

  if ( $#kentat < 0 ) {
    return 0;
  }

  if ( !defined($osakentta) ) {
    for ( my $i=$#kentat; $i>=0; $i-- ) {
      if ( $kentat[$i] eq $arvo ) {
	$tietue = marc21_record_remove_nth_field($tietue, $kentta, undef, $i);
      }
    }
    return $tietue;
  }

  die("Not implemented yet");
  return $tietue;
}

sub marc21_record_copy_missing_field($$$) {
  my ( $from, $to, $tag ) = @_;

  my @to_fields = marc21_record_get_fields($to, $tag, undef);

  if ( $#to_fields >= 0 ) {
    print STDERR "Target already has field '$tag'\n";
    return $to;
  }

  my @from_fields = marc21_record_get_fields($from, $tag, undef);

  if ( $#from_fields < 0 ) { return $to; }

  if ( $#from_fields > 0 ) {
    print STDERR "Multiple copyable $tag fields. Copying first ('$from_fields[0]).\n";
  }
  $to = &marc21_record_add_field($to, $tag, $from_fields[0]);

  return $to;
}

# Common field tricks:
sub rda040($$) {
  my $record = shift();
  my $debug = shift();
  my $f040old = &marc21_record_get_field($record, '040', '');
  my $f040rda = "  \x1FaFI-NL\x1Fbfin\x1Ferda";
  if ( $f040old ) {
    if ( $f040old =~ /^(  \x1FaFI-NL)$/ ) {
      $record = &marc21_record_replace_field($record, '040', $f040rda);
    }
    else {
      die($f040old);
    }
  }
  else {
    $record = &marc21_record_add_field($record, '040', $f040rda);
  }
  return $record;
}

sub normalize_content($$) {
  my ( $tag, $val ) = @_;
  if ( $tag =~ /^[167](00|10|11)$/ ) {
    $val =~ s/(\x1F[abcd][^\x1F]+),$/$1./;
    $val =~ s/(\x1Fa[^\x1F]+)\.\.$/$1./;
  }
  return $val;
}

sub pair_field($$$$) {
  my ( $from_field, $to_field, $tag, $sfc ) = @_;
  # poista lähteen ja vastaavat kohteen speksatut kentät:
  while ( $sfc =~ s/^([a-z0-9])// ) {
    my $key = $1;
    if ( $from_field =~ s/(\x1F$key[^\x1F]+)// ) {
      my $val1 = $1;
      if ( $to_field =~ s/(\x1F$key[^\x1F]+)// ) {
	my $val2 = $1;
	$val1 = &normalize_content($tag, $val1);
	$val2 = &normalize_content($tag, $val2);
	if ( $val1 ne $val2) {
	  return 0;
	}
      }
    }
    elsif ( $to_field =~ s/(\x1F$key[^\x1F]+)// ) {
      return 0;
    }
  }
  # kohteen jokainen kenttä pitää löytyy lähteestä, muuten fail...
  while ( $to_field =~ s/(\x1F[^\x1F]+)// ) {
    my $val2 = $1;
    if ( $from_field =~ s/(\x1F[^\x1F]+)// ) {
      my $val1 = $1;
      $val1 = &normalize_content($tag, $val1);
      $val2 = &normalize_content($tag, $val2);
      if ( $val1 ne $val2) {
	return 0;
      }
    }
  }
  return 1;

}

# Copy a subfield from target to source if other subfields are identical..
sub marc21_record_enrich_fields($$$$) {
  # used mainly for copying subfield 100$do from "better" records:
  my ( $source_record, $target_record, $field, $subfield_codes ) = @_;
  # Currently lazy version
  my @source_fields = marc21_record_get_fields($source_record, $field, undef);
  if ( $#source_fields < 0 ) {
    return $target_record;
  }
  my @orig_source_fields = @source_fields;
  
  my @target_fields = marc21_record_get_fields($target_record, $field, undef);
  my @orig_target_fields = @target_fields;

  if ( $#target_fields < 0 ) {
    return $target_record;
  }

  if ( 0 ) {
    # Clean up targets:
    for ( my $i = 0; $i <= $#target_fields; $i++ ) {
      my $sfc = $subfield_codes;
      my $cand_target_field = $target_fields[$i];
      while ( $sfc =~ s/^([a-z0-9])// ) {
	my $key = $1;
	$cand_target_field =~ s/\x1F$key[^\x1F]+//;
      }
      $target_fields[$i] = &normalize_content($field, $cand_target_field);
      print STDERR " TF$i\t'", $target_fields[$i], "'\n";
    }
    # Clean up sources
    for ( my $i = 0; $i <= $#source_fields; $i++ ) {
      my $sfc = $subfield_codes;
      my $cand_source_field = $source_fields[$i];
      while ( $sfc =~ s/^([a-z0-9])// ) {
	my $key = $1;
	$cand_source_field =~ s/\x1F$key[^\x1F]+//;
      }
      $source_fields[$i] = &normalize_content($field, $cand_source_field);
      print STDERR " SF$i\t'", $source_fields[$i], "'\n";
    }
  }

  for ( my $j = 0; $j <= $#source_fields; $j++ ) {
    my $cand_source_field = $source_fields[$j];

    for ( my $i = 0; $i <= $#target_fields; $i++ ) {
      my $cand_target_field = $target_fields[$i];
      if ( defined($cand_target_field) &&
	   pair_field($orig_source_fields[$i], $orig_target_fields[$i], $field, $subfield_codes) ) {

	$cand_source_field = $orig_source_fields[$j];
	$target_record = marc21_record_replace_nth_field($target_record, $field, $cand_source_field, $i);
	if ( $debug ) {
	  print STDERR "UPDATE $field\t'", $target_fields[$i], "' => '$cand_source_field'\n";
	}
      }
    }
  }
  return $target_record;
}

sub mfhd_record2bib_id($) {
  my ( $mfhd_record ) = @_;
  return marc21_record_get_field($mfhd_record, '004', undef);
}


sub viola_lisaa_puuteluetteloon($) {
  my ( $record ) = @_;

  my $f008 = marc21_record_get_field($record, '008', '');

  my $julkaisumaa = substr($f008, 15, 3);
  my $julkaisuvuosi = substr($f008, 7, 4);
  my $kieli = substr($f008, 37, 4);
  my $aanite = ( $record =~ /^......j/ ? 1 : 0 );
  my $skip583 = 0;

  # Ks. VIOLA-54 kommentit
  if ( $julkaisuvuosi =~ /^\d+$/ && $julkaisuvuosi < 1981 && $aanite ) {
    $skip583 = 1;
  }

  my $nf = "  \x1FaPUUTELUETT.";
  if ( !$skip583 ) {

    unless ( marc21_record_has_field($record, '583', undef, $nf) ) {
      print " Lisätään puuteluettelomerkintä 583 '$nf'\n";
      $record = marc21_record_add_field($record, '583', $nf);
    }
  }

  $nf = "  \x1FaPuuttuu kansalliskokoelmasta";
  unless ( marc21_record_has_field($record, '594', undef, $nf) ) {
    print " Lisätään puuteluettelomerkintä 594 '$nf'\n";
    $record = marc21_record_add_field($record, '594', $nf);
  }

  return $record;
}

sub is_electronic($) {
  my $record = $_[0];
  my @fields = marc21_record_get_fields($record, '007', undef);
  foreach my $field (@fields) {
    if ( $field =~ /^c/ ) { return 1; }
  }
  return 0;
}

sub is_host($) {
  my $record = $_[0];
  if ( $record =~ /^.{7}m/ ) { # [ms]?
    return 1;
  }
  return 0;
}

sub is_auth($) {
  my $record = $_[0];
  if ( $record =~ /^.{6}z/ ) {
    return 1;
  }
  return 0;
}

sub is_bib($) {
  my $record = $_[0];
  if ( $record =~ /^.{6}[acdefgijkmoprt]/ ) {
    return 1;
  }
  return 0;
}

sub is_holding($) {
  my $record = $_[0];
  if ( $record =~ /^.{6}[uvxy]/ ) {
    return 1;
  }
  return 0;
}

sub is_component_part($) {
  my $record = $_[0];
  if ( $record =~ /^.{7}[ab]/ ) {
    return 1;
  }
  return 0;
}

sub is_serial($) {
  my $record = $_[0];
  if ( $record =~ /^.{7}[bs]/ ) {
    return 1;
  }
  return 0;
}
		  

sub merge_033($) {
  # Fono-konversio saattaa luoda useita yksittäisiä:
  my $record = $_[0];
  my @fields = marc21_record_get_fields($record, '033', '');
  my $ind1is0 = 0;
  my $ind2 = undef;
  my @vals;
  for ( my $i=0; $i <= $#fields; $i++ ) {
    if ( $fields[$i] =~ /^0(.)\x1Fa([^\x1F]+)$/ ) {
      $vals[$#vals+1] = $2;
      $ind1is0++;
      if ( !defined($ind2) ) {
	$ind2 = $1;
      }
      elsif ( $1 ne $ind2 ) {
	$ind2 = ' ';
      }
    }
  }
  if ( $ind1is0 > 1 ) {
    for ( my $i=$#fields; $i >= 0; $i-- ) {
      if ( $fields[$i] =~ /^0/ ) {
	$record = marc21_record_remove_nth_field($record, '033', '', $i);
      }
    }
    $record = marc21_record_add_field($record, '033', "1${ind2}\x1Fa".join("\x1Fa", @vals));
  }
  return $record;
}


sub get_melinda_id($$) {
  my ( $bib_id, $bib_record ) = @_;
  my @fields = marc21_record_get_fields($bib_record, '035', 'a');
  my $i;
  my $melinda_id = 0;
  for ( $i=0; $i <= $#fields; $i++ ) {
    my $val = $fields[$i];
    if ( defined($val) ) {
      if ( $val =~ s/^FCC0*// || # paikalliskannasta tullut tietue
	   $val =~ s/^\(FI\-MELINDA\)0*// ) {
	if ( $val =~ /^(\d+)/ ) {
	  my $tmp = $1;
	  if ( $melinda_id ) {
	    # Joku näistä voi olla deletoituun
	    print STDERR "BIB-$bib_id\tMultiple Melinda references: ", join(", ", @fields), "\n";
	    return 0;
	  }
	  $melinda_id = $1;
	}
	else {
	  print STDERR "$bib_id\tWARNING\tCORRUPTED 035a '", $fields[$i], "'\n";
	}
      }
      elsif ( $val =~ /MELINDA/ ) {
	print STDERR "$bib_id\tWARNING\tCORRUPTED 035a '", $fields[$i], "'\n";
      }
    }
  }
  return $melinda_id;
}

sub is_isbn($) {
  my $issn = shift;
  if ( $issn =~ /^([0-9]\-?){9}[0-9X]$/ ) {
    return 1;
  }
  if ( $issn =~ /^([0-9]\-?){12}[0-9X]$/ ) {
    return 1;
  }
  return 0;
}

sub is_issn($) {
  my $issn = shift;
  if ( $issn =~ /^([0-9]{4}\-[0-9]{3}[0-9X])$/ ) {
    return 1;
  }
  return 0;
}


sub karsi_kentan_perusteella($$$$$$$) {
  my ( $tietueetP, $kentta, $osakentta, $sisalto, $poista_kaikki, $hyva_kentta, $puuttuvaa_ei_poisteta ) = @_;
  my @tietueet = @{$tietueetP};
  if ( $#tietueet < 0 ) { return @tietueet; }

  my $n_tietueet = $#tietueet+1;

  my $prefix = ( $hyva_kentta ? "LACKING " : 'CONTAINING ' );
  print STDERR "OPERATION: REMOVE RECORDS ${prefix}$kentta", ( defined($osakentta) ? "\$$osakentta" : '' ), " '$sisalto'\tN=", (1+$#tietueet), "\n";

  my @pois;
  my $n_osuma = 0;
  for ( my $i=$#tietueet; $i >= 0; $i-- ) {
    my $tietue = $tietueet[$i];
    #$pois[$i] = ( marc21_record_has_field($tietue, 'LOW', undef, "  \x1FaFENNI") ? 1 : 0 );
    $pois[$i] = 0;

    my @tietueen_kentat = marc21_record_get_fields($tietue, $kentta, $osakentta);
    my $osumat = 0;
    my $j = 0;
    for ( $j=0; $j <= $#tietueen_kentat; $j++ ) {
      my $tietueen_kentta = $tietueen_kentat[$j];
      if ( $tietueen_kentta eq $sisalto ) {
	$osumat++;
      }
    }

    if ( $j == 0 && $puuttuvaa_ei_poisteta ) {

    }
    elsif ( ( $osumat && !$hyva_kentta ) ||
	 ( !$osumat && $hyva_kentta ) ) {
      $pois[$i] = 1;
      $n_osuma++;
    }
  }

  if ( $n_osuma ) {
    if ( $n_osuma == $n_tietueet && !$poista_kaikki ) {
      if ( $hyva_kentta ) {
	print STDERR " Every record matches. Remove nothing\n";
      }
      else {
	print STDERR " NO record matches! Remove nothing\n";
      }
    }
    else {
      print STDERR " Remove $n_osuma/$n_tietueet records\n";
      for ( my $i=$#tietueet; $i >= 0; $i-- ) {
	if ( $pois[$i] ) {
	  my $id = marc21_record_get_field($tietueet[$i], '001', undef);
	  print STDERR "  Removing $id\n";
	  splice(@tietueet, $i, 1);
	}
      }
    }
  }

  if ( $#tietueet == -1 ) {
    print STDERR " NB! Poistettiin kaikki! ($sisalto)\n";
  }
  if ( $n_tietueet == $#tietueet + 1 ) {
    print STDERR "  Did not apply.\n";
  }
  return @tietueet
}



sub lisaa_kentta($$$) {
  # Miten tää suhtautuu marc21_record_add_field()-funktioon?

  my ( $tietue, $kentta, $arvo ) = @_;
  # print STDERR "LK IN $kentta='$arvo'...\n";
  if ( marc21_record_has_field($tietue, $kentta, '', undef) ) {
    if ( marc21_record_has_field($tietue, $kentta, '', $arvo) ) {
      # on jo, kaikki hyvin
      return $tietue;
    }
    my @fields = marc21_record_get_fields($tietue, $kentta, undef);
    # täällä on jotain paskaa, joka pitää selvittää
    die("Jotain on jo olemassa \@$kentta:\n" . join("\n", @fields));
  }
  $tietue = marc21_record_add_field($tietue, $kentta, $arvo);
  return $tietue;
}



sub append_zeroes_to_melinda_id($) {
  my $melinda_id = shift();

  if ( length($melinda_id) < 9 ) {
    # Append zeroes:
    $melinda_id = ( '0' x ( 9-length($melinda_id) )) . $melinda_id;
  }
  # remove this after testing:
  if ( length($melinda_id) != 9 ) { die("length($melinda_id) != 9"); }

  return $melinda_id;
}



sub lisaa_ulkofennicuus($) {
  my ( $record ) = @_;

  my $nf = "  \x1Faulkofennica";
  unless ( marc21_record_has_field($record, '583', undef, $nf) ) {
    print " Lisätään ulkofennica-merkintä 583 '$nf'\n";
    $record = marc21_record_add_field($record, '583', $nf);
  }

  return $record;
}


sub lisaa_puuteluetteloon($) {
  my ( $record ) = @_;

  my $nf = "  \x1FaPUUTELUETT.";
  unless ( marc21_record_has_field($record, '583', undef, $nf) ) {
    print " Lisätään puuteluettelomerkintä 583 '$nf'\n";
    $record = marc21_record_add_field($record, '583', $nf);
  }

  $nf = "  \x1FaPuuttuu kansalliskokoelmasta";
  unless ( marc21_record_has_field($record, '594', undef, $nf) ) {
    print " Lisätään puuteluettelomerkintä 594 '$nf'\n";
    $record = marc21_record_add_field($record, '594', $nf);
  }

  return $record;
}

sub lisaa_udk_versio($$$) {
  my ( $id, $record, $fennikeep ) = @_;

  my @f080 = marc21_record_get_fields($record, '080', undef);

  if ( $#f080 > -1 ) {
    my $new_sf2 = '1974/fin/fennica';
    if ( $record =~ /^......(as|is|es|gs|ms|os|ai)/ ) {
      $new_sf2 = '1974/fin/finuc-s';
    }
    for ( my $i=0; $i <= $#f080; $i++ ) {
      my $field = $f080[$i];
      my $sf2 = marc21_field_get_subfield($field, '2');
      # Jos kenttä on olemassa älä tee mitään

      if ( defined($sf2) ) {
	if ( $sf2 ne $new_sf2 ) {
	  print STDERR "$id\t080\tTODO: fix \$2 '$sf2' => '$new_sf2' manually\n";
	}
      }
      else {

	print STDERR "$id\tAdd \$2\n";
	if ( $field =~ s/(\x1F[3-9])/\x1F2${new_sf2}$1/ ) {
	  # Huomaa, että onnistuessaan s/// lisää $2:n	  
	}
	else {
	  $field .= "\x1F2${new_sf2}";
	}
	# FENNI<KEEP>-lisäys tarvittaessa
	if ( $fennikeep ) {
	  if ( $field =~ /\x1F9FENNI<KEEP>/ ) {
	    # do nothing
	  }
	  elsif ( $field !~ /\x1F9/ ) {
	    $field .= "\x1F9FENNI<KEEP>";
	  }
	  else {
	    die("FENNI<KEEP>-lisäys epäonnistui");
	  }
	}
	$record = marc21_record_replace_nth_field($record, '080', $field, $i);
      }
    }
  }
  return $record;
}

sub marc21_record_type($) { # sinnepäin, hyvin karkea
  my $record = $_[0];
  $record =~ /^......(.)(.)/ or die();
  my $type_of_record = $1;
  my $bibliographic_level = $2;
  my $format = $1.$2;
  # Book (BK)
  # Continuing Resources (CR)
  # Computer Files (CF)
  # Maps (MP)
  # Mixed Materials (MX)
  # Music (MU)
  # Visual Materials (VM)
  if ( $format =~ /^[at]/ ) {
    if ( $format =~ /[bis]/ ) { return 'CR'; }
    return 'BK';
  }
  if ( $format =~ /^[cdj]/ ) { return 'MU'; }
  if ( $format =~ /^[ef]/ ) { return 'MP'; }
  if ( $format =~ /^[m]/ ) { return 'CF'; }
  if ( $format =~ /^[p]/ ) { return ' MX'; }
  if ( $format =~ /^[g]/ ) { return 'VM'; }
  if ( $format =~ /^[iko]/ ) { return 'MX'; }
  if ( $format =~ /^[r]/ ) { return 'MX'; } # nähty lautapeli...

  print STDERR marc21_debug_record($record, "UNKNOWN RECORD TYPE");
  return 'MX'; # whatever
  die();
}

sub marc21_add_subfield_if_needed { # ($$$@) {
  my $record = shift;
  my $sf = shift;
  my $content = shift;

  while ( 1 ) {
    my $tag = shift();
    if ( !defined($tag) ) {
      return $record;
    }
    # print STDERR " Processing TAG $tag\$$sf $content\n";

    my @fields = marc21_record_get_fields($record, $tag, undef);
    for ( my $i=0; $i <= $#fields; $i++ ) {
      my $field = $fields[$i];
      #print STDERR "  Inspecting $tag '$field'\n";

      my $old_content = marc21_field_get_subfield($field, $sf);
      if ( !defined($old_content) ) {
	my $new_content = "$field\x1F$sf$content";
	$record = marc21_record_replace_nth_field($record, $tag, $new_content, $i);
	print STDERR "  Adding subfield $sf to $tag: '$field'\n";
      }
      elsif ( $old_content eq $content ) {
	# ok
      }
      else {
	print STDERR " TODO: HANDLE $tag\$$sf '$old_content' vs '$content'\n";
	die();
      }
    }
  }
  return $record;
}

sub replace_sid($$$$) {
  my ( $melinda_record, $sid, $old_id, $new_id ) = @_;
  my @sid = marc21_record_get_fields($melinda_record, 'SID', undef);
  for ( my $i=0; $i <= $#sid; $i++ ) {
    if ( $sid[$i] =~ /\x1Fb$sid/ ) {
      my $local_id = marc21_field_get_subfield($sid[$i], 'c');
      if ( $local_id eq $old_id ) {
	my $content = "  \x1Fc$new_id\x1Fb$sid";
	print STDERR "Replace SID:\n '", $sid[$i], "' =>\n '", $content, "'\n";
	$melinda_record = marc21_record_replace_nth_field($melinda_record, 'SID', $content, $i);
	return $melinda_record;
      }
    }
  }
  return $melinda_record;
}

sub remove_id_from_035($$) {
  my ( $voyager_record, $id2remove ) = @_;

  my $f001 = marc21_record_get_field($voyager_record, '001', undef);
  my $hit = -1;
  my $f001_in_035a = 0;

  if ( !$f001 ) { die(); }

  my @f035 = marc21_record_get_fields($voyager_record, '035', undef);
  for ( my $i=0; $i <= $#f035; $i++ ) {
    my $field = $f035[$i];
    my $a = marc21_field_get_subfield($field, 'a');
    if ( defined($a) ) {
      ## ei hakuta poistaa, jos muita osakenttiä
      ## eli ei käytetä ehtoa "if ( $a eq $id2remove )"
      if ( $field eq "  \x1Fa$id2remove" ) {
	$hit = $i;
	if ( $f001 eq $id2remove ) { # poistetaan (muuten korvataa foo id:llä)
	  $f001_in_035a = 1;
	}
      }
      elsif ( $a eq $f001 ) {
	$f001_in_035a = 1;
      }
    }
  }

  if ( $hit > -1 ) {
    if ( $f001_in_035a ) {
      print STDERR "$f001\tRemove 035\$a '$id2remove'\n";
      $voyager_record = marc21_record_remove_nth_field($voyager_record, '035', undef, $hit);
    }
    else {
      print STDERR "$f001\tReplace 035\$a '$id2remove' with '$f001'\n";
      $voyager_record = marc21_record_replace_nth_field($voyager_record, '035', "  \x1Fa$f001", $hit);
    }
  }
  return $voyager_record;
}


sub marc21_record_replace_field_with_field($$$$) {
  my ( $record, $tag, $from_field, $to_field) = @_;

  my @fields = marc21_record_get_fields($record, $tag, undef);
  for ( my $i=0; $i <= $#fields; $i++ ) {
    my $field = $fields[$i];
    if ( $field eq $from_field ) {
      $record = marc21_record_replace_nth_field($record, $tag, $to_field, $i);
      return $record;
    }
  }
  return $record;
}


sub marc21_remove_duplicate_fields($$) {
  my ( $record, $tag ) = @_;
  my $id = 0;
  my @fields = marc21_record_get_fields($record, $tag, undef);
  for ( my $i = $#fields; $i > 0; $i-- ) {
    my $f1 = $fields[$i];
    my $poista = 0;
    for ( my $j = 0; !$poista && $j < $i; $j++ ) {
      my $f2 = $fields[$j];
      if ( $f1 eq $f2 ) {
	$poista = 1;
      }
    }
    if ( $poista ) {
      if ( $id == 0 ) {
	$id = marc21_record_get_field($record, '001', undef);
      }
      print STDERR "$id\tPoistettu $tag '", $fields[$i], "'\n";
      $record = marc21_record_remove_nth_field($record, $tag, '', $i);
    }
  }
  return $record;
}

sub get_773d_from_host($) {
  my $record = $_[0];

  my $d = '';
  my $publisher_field = marc21_record_get_publisher_field($record);

  if ( defined($publisher_field) ) {
    my $h26Xa = marc21_field_get_subfield($publisher_field, 'a');
    my $h26Xb = marc21_field_get_subfield($publisher_field, 'b');
    my $h26Xc = marc21_field_get_subfield($publisher_field, 'c');
    my @d;

    if ( defined($h26Xa) ) { $d[$#d+1] = $h26Xa; }
    if ( defined($h26Xb) ) { $d[$#d+1] = $h26Xb; }
    if ( defined($h26Xc) ) { $d[$#d+1] = $h26Xc; }
    if( $#d > -1 ) {
      $d = join(' ', @d);
      # $d =~ s/\] *℗ ?\d+$/\]/; # siivoa vähän (ei kyl pyydetty)
      # $d =~ s/, *℗ ?\d+$//;; # siivoa vähän (ei kyl pyydetty)
      $d =~ s/\.$//;
    }
  }
  return $d;
}
sub get_773h_from_host($) {
  my $record = $_[0];

  my $h = marc21_record_get_field($record, '300', 'a');
  if ( !defined($h) ) { return ''; }

  $h =~ s/[ \.:;\+]*$//;
  if ( $h =~ s/(\S)\s*\([^\)]*\)$/$1/ ) { # loppusulut (kesto) pois.
    $h =~ s/[ \.:;\+]*$//;
  }
  return $h;
}

sub get_773k_from_host($) {
  my $record = $_[0];
  my $k = '';

  my $h490 = marc21_record_get_field($record, '490', undef);
  if ( defined($h490) ) {
    my $h490a = marc21_field_get_subfield($h490, 'a');
    my $h490n = marc21_field_get_subfield($h490, 'n');
    my $h490p = marc21_field_get_subfield($h490, 'p');
    my $h490x = marc21_field_get_subfield($h490, 'x');
    my $h490v = marc21_field_get_subfield($h490, 'v');
    my @k;
    if ( defined($h490a) ) { $k[$#k+1] = $h490a; }
    if ( defined($h490n) ) { $k[$#k+1] = $h490n; }
    if ( defined($h490p) ) { $k[$#k+1] = $h490p; }
    if ( defined($h490x) ) { $k[$#k+1] = $h490x; }
    if ( defined($h490v) ) { $k[$#k+1] = $h490v; }
    
    if( $#k > -1 ) {
      $k = join(' ', @k);
      $k =~ s/[ \.:]*$//;
    }
  }
  
  return $k;
}

sub get_773os_from_host($) {
  my $record = $_[0];

  my @ostack;


  if ( $record =~ /^......[acdo]/ ) {
    my @h024 = marc21_record_get_fields($record, '024', undef);
    for ( my $i=0; $i <= $#h024; $i++ ) {
      my $o = '';
      my $h024 = $h024[$i];
      if ( defined($h024) ) {
	my $h024a = marc21_field_get_subfield($h024, 'a');
	if ( defined($h024a) ) {
	  $ostack[$#ostack+1] = $h024a;
	}
      }
    }

    my @h028 = marc21_record_get_fields($record, '028', undef);
    for ( my $j=0; $j <= $#h028; $j++ ) {
      my $h028 = $h028[$j];
      if ( defined($h028) && $h028 =~ /^3/ ) {
	#my $h028b = marc21_field_get_subfield($h028, 'b');
	my $h028a = marc21_field_get_subfield($h028, 'a');

	#if ( defined($h028b) ) { $o[$#o+1] = $h028b; }
	if ( defined($h028a) ) {
	  $ostack[$#ostack+1] = $h028a;
	}
      }

    }
  }
  elsif ( $record =~ /^......[gj]/ ) {
    my @h028 = marc21_record_get_fields($record, '028', undef);
    for ( my $i=0; $i <= $#h028; $i++ ) {
      my $h028 = $h028[$i];
      if ( defined($h028) ) {
	my $h028a = marc21_field_get_subfield($h028, 'a');
	my $h028b = marc21_field_get_subfield($h028, 'b');
	my @o;
	if ( defined($h028b) ) { $o[$#o+1] = $h028b; } # B tulee ensin
	if ( defined($h028a) ) { $o[$#o+1] = $h028a; }
	if( $#o > -1 ) {
	  my $o = join(' ', @o);
	  $ostack[$#ostack+1] = $o;
	  if ( $#o == 1 ) {
	    $ostack[$#ostack] = $o[1];
	  }
	}
      }
    }
  }

  return @ostack;
}

sub get_773o_from_host($) {
  my $record = $_[0];
  my $o = '';

  if ( $record =~ /^......[acdo]/ ) {
    my $h024 = marc21_record_get_field($record, '024', undef);
    if ( defined($h024) ) {
      my $h024a = marc21_field_get_subfield($h024, 'a');
      if ( defined($h024a) ) {
	$o = $h024a;
      }
    }

    my $h028 = marc21_record_get_field($record, '028', undef);
    if ( defined($h028) && $h028 =~ /^3/ ) {
      #my $h028b = marc21_field_get_subfield($h028, 'b');
      my $h028a = marc21_field_get_subfield($h028, 'a');

      #if ( defined($h028b) ) { $o[$#o+1] = $h028b; }
      if ( defined($h028a) ) {
	my @o;
	if ( $o ) {
	  $o[0] = $o;
	}
	$o[$#o+1] = $h028a;
	if( $#o > -1 ) {
	  $o = join(' ', @o);
	}
      }
    }
  }
  elsif ( $record =~ /^......[gj]/ ) {
    my $h028 = marc21_record_get_field($record, '028', undef);
    if ( defined($h028) ) {

      my $h028a = marc21_field_get_subfield($h028, 'a');
      my $h028b = marc21_field_get_subfield($h028, 'b');
      my @o;
      if ( defined($h028b) ) { $o[$#o+1] = $h028b; } # B tulee ensin
      if ( defined($h028a) ) { $o[$#o+1] = $h028a; }
      if( $#o > -1 ) {
	$o = join(' ', @o);
      }
    }
  }

  $o =~ s/\.$//;
  $o =~ s/\s+$//;
  return $o;
}

sub get_773t_from_host($) {
  my $record = $_[0];
  my $h245a = marc21_record_get_field($record, '245', 'a');
  my $h245b = marc21_record_get_field($record, '245', 'b');
  my $h245n = marc21_record_get_field($record, '245', 'n');
  my $h245p = marc21_record_get_field($record, '245', 'p');
  my $h245c = marc21_record_get_field($record, '245', 'c');
  if ( !defined($h245a) ) {
    die();
  }
  my $t = $h245a;
  if ( defined($h245b) ) { $t .= " " . $h245b; }
  if ( defined($h245n) ) { $t .= " " . $h245n; }
  if ( defined($h245p) ) { $t .= " " . $h245p; }
  if ( defined($h245c) ) { $t .= " " . $h245c; }
  return $t;
}

sub get_773z_from_host($) {
  my $record = $_[0];
  my $z = '';

  if ( $record =~ /^......[acdo]/ ) {
    my $h020 = marc21_record_get_field($record, '020', undef);
    if ( defined($h020) ) {
      my $h020a = marc21_field_get_subfield($h020, 'a');
      if ( defined($h020a) ) {
	$z = $h020a;
      }
    }
  }
  return $z;
}

sub create773($$$) {
  my ( $host_id, $host_record, $g ) = @_;

  if ( $host_record =~ /^......([acdgjo])/ ) {
    my $type = $1;
    
    my $t = get_773t_from_host($host_record);
    my $d = get_773d_from_host($host_record);
    my $h = get_773h_from_host($host_record);
    my $k = get_773k_from_host($host_record);
    my $z = get_773z_from_host($host_record);
    my $o = get_773o_from_host($host_record);

    my $new773 = "0 " .
      "\x1F7" . "nn${type}m" .
      "\x1Fw" . $host_id .
      "\x1Ft" . $t .
      ( length($d) ? " -\x1Fd" . $d . '.' : '' ) .
      ( length($h) ? " -\x1Fh" . $h . "." : '' ) .
      ( length($k) ? " -\x1Fk" . $k . "." : '' ) .
      ( length($z) ? " -\x1Fz" . $z . "." : '' ) .
      ( length($o) ? " -\x1Fo" . $o . "." : '' ) .
      ( defined($g) && $g ? " -\x1Fg\u$g" : '' );
      # . " -\x1Fg" . "Raita"
      # . " -\x1Fnnvolk 790"

    $new773 =~ s/\.$//;
    $new773 =~ s/\s+/ /g;
    return $new773;
  }
  else {
    print STDERR "Sanity check...\n";
  }

  return undef;
}

sub critical_sanity_checks($$) {
  my ( $id, $record ) = @_;

  $record =~ /^.........(.)/;
  my $encoding = $1;

  if ( $encoding ne 'a' ) {
    print STDERR "$id\tLDR/09='$encoding'\ţNot Unicode\n";
  }

  if ( is_bib($record) ) {
    my @f245 = marc21_record_get_fields($record, '245', undef);
    if ( $#f245 != 0 ) {
      print STDERR "$id\tVirheellinen määrä 245-kenttiä: ", ($#f245+1), "\n";
    } elsif ( $f245[0] !~ /^..(\x1F[68][^\x1F]+)?\x1Fa/ ) {
      print STDERR "$id\tOuto nimeke '", $f245[0], "'\n";
    } elsif ( $f245[0] !~ /^[01][0-9]\x1F/ ) {
      print STDERR "$id\t245 indikaattoriongelma '", $f245[0], "'\n";
    }

    my @f100 = marc21_record_get_fields($record, '100', undef);
    my @f110 = marc21_record_get_fields($record, '110', undef);
    
    my @f260 = marc21_record_get_fields($record, '260', undef);
    my @f264 = marc21_record_get_fields($record, '264', undef);
    
    if ( $#f100 + $#f110 + 2 > 1 ) {
      print STDERR "$id\t100=", ($#f100+1), "\t110=", ($#f110+1), "\tYHT=", ( $#f100 + $#f110 + 2 ), "\n";
    }
    
    my @require_a = ( '100', '110' );
    for ( my $j=0; $j <= $#require_a; $j++ ) {
      my $tag = $require_a[$j];
      my @content = marc21_record_get_fields($record, $tag, undef);
      for ( my $i=0; $i <= $#content; $i++ ) {
	my $field = $content[$i];
	if ( $field !~ /\x1Fa/ ) {
	  print STDERR "$id\tKentästä $tag puuttuu osakenttä \$a: '$field'\n";
	} elsif ( $field !~ /\x1Fa[^\x1F]/ ) {
	  print STDERR "$id\tKentän $tag\$a:n arvo on outo: '$field'\n";
	}
      }
    }

    if ( $#f260 >= 0 && $#f264 >= 0 ) {
      print STDERR "$id\tnähty sekä 260 että 264!\n";
    }
  }
  elsif ( is_auth($record) ) {
    my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
    my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);
    my @tags = @$tags_ref;
    my $seen_1XX = 0;
    for ( my $i=0; $i <= $#tags; $i++ ) {
      if ( $tags[$i] =~ /^1/ ) {
	$seen_1XX++;
      }
    }
    if ( $seen_1XX > 1 ) {
      my $f001 = marc21_record_get_field($record, '001', undef);
      print STDERR "AUTH-$id\tMultiple 1XX fields\n";
    }
  }
  elsif ( is_holding($record) ) {

  }
  else {
    die();
  }

  # Tarkista tarkistan, että kunkin kentän osakentät on speksattu kelvollisesti:
  my @fields = split(/\x1E/, $record);
  for ( my $i=0; $i <= $#fields; $i++ ) {
    my $content = $fields[$i];
    if ( $content =~ /^[^\x01-\x1C\x1F]+$/ ) {
      #print STDERR "OK kiinteä\n";
      # ok, kiinteämittainen
    }
    elsif ( $content =~ /^[^\x1F][^\x1F](\x1F[a-z0-9][^\x00-\x1F]*)+$/ ) {
      #print STDERR "OK normo\n";
      # Ok normikenttä
    }
    else {
      print STDERR "$id\tOuto kenttä '$content'\n";
      print STDERR nvolk_marc212oai_marc($record);
    }
  }

  return $record;
}

1;



# update ANNUAL_STAT_DATA set VALUE='*' where YEAR=2012 and LIBRARY_ID=1 and VALUE<>'*' and VALUE=INHERITED_VALUE;

# 
