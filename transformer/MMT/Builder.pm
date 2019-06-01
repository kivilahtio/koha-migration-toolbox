package MMT::Builder;

use MMT::Pragmas;

#External modules
use Text::CSV;

#Local modules
use MMT::Cache;
use MMT::Tester;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

#Add a bit of type-safety
use fields qw(inputFile outputFile type);

=head1 NAME

MMT::Builder

=head1 DESCRIPTION

-Dynamically loads the correct Koha object instance to build
-Loads the translation tables, they are accessible by the last part of the translation table class name
-Loads external repositories, to be accessible using the given repository name
-Invokes the correct MMT::Voyager2Koha::Object's new() and build() as per the interface definition for each row
 in the given $inputFile
-Writes transformed .migrateme-"Koha object files" into the configured Export directory

=head2 SYNOPSIS

  my $b = MMT::Builder->new({
    type => 'Item',
    inputFile => '02-items.csv',
    repositories => [
      {name => "Last borrow dates", file => "02-borrow-dates.csv", keys => ['barcode']},
      ...
    ],
    translationTables => [
      {name => "LocationId", params => [1,2,3]},
      ...
    ],
  });

  open(my $FH, "<:encoding(UTF-8)", MMT::Config::kohaImportDir.'/'.$b->{type}.'.migrateme';

=cut

sub new($class, $params) {
  $log->trace("Constructor(@_)") if $log->is_trace();
  my $self = bless($params, $class);


  $log->logdie("$class attribute 'type' is not defined") unless $self->{type};


  $self->{inputFile} = MMT::Config::exportsDir."/".$self->{inputFile} unless -e $self->{inputFile};
  $self->{outputFile} = MMT::Config::kohaImportDir.'/'.$self->{type}.'.migrateme';
  $self->_loadRepositories();
  $self->_loadTranslationTables();
  $self->{tester} = MMT::Tester->new(MMT::Config::testDir.'/'.$self->{type}.'.yaml');

  return $self;
}

=head2 now

 @returns The current datetime in ISO8601 YYYY-MM-DDTHH:MM:SS

=cut

sub now($s) {
  unless ($s->{now}) {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $s->{now} = sprintf("%04d-%02d-%02dT%02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
  }
  return $s->{now};
}

sub build($s) {
  $log->info($s->{type}." - Starting to build");

  my $csv = Text::CSV->new(MMT::Config::csvInputNew());
  open(my $inFH, '<:encoding(UTF-8)', $s->{inputFile}) or $log->logdie("Loading file '".$s->{inputFile}."' failed: $!");
  $csv->column_names($csv->getline($inFH));
  $log->info("Loading file '".$s->{inputFile}."', identified columns '".join(',', $csv->column_names())."'");

  #Open output file
  $log->info("Opening file '".$s->{outputFile}."' for export");
  open(my $outFH, '>:encoding(UTF-8)', $s->{outputFile}) or $log->logdie("Opening file '".$s->{outputFile}."' failed: $!");

  my $objectClass = 'MMT::Voyager2Koha::'.$s->{type};
  __dynaload($objectClass);

  my $i = 0; #Track how many KohaObjects are processed
  my $w = 0; #Track how many KohaObjects actually survived the build
  while (my $o = $csv->getline_hr($inFH)){
    $i++;

    if ($o->{DUPLICATE}) {
      $log->debug("Duplicate entry skipped at input file line '$.'");
      next;
    }

    my $ko = $objectClass->new(); #Instantiate first, so we get better error handling when we can catch the failed object when building it.
    eval {
      $ko->build($o, $s);
    };
    if ($@) {
      if (ref($@) eq 'MMT::Exception::Delete') {
        $log->error($ko->logId()." was dropped. Reason: ".$@->error) if $log->is_error();
      }
      else {
        $log->fatal("Received an unhandled exception '".MMT::Validator::dumpObject($@)."'") if $log->is_fatal();
      }
    }
    else {
      print $outFH $ko->serialize()."\n";
      $log->debug("Wrote ".$ko->logId()) if $log->is_debug();
      $s->{tester}->test($ko);
      $w++;
    }
  }

  close $outFH;
  close $inFH;
  $log->info("Built, $w/$i objects survived");

  return undef; #Getopt::OO callback errors if we return something.
}

=head2 _loadRepositories

 @param1 $self, uses the object attribute 'repositories' to load all configured repositories dynamically inside the Builder.

=cut

sub _loadRepositories($s) {
  for my $repo (@{$s->{repositories}}) {
    $s->{ $repo->{name} } = MMT::Cache->new($repo);
  }
}
sub _loadTranslationTables($s) {
  for my $table (@{$s->{translationTables}}) {
    my $tableClass = 'MMT::TranslationTable::'.$table->{name};
    __dynaload($tableClass);
    my $params = $table->{params} || [];
    $s->{ $table->{name} } = $tableClass->new(@$params);
  }
}

sub __dynaload($module) {
  (my $file = $module) =~ s|::|/|g;
  require $file . '.pm';
}

return 1;
