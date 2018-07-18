use 5.22.1;

package MMT::Builder;
#Pragmas
use Carp::Always::Color;
use experimental 'smartmatch', 'signatures';

#External modules
use Text::CSV;
use Data::Dumper;

#Local modules
use MMT::Config;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);
use MMT::Validator;
use MMT::Cache;
use MMT::Tester;

#Add a bit of type-safety
use fields qw(inputFile outputFile type);

=head1 NAME

MMT::Builder

=head1 DESCRIPTION

-Dynamically loads the correct Koha object instance to build
-Loads the translation tables, they are accessible by the last part of the translation table class name
-Loads external repositories, to be accessible using the given repository name
-Invokes the correct MMT::Koha::Object's new() and build() as per the interface definition for each row
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
      {name => "Branchcodes", params => [1,2,3]},
      ...
    ],
  });

  open(my $FH, "<:encoding(UTF-8)", MMT::Config::kohaImportDir.'/'.$b->{type}.'.migrateme';

=cut

sub new($class, $params) {
  $log->trace("Constructor(@_)") if $log->is_trace();
  my $self = bless($params, $class);


  $log->logdie("$class attribute 'type' is not defined") unless $self->{type};


  $self->{inputFile} = MMT::Config::voyagerExportDir."/".$self->{inputFile} unless -e $self->{inputFile};
  $self->{outputFile} = MMT::Config::kohaImportDir.'/'.$self->{type}.'.migrateme';
  $self->_loadRepositories();
  $self->_loadTranslationTables();
  $self->{tester} = MMT::Tester->new(MMT::Config::testDir.'/'.$self->{type}.'.yaml');
  return $self;
}

sub build($s) {
  $log->info($s->{type}." - Starting to build");

  my $csv=Text::CSV->new({ binary => 1 });
  open(my $inFH, '<:encoding(UTF-8)', $s->{inputFile}) or $log->logdie("Loading file '".$s->{inputFile}."' failed: $!");
  $csv->column_names($csv->getline($inFH));
  $log->info("Loading file '".$s->{inputFile}."', identified columns '".join(',', $csv->column_names())."'");

  #Open output file
  $log->info("Opening file '".$s->{outputFile}."' for export");
  open(my $outFH, '>:encoding(UTF-8)', $s->{outputFile}) or $log->logdie("Opening file '".$s->{outputFile}."' failed: $!");

  my $objectClass = 'MMT::Koha::'.$s->{type};
  __dynaload($objectClass);

  my $i = 0; #Track how many KohaObjects are processed
  my $w = 0; #Track how many KohaObjects actually survived the build
  while (my $o = $csv->getline_hr($inFH)){
    $i++;
    my $ko = $objectClass->new(); #Instantiate first, so we get better error handling when we can catch the failed object when building it.
    eval {
      $ko->build($o, $s);
    };
    if ($@) {
      if (ref($@) eq 'MMT::Exception::Delete') {
        $log->debug($ko->logId()." was dropped. Reason: ".$@->error) if $log->is_debug();
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
