package MMT::DeleteList;

use MMT::Pragmas;

#External modules

#Local modules
my Log::Log4perl $log = Log::Log4perl->get_logger(__PACKAGE__);

my $filename = MMT::Config::kohaImportDir() . '/' . 'droplist.txt';

sub FlushDeleteList {
  if (-e $filename) {
    open(my $FH, '>', $filename) or die $!;
    close($FH) or die $@;
  }
}

sub new {
  my ($class) = @_;
  my $self = bless({}, $class);
  $self->{_list} = {};
  $self->_slurpFile();
  return $self;
}

sub _slurpFile {
  my ($self) = @_;
  if (-e $filename) {
    $log->info("Slurping '$filename'");
    open(my $FH, '<:encoding(UTF-8)', $filename) or die $!;
    while(<$FH>) {
      if ($_ !~ /^(.+):(.*)$/) {
        $log->warn("Unable to parse row = '$_'");
        next;
      }
      $self->{_list}->{$1} = $2;
    }
    close($FH);
  } else {
    $log->info("Slurping '$filename' didn't exist yet");
  }
}

sub saveList {
  my ($self) = @_;
  $log->info("Saving to '$filename'");

  my @sb = map { $_ . ':' . $self->{_list}->{$_} } sort keys %{$self->{_list}};
  open(my $FH, '>:encoding(UTF-8)', $filename) or die $!;
  print $FH join("\n", @sb);
  close $FH or die $@;
}

sub get {
  my ($self, $key) = @_;
  return $self->{_list}->{$key};
}

sub put {
  my ($self, $kohaObject, $exception) = @_;
  $self->{_list}->{$kohaObject->getDeleteListId()} = (split("\n", $exception->error()))[0];
  return $self;
}

return 1;

