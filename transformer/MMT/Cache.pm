package MMT::Cache;

use MMT::Pragmas;

#External modules
use Text::CSV;

#Local modules
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

MMT::Cache - Simple key-value cache.

=head2 DESCRIPTION

Used to slurp Voyager exported tables into memory

=cut

=head2 new

 @param1 HASHRef of constructor params: {
  name => 'patron_notes', #Name of the Cache, or the type of data it contains
  file => 'file.csv',     #Which file is slurped to cache
  keys => ['PATRON_ID'],  #List of column names to use as cache keys. Use the same keys to fetch the result
 }

=cut

sub new {
  my ($class, $p) = _validate(@_);
  my $self = bless({}, $class);
  $self->{_params} = $p;
  $self->{_params}->{filetype} = MMT::Validator::filetype($self->file());
  $self->{_cache} = {};
  $self->_slurpFile();
  return $self;
}
sub _validate($class, $p) {
  my $var; #Simply reduce duplication at a cost of slight awkwardness
  $var = 'file';      MMT::Validator::isString($p->{$var}, $var, undef);
  $p->{$var} = MMT::Config::exportsDir().'/'.$p->{$var} unless MMT::Validator::checkIsAbsolutePath($p->{$var}); #Prepend the voyager exports dir if the file is not an absolute path

  $var = 'file';      MMT::Validator::isFileReadable($p->{$var}, $var, undef);
  $var = 'name';      MMT::Validator::isString($p->{$var}, $var, undef);
  $var = 'keys';      MMT::Validator::isArray($p->{$var}, $var, undef);
  return @_;
}
sub _slurpFile($s) {
  $log->info("Loading Cache '".$s->name()."' into memory from '".$s->file()."' using keys '".join(',', @{$s->keys()})."'");

  my $linesRead;
  given ($s->filetype()) {
    when ('csv') {
      $linesRead = $s->_slurpCsv();
    }
    default {
      die "Unsupported filetype '".$s->filetype()."'";
    }
  }

  $log->info("Cache '".$s->name()."' loaded. '$linesRead' lines read.");
}
sub _slurpCsv($s) {
  my $csv = Text::CSV->new(MMT::Config::csvInputNew());
  my $encoding = MMT::Config::csvInputEncoding();
  open(my $FH, "<:encoding($encoding)", $s->file());
  eval {
    $csv->header($FH, MMT::Config::csvInputHeader());
  };
  if ($@) { $log->logdie("Failed to read the header of .csv-file '".$s->file()."'!\n$@") }
  $log->debug("Loading .csv-file '".$s->file()."', identified columns '".join(',', $csv->column_names())."'");
  my $i = 0;
  while (my $obj = $csv->getline_hr($FH)) {
    $i++;
    push (@{$s->{_cache}->{$s->key($obj)}}, $obj);
  }
  close $FH;
  return $i;
}

=head2 get

 @param1 HASHRef, the Cache key is built using the same HASH keys as the keys defined in this Cache,
         or SCALAR, String representation of a preconstructed Cache key. Useful when the only key is for. ex. the patron_id
 @returns ARRAYRef of cached values.

=cut

sub get($s, $o) {
  if (ref $o) { #Scalar returns undef
    return $s->{_cache}->{$s->key($o)};
  }
  else {
    return $s->{_cache}->{$o};
  }
}
sub key($s, $o) {
  my $key = '';
  foreach my $k (@{$s->keys()}) {
    $log->error("Object '".MMT::Validator::dumpObject($o)."' doesn't have the needed Cache key '$k'") unless defined $o->{$k};
    $key .= $o->{$k}||'NULL';
  }
  return $key;
}
sub keys {
  return $_[0]->{_params}->{keys};
}
sub name {
  return $_[0]->{_params}->{name};
}
sub file {
  return $_[0]->{_params}->{file};
}
sub filetype {
  return $_[0]->{_params}->{filetype};
}
sub delimiter {
  return $_[0]->{_params}->{delimiter};
}
