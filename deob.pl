#!/usr/bin/perl -w
# deob.pl --- 
# Last modify Time-stamp: <Ye Wenbin 2007-10-30 17:27:58>
# Version: v 0.0 2007/10/27 07:43:18
# Author: Ye Wenbin <wenbinye@gmail.com>

use strict;
use warnings;

#{{{  Ring
package Ring;
#
# method:
#  - insert: insert an element to ring
#  - peek: return current element
#  - roll_back: remove current element
#  - resize: resize the ring
sub new {
    my $_class = shift;
    my $class = ref $_class || $_class;
    my $self = {size => 0, data => [], curr=> 0, length => 0};
    if ( ref $_[0] ) {
        $self->{data} = shift;
        $self->{size} = scalar(@{$self->{data}});
        $self->{length} = $self->{size};
    }
    if ( @_ ) {
        $self->{size} = shift;
    }
    bless $self, $class;
    
    return $self;
}

sub insert {
    my $self = shift;
    if ( $self->{size} == 0 ) {
        return;
    }
    $self->{data}[$self->{curr}] = shift;
    $self->{curr}++;
    if ( $self->{curr} == $self->{size} ) {
        $self->{curr} = 0;
    }
    if ( $self->{length} < $self->{size} ) {
        $self->{length}++;
    }
    return $self->{length};
}

sub roll_back {
    my $self = shift;
    if ( $self->{length} == 0 ) {
        return;
    }
    $self->{curr}--;
    if ( $self->{curr} < 0 ) {
        $self->{curr} = $self->{size}-1;
    }
    $self->{length}--;
}

sub peek {
    my $self = shift;
    if ( $self->{length} == 0 ) {
        return;
    }
    return $self->{data}[$self->{curr}-1];
}

sub toarray {
    my $self = shift;
    if ( $self->{length} == 0 ) {
        return;
    }
    my ($data, $curr, $len) = ($self->{data}, $self->{curr},
                               $self->{length});
    if ( $curr - $len < 0 ) {
        return (@{$data}[$#$data-($len-$curr)+1..$#$data],
                @{$data}[0..$curr-1]);
    } else {
        return @{$data}[($curr-$len)..$curr-1];
    }
}

sub length {
    my $self = shift;
    return $self->{length};
}

sub size {
    my $self = shift;
    return $self->{size};
}

sub resize {
    my $self = shift;
    my $newsize = shift;
    if ( $newsize > $self->{size} ) {
        splice(@{$self->{data}}, $self->{curr}, 0, (undef)x($newsize-$self->{size}));
    } else {
        my $len = $self->{size}-$newsize;
        if ( $self->{curr} + $len > $self->{size} ) {
            splice(@{$self->{data}}, $self->{curr}, $self->{size}-$self->{curr});
            splice(@{$self->{data}}, 0, $len-$self->{size}+$self->{curr});
        } else {
            splice(@{$self->{data}}, $self->{curr}, $len);
        }
        if ( $self->{length} > $newsize ) {
            $self->{length} = $newsize;
        }
    }
    $self->{size} = $newsize;
}
#}}}

package main;

use Deobfuscator;
use Getopt::Long;
use Pod::Usage;
use List::Util qw(max min);
use Text::Abbrev;
use Text::Wrap;
use Data::Dumper qw(Dumper);
use FindBin qw($Bin);

our $VERSION = "0.02";
# Turn all buffering off.
select((select(STDOUT), $| = 1)[0]);
select((select(STDERR), $| = 1)[0]);
select((select(STDIN),  $| = 1)[0]);

#{{{  Main Loop
#{{{ Global Variables
our %commands = (
    alias => \&alias,
    desc => \&desc,
    exit => \&quit,
    help => \&help,
    history => \&history,
    isa => \&isa,
    method => \&method,
    pop => \&pop_history,
    quit => \&quit,
    search => \&search,
    show => \&show,
    synopsis => \&synopsis,
);
our %cmd_abbv = abbrev( keys %commands );
#{{{  Help documents
our %help_doc = (
    help => <<'HELP',
Syntax: command [options] [parameters]
Available commands:
  alias    [ -quiet ] alias command 
  desc     [ -short ] [ module ]
  exit
  help     [ command ]
  history  [ -method -show_all ] number
  isa      [ -tree -child ] [ modlue ]
  method   [ -remove_root -sort method|class ] [ module ]
  pop      [ -method ] [ number ]
  quit
  search   [ -ignorecase -case -method ] pattern
  show     method
  synopsis [ module ]
HELP
    search => <<'SEARCH',
search [-ignorecase -case -method] patten

Search the modules or methods that match the pattern. 
SEARCH
    isa => <<'ISA',
isa [-child -tree] [module]

Show the superclass or child class of module.
Option -tree indicate using Data::TreeDumper show the hierarchy
tree of the module.
Option -child indicate show the child class of the module.
The parameters module can be the full name of the module,
or the Id number in last search result. If omit, use
the modules last time used.
ISA
    exit => <<'EXIT',
exit

Exit the program.
EXIT
    quit => <<'QUIT',
quit 

Exit the program.
QUIT
    desc => <<'DESC',
desc [-short] [module]

Show the description of the module.
option -short indicate show the short description of the
module.
The parameters module can be the full name of the module,
or the Id number in last search result. If omit, use
the modules last time used.
DESC
    history => <<'HISTORY',
history [-method -show_all] [ number ]

Show the last number history in the module or method ring.
Option -show_all indicate show all items in history, override
the $Config{history_max_items}.
HISTORY
    pop => << 'POP',
pop [-method ] [number]

Remove the last number item in history.
POP
    alias => <<'ALIAS',
alias [-quiet] new command

Make the name "new" do the same as original "command".
ALIAS
    method => <<'METHOD',
method [ -remove_root -sort class|method] [module]

Show the method of the module.
Option -sort indicate the order to display the table.
Current support two sort method: class or method.
Option -remove_root will toggle display root method, that
is to say that if $Config{remove_root_method} is true,
the option is to display root method.
The parameters module can be the full name of the module,
or the Id number in last search result. If omit, use
the modules last time used.
METHOD
    synopsis => <<'SYNOPSIS',
synopsis [module]

Show the synopsis of the module.
The parameters module can be the full name of the module,
or the Id number in last search result. If omit, use
the modules last time used.
SYNOPSIS
    show => <<'SHOW',
show method

Show the detail information of the method.
The parameters method can be the full name of the module,
or the Id number in last query using command "method".
SHOW
);
#}}}

our $current_cmd;
our @last_module;
our ($module_history, $method_history);
our ($packages, $methods);
our ($isa, $risa, $tree);

#{{{  Configuration
our %Config = (
    # File create by deob_index.pl
    'packages' => "packages.db",
    'methods' => "methods.db",
    # ignore case for search pattern and commands
    'ignorecase' => 1,
    # list methods order
    'sort_method_by' => 'class',
    # list methods that exclude root method
    'remove_root_method' => 0,
    # Max items record in history
    'history_length' => 30,
    # Max items to show using command 'history'
    'history_max_items' => 3,
    # Max rows in the table
    'max_rows' => 1000,
    # Table output style, current only three style
    # support: 'table', 'orgtbl', 'tab'
    'table_style' => 'table',
    # Max column width of table
    'max_width' => 50,
    # Column width for each command that output table
    'width' => {
        method => [ undef, undef, undef, 30, 30 ],
    },
    # Output row seperator or not for each command
    'row_separator' => {
        'method' => 1,
    },
);
my $home;
eval { require File::HomeDir };
if ( $@ ) {
    $home = File::HomeDir->my_home;
}
else {
    $home = $ENV{HOME} || $Bin;
}
if ( -e "$home/.deob" ) {
    eval { require "$home/.deob" };
    if ( $@ ) {
        print STDERR "Error when load config file!\n";
    }
}
#}}}

$packages = Deobfuscator::open_db($Config{packages});
$methods  = Deobfuscator::open_db($Config{methods});
$module_history = Ring->new( $Config{history_length} );
$method_history = Ring->new( $Config{history_length} );
#}}}

while ( 1 ) {
    print "deob> ";
    $current_cmd = <STDIN>;
    if ( !defined $current_cmd ) {
        quit();
    }
    chomp($current_cmd);
    trim($current_cmd);
    if ( $current_cmd ) {
        my @words = split /\s/, $current_cmd;
        if ( $Config{ignorecase} ) {
            $words[0] = lc($words[0]);
        }
        if ( exists $cmd_abbv{$words[0]} ) {
            my $cmd = $cmd_abbv{shift @words};
            $commands{$cmd}->(@words);
        } else {
            print "Unknown command \"$words[0]\"\n"
        }
    }
}
#}}}

#{{{  Helper function

# replace_index($array_ref, $history)
# if the item in the array ref is a number, replace it with the thing
# in the nth of last item of history.
sub replace_index {
    my ($args, $history) = @_;
    my $last;
    foreach ( @$args ) {
        if ( /^\d+$/ ) {
            unless ( $last ) {
                $last = $history->peek;
                if ( defined $last ) {
                    $last = $last->[1];
                } else {
                    print "No last item found! Please do some search first.\n";
                }
            }
            if ( defined $last ) {
                if ( $_ <= $#$last+1 ) {
                    $_ = $last->[$_-1];
                } else {
                    print "$_ out of range! Max index is ", $#$last+1, "\n";
                    $_ = undef;
                }
            } else {
                $_ = undef;
            }
        }
    }
    @$args = grep { defined $_ } @$args;
}

sub save_history {
    my $mods = shift;
    if ( @$mods ) {
        replace_index($mods, $module_history);
        @last_module = @$mods;
    }
    else {
        @$mods = @last_module;
    }
}

sub trim_table {
    my $table = shift;
    if ( $#$table > $Config{max_rows} ) {
        print "Match item exceed the max rows!\n";
        $#$table = $Config{max_rows};
    }
}
#}}}

#{{{  Commands
sub eval_input {
    (my $code = $current_cmd) =~ s/^\w+//;
    eval($code);
}

sub quit {
    print "\nByebye!\n";
    exit;
}

sub help {
    my @args = @_;
    if ( @args ) {
        my %seen;
        foreach ( @args ) {
            if ( !exists $cmd_abbv{$_} ) {
                print "No command \"$_\" found!\n";
                next;
            }
            my $full = $cmd_abbv{$_};
            next if exists $seen{$full};
            $seen{$full}++;
            if ( exists $help_doc{$full} ) {
                print "* $_\n";
                print $help_doc{$full}, "\n";
            }
            else {
                print "Sorry, the document about \"$_\" is not write yet!\n";
            }
        }
    }
    else {
        print $help_doc{help}, "\n";
    }
}

sub pop_history {
    my @args = shift;
    my $method;
    parse_args(\@args, {'-method' => \$method });
    my $n = $args[0] || 1;
    my $history = $module_history;
    if ( $method ) {
        $history = $method_history;
    }
    while ( $n > 0 ) {
        last if !$history->roll_back;
        $n--;
    }
}

sub history {
    my @args = @_;
    my ($method, $show_all, $n);
    parse_args(\@args,
               {
                   '-method' => \$method,
                   '-show_all' => \$show_all,
               });
    my @history = ( $method ?
                        $method_history->toarray :
                            $module_history->toarray );
    if ( @args ) {
        $n = shift @args;
        if ( $n< scalar(@history) ) {
            splice(@history, 0, $#history-$n+1);
        }
    }
    foreach ( 1..$#history+1 ) {
        my $h = $history[$_-1];
        print "$_. ", $h->[0], "\n";
        my $idx = ( $show_all ? $#{$h->[1]} : min($Config{history_max_items}, $#{$h->[1]})); 
        for ( 0..$idx ) {
            print "  ", sprintf("%3d. ", $_+1), $h->[1][$_], "\n";
        }
        if ( $#{$h->[1]} > $idx ) {
            print "   ...\n";
        }
    }
}

sub show {
    my @args = @_;
    replace_index( \@args, $method_history );
    foreach my $m (@args) {
        print "* $m\n";
        my @table;
        foreach ( "title", "usage", "function", "returns", "args" ) {
            my $doc = Deobfuscator::get_method_docs( $methods, $m, $_ );
            if ( $doc eq "0" ) {
                $doc = "not documented";
            } else {
                normal_space(trim($doc))
            }
            push @table, [ ucfirst($_), $doc ];
        }
        print_table(
            \@table,
            style => $Config{table_style},
            max_width => $Config{max_width},
            width => $Config{width}{show},
            row_separator => $Config{row_separator}{show},
        );
    }
}

sub alias {
    my @args = @_;
    my ($quiet);
    parse_args(\@args, { -quiet => \$quiet });
    my ($alias, $cmd) = @args;
    if ( !exists $cmd_abbv{$cmd} ) {
        print "Unknown command \"$cmd\"\n";
        return;
    }
    if ( !$quiet ) {
        print "\"$alias\" alias to \"$cmd_abbv{$cmd}\"\n";
    }
    add_abbrev(\%cmd_abbv, $alias);
    $commands{$alias} = $commands{$cmd};
}

sub synopsis {
    my @args = @_;
    save_history(\@args);
    foreach ( @args ) {
        print "* $_\n";
        print Deobfuscator::get_pkg_docs($packages, $_, 'synopsis');
        print "\n";
    }
}

sub isa {
    my @args = @_;
    if ( !defined $isa ) {
        #{{{  ISA
        $isa = {
            'Bio::DB::GFF::Adaptor::dbi' => [
                'Bio::DB::GFF'
            ],
            'Bio::OntologyIO::InterProParser' => [
                'Bio::OntologyIO'
            ],
            'Bio::Seq::Quality' => [
                'Bio::LocatableSeq',
                'Bio::Seq::Meta::Array'
            ],
            'Bio::Graphics::FeatureFile::Iterator' => [],
            'Bio::DB::GenericWebDBI' => [
                'Bio::Root::Root',
                'LWP::UserAgent'
            ],
            'Bio::Map::Clone' => [
                'Bio::Root::Root',
                'Bio::Map::MappableI'
            ],
            'Bio::Tools::RestrictionEnzyme' => [
                'Bio::Root::Root',
                'Exporter'
            ],
            'Bio::SeqIO::raw' => [
                'Bio::SeqIO'
            ],
            'Bio::Map::EntityI' => [
                'Bio::Root::RootI'
            ],
            'Bio::AlignIO::phylip' => [
                'Bio::AlignIO'
            ],
            'Bio::FeatureIO::interpro' => [
                'Bio::FeatureIO'
            ],
            'Bio::DB::ReferenceI' => [],
            'Bio::Assembly::IO::ace' => [
                'Bio::Assembly::IO'
            ],
            'Bio::Root::Version' => [],
            'Bio::Annotation::SimpleValue' => [
                'Bio::Root::Root',
                'Bio::AnnotationI'
            ],
            'Bio::Tools::Phylo::PAML' => [
                'Bio::Root::Root',
                'Bio::Root::IO',
                'Bio::AnalysisParserI'
            ],
            'Bio::Factory::SeqAnalysisParserFactoryI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Seq::SeqBuilder' => [
                'Bio::Root::Root',
                'Bio::Factory::ObjectBuilderI'
            ],
            'Bio::Factory::ResultFactoryI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Tools::BPlite::Iteration' => [
                'Bio::Root::Root'
            ],
            'Bio::Ontology::Path' => [
                'Bio::Ontology::Relationship',
                'Bio::Ontology::PathI'
            ],
            'Bio::DB::GFF::Aggregator::ucsc_twinscan' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::DB::Flat' => [
                'Bio::Root::Root',
                'Bio::DB::RandomAccessI'
            ],
            'Bio::IdentifiableI' => [
                'Bio::Root::RootI'
            ],
            'Bio::SeqIO::tigr' => [
                'Bio::SeqIO'
            ],
            'Bio::DB::GFF::Adaptor::biofetch_oracle' => [
                'Bio::DB::GFF::Adaptor::dbi::oracle'
            ],
            'Bio::DB::QueryI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Seq::RichSeq' => [
                'Bio::Seq',
                'Bio::Seq::RichSeqI'
            ],
            'Bio::Search::HSP::PsiBlastHSP' => [
                'Bio::SeqFeature::SimilarityPair',
                'Bio::Search::HSP::HSPI'
            ],
            'Bio::LiveSeq::Exon' => [
                'Bio::LiveSeq::Range'
            ],
            'Bio::DB::GFF::Feature' => [
                'Bio::DB::GFF::RelSegment',
                'Bio::SeqFeatureI'
            ],
            'Bio::PopGen::IO::csv' => [
                'Bio::PopGen::IO'
            ],
            'Bio::Tools::Run::GenericParameters' => [
                'Bio::Root::Root',
                'Bio::Tools::Run::ParametersI'
            ],
            'Bio::SeqIO::tigrxml' => [
                'Bio::SeqIO',
                'XML::SAX::Base'
            ],
            'Bio::DB::Flat::BinarySearch' => [
                'Bio::DB::RandomAccessI'
            ],
            'Bio::Search::Hit::BlastHit' => [
                'Bio::Search::Hit::GenericHit'
            ],
            'Bio::Graphics::Glyph::ruler_arrow' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Ontology::TermFactory' => [
                'Bio::Factory::ObjectFactory'
            ],
            'Bio::Ontology::InterProTerm' => [
                'Bio::Ontology::Term'
            ],
            'Bio::DB::RandomAccessI' => [
                'Bio::Root::Root'
            ],
            'Bio::Search::HSP::FastaHSP' => [
                'Bio::Search::HSP::GenericHSP'
            ],
            'Bio::Symbol::Symbol' => [
                'Bio::Root::Root',
                'Bio::Symbol::SymbolI'
            ],
            'Bio::Tools::tRNAscanSE' => [
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::Taxonomy::Tree' => [
                'Bio::Root::Root',
                'Bio::Tree::TreeI',
                'Bio::Tree::TreeFunctionsI'
            ],
            'Bio::DB::GFF::Adaptor::dbi::pg' => [
                'Bio::DB::GFF::Adaptor::dbi'
            ],
            'Bio::Search::Result::WABAResult' => [
                'Bio::Search::Result::GenericResult'
            ],
            'Bio::PopGen::PopulationI' => [
                'Bio::Root::RootI'
            ],
            'Bio::SeqFeature::Gene::GeneStructure' => [
                'Bio::SeqFeature::Generic',
                'Bio::SeqFeature::Gene::GeneStructureI'
            ],
            'Bio::SeqIO::scf' => [
                'Bio::SeqIO'
            ],
            'Bio::Tools::ECnumber' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::Flat::BDB' => [
                'Bio::DB::Flat'
            ],
            'Bio::Factory::ApplicationFactoryI' => [
                'Bio::Root::RootI'
            ],
            'Bio::RangeI' => [
                'Bio::Root::RootI'
            ],
            'Bio::OntologyIO::Handlers::InterProHandler' => [
                'Bio::Root::Root'
            ],
            'Bio::Factory::DriverFactory' => [
                'Bio::Root::Root'
            ],
            'Bio::Variation::SNP' => [
                'Bio::Variation::SeqDiff',
                'Bio::Variation::Allele'
            ],
            'Bio::Graphics::Glyph::dumbbell' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::SearchIO::Writer::HTMLResultWriter' => [
                'Bio::Root::Root',
                'Bio::SearchIO::SearchWriterI'
            ],
            'Bio::MapIO::fpc' => [
                'Bio::MapIO'
            ],
            'Bio::Phenotype::MeSH::Twig' => [
                'Bio::Root::Root'
            ],
            'Bio::Tools::Hmmpfam' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::SeqIO::game::gameWriter' => [
                'Bio::SeqIO::game::gameSubs'
            ],
            'Bio::SearchIO::Writer::ResultTableWriter' => [
                'Bio::Root::Root',
                'Bio::SearchIO::SearchWriterI'
            ],
            'Bio::DB::GFF::Aggregator::ucsc_refgene' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::Assembly::ScaffoldI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Graphics::Glyph' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::Taxonomy::list' => [
                'Bio::DB::Taxonomy'
            ],
            'Bio::LiveSeq::Range' => [
                'Bio::LiveSeq::SeqI'
            ],
            'Bio::SearchIO::waba' => [
                'Bio::SearchIO'
            ],
            'Bio::Structure::IO::pdb' => [
                'Bio::Structure::IO'
            ],
            'Bio::Search::Result::HMMERResult' => [
                'Bio::Search::Result::GenericResult'
            ],
            'Bio::Biblio::Patent' => [
                'Bio::Biblio::Ref'
            ],
            'Bio::Structure::SecStr::STRIDE::Res' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::SeqFeature::NormalizedFeatureI' => [],
            'Bio::Align::ProteinStatistics' => [
                'Bio::Root::Root',
                'Bio::Align::StatisticsI'
            ],
            'Bio::Tree::DistanceFactory' => [
                'Bio::Root::Root'
            ],
            'Bio::Structure::SecStr::DSSP::Res' => [
                'Bio::Root::Root'
            ],
            'Bio::ClusterIO' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::MapIO' => [
                'Bio::Root::Root',
                'Bio::Root::IO',
                'Bio::Factory::MapFactoryI'
            ],
            'Bio::Tools::SeqStats' => [
                'Bio::Root::Root'
            ],
            'Bio::Index::Qual' => [
                'Bio::Index::AbstractSeq'
            ],
            'Bio::Map::Position' => [
                'Bio::Root::Root',
                'Bio::Map::PositionI'
            ],
            'Bio::Search::Hit::PsiBlastHit' => [
                'Bio::Root::Root',
                'Bio::Search::Hit::HitI'
            ],
            'Bio::Expression::DataSet' => [
                'Bio::Root::Root'
            ],
            'Bio::Tools::GFF' => [
                'Bio::Root::Root',
                'Bio::SeqAnalysisParserI',
                'Bio::Root::IO'
            ],
            'Bio::DB::GFF::Aggregator::match' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::DB::GenPept' => [
                'Bio::DB::NCBIHelper'
            ],
            'Bio::Matrix::PSM::SiteMatrixI' => [
                'Bio::Root::RootI'
            ],
            'Bio::DB::GFF::Adaptor::dbi::mysqlcmap' => [
                'Bio::DB::GFF::Adaptor::dbi::mysql'
            ],
            'Bio::Graphics::ConfiguratorI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Cluster::ClusterFactory' => [
                'Bio::Factory::ObjectFactory'
            ],
            'Bio::Map::Mappable' => [
                'Bio::Root::Root',
                'Bio::Map::MappableI'
            ],
            'Bio::ClusterI' => [
                'Bio::Root::RootI'
            ],
            'Bio::LiveSeq::Repeat_Region' => [
                'Bio::LiveSeq::Range'
            ],
            'Bio::AnalysisResultI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Tools::RNAMotif' => [
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::Tools::ESTScan' => [
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::Ontology::GOterm' => [
                'Bio::Ontology::Term'
            ],
            'Bio::Matrix::Generic' => [
                'Bio::Root::Root',
                'Bio::Matrix::MatrixI'
            ],
            'Bio::Variation::RNAChange' => [
                'Bio::Variation::VariantI'
            ],
            'Bio::DB::GFF::Adaptor::berkeleydb::iterator' => [],
            'Bio::AlignIO::pfam' => [
                'Bio::AlignIO'
            ],
            'Bio::SeqIO::largefasta' => [
                'Bio::SeqIO'
            ],
            'Bio::Coordinate::ExtrapolatingPair' => [
                'Bio::Coordinate::Pair'
            ],
            'Bio::Align::StatisticsI' => [
                'Bio::Root::RootI'
            ],
            'Bio::DescribableI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Root::Root' => [
                'Bio::Root::RootI'
            ],
            'Bio::Factory::SeqAnalysisParserFactory' => [
                'Bio::Factory::DriverFactory',
                'Bio::Factory::SeqAnalysisParserFactoryI'
            ],
            'Bio::Tools::Prediction::Gene' => [
                'Bio::SeqFeature::Gene::Transcript'
            ],
            'Bio::Symbol::AlphabetI' => [],
            'Bio::DB::SeqI' => [
                'Bio::DB::RandomAccessI'
            ],
            'Bio::Taxonomy' => [
                'Bio::Root::Root'
            ],
            'Bio::Search::Hit::HMMERHit' => [
                'Bio::Search::Hit::GenericHit'
            ],
            'Bio::DB::SeqFeature::Store::berkeleydb' => [
                'Bio::DB::SeqFeature::Store'
            ],
            'Bio::Graphics::Glyph::broken_line' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Coordinate::Result::Gap' => [
                'Bio::Location::Simple',
                'Bio::Coordinate::ResultI'
            ],
            'Bio::SearchIO::Writer::TextResultWriter' => [
                'Bio::Root::Root',
                'Bio::SearchIO::SearchWriterI'
            ],
            'Bio::Location::Fuzzy' => [
                'Bio::Location::Atomic',
                'Bio::Location::FuzzyLocationI'
            ],
            'Bio::DB::SeqFeature::NormalizedFeature' => [
                'Bio::Graphics::FeatureBase',
                'Bio::DB::SeqFeature::NormalizedFeatureI'
            ],
            'Bio::Search::Processor' => [],
            'Bio::Ontology::SimpleOntologyEngine' => [
                'Bio::Root::Root',
                'Bio::Ontology::OntologyEngineI'
            ],
            'Bio::Biblio::PubmedBookArticle' => [
                'Bio::Biblio::PubmedArticle',
                'Bio::Biblio::MedlineBookArticle'
            ],
            'Bio::Search::Hit::HitI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Tools::isPcr' => [
                'Bio::Root::Root'
            ],
            'Bio::Symbol::ProteinAlphabet' => [
                'Bio::Symbol::Alphabet'
            ],
            'Bio::Search::Result::ResultFactory' => [
                'Bio::Root::Root',
                'Bio::Factory::ObjectFactoryI'
            ],
            'Bio::Matrix::PSM::IO::transfac' => [
                'Bio::Matrix::PSM::PsmHeader',
                'Bio::Matrix::PSM::IO'
            ],
            'Bio::OntologyIO::Handlers::InterPro_BioSQL_Handler' => [
                'Bio::OntologyIO::Handlers::BaseSAXHandler'
            ],
            'Bio::DB::XEMBLService' => [
                'Exporter',
                'SOAP::Lite'
            ],
            'Bio::Matrix::IO' => [
                'Bio::Root::IO'
            ],
            'Bio::SearchIO::megablast' => [
                'Bio::SearchIO'
            ],
            'Bio::Search::HSP::HSPFactory' => [
                'Bio::Root::Root',
                'Bio::Factory::ObjectFactoryI'
            ],
            'Bio::Graphics::FeatureFile' => [],
            'Bio::FeatureHolderI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Tools::Genomewise' => [
                'Bio::Tools::Genewise'
            ],
            'Bio::Map::SimpleMap' => [
                'Bio::Root::Root',
                'Bio::Map::MapI'
            ],
            'Bio::Tools::Sim4::Results' => [
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::CodonUsage::IO' => [
                'Bio::Root::IO'
            ],
            'Bio::Graphics::Glyph::transcript' => [
                'Bio::Graphics::Glyph::segments'
            ],
            'Bio::Map::OrderedPositionWithDistance' => [
                'Bio::Map::Position'
            ],
            'Bio::DB::LocationI' => [
                'Bio::Root::Root'
            ],
            'Bio::PopGen::Simulation::Coalescent' => [
                'Bio::Root::Root',
                'Bio::Factory::TreeFactoryI'
            ],
            'Bio::Phenotype::OMIM::OMIMentry' => [
                'Bio::Phenotype::Phenotype'
            ],
            'Bio::AlignIO::stockholm' => [
                'Bio::AlignIO'
            ],
            'Bio::DB::EUtilities::epost' => [
                'Bio::DB::EUtilities'
            ],
            'Bio::Cluster::SequenceFamily' => [
                'Bio::Root::Root',
                'Bio::Cluster::FamilyI'
            ],
            'Bio::Factory::LocationFactoryI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Tools::Primer::AssessorI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Tools::Tmhmm' => [
                'Bio::Root::Root',
                'Bio::Root::IO',
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::DB::EUtilities::elink' => [
                'Bio::DB::EUtilities'
            ],
            'Bio::SeqIO::game' => [
                'Bio::SeqIO'
            ],
            'Bio::DB::GFF::Util::Binning' => [
                'Exporter'
            ],
            'Bio::Structure::Model' => [
                'Bio::Root::Root'
            ],
            'Bio::Ontology::SimpleGOEngine::GraphAdaptor' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::GFF::Aggregator::ucsc_sanger22pseudo' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::Search::BlastStatistics' => [
                'Bio::Root::RootI',
                'Bio::Search::StatisticsI'
            ],
            'Bio::Tools::Promoterwise' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::DB::SeqFeature::Store::DBI::Iterator' => [],
            'Bio::TreeIO::cluster' => [
                'Bio::TreeIO'
            ],
            'Bio::SeqFeature::Gene::Poly_A_site' => [
                'Bio::SeqFeature::Gene::NC_Feature'
            ],
            'Bio::LocatableSeq' => [
                'Bio::PrimarySeq',
                'Bio::RangeI'
            ],
            'Bio::Graphics::Glyph::oval' => [
                'Bio::Graphics::Glyph::ellipse'
            ],
            'Bio::SeqIO::fasta' => [
                'Bio::SeqIO'
            ],
            'Bio::Ontology::OntologyI' => [
                'Bio::Ontology::OntologyEngineI'
            ],
            'Bio::Tree::Node' => [
                'Bio::Root::Root',
                'Bio::Tree::NodeI'
            ],
            'Bio::DB::SeqFeature::NormalizedTableFeatureI' => [
                'Bio::DB::SeqFeature::NormalizedFeatureI'
            ],
            'Bio::Map::LinkagePosition' => [
                'Bio::Map::OrderedPosition'
            ],
            'Bio::Variation::AAReverseMutate' => [
                'Bio::Root::Root'
            ],
            'Bio::AlignIO::selex' => [
                'Bio::AlignIO'
            ],
            'Bio::SearchIO::wise' => [
                'Bio::SearchIO'
            ],
            'Bio::DB::Flat::BDB::swissprot' => [
                'Bio::DB::Flat::BDB'
            ],
            'Bio::Tools::BPlite::Sbjct' => [
                'Bio::Root::Root'
            ],
            'Bio::AlignIO::psi' => [
                'Bio::AlignIO'
            ],
            'Bio::Matrix::MatrixI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Assembly::Singlet' => [
                'Bio::Assembly::Contig'
            ],
            'Bio::SearchIO::Writer::HSPTableWriter' => [
                'Bio::SearchIO::Writer::ResultTableWriter'
            ],
            'Bio::PopGen::Simulation::GeneticDrift' => [
                'Bio::Root::Root'
            ],
            'Bio::Graphics::Util' => [
                'Exporter'
            ],
            'Bio::DB::InMemoryCache' => [
                'Bio::Root::Root',
                'Bio::DB::SeqI'
            ],
            'Bio::LiveSeq::ChainI' => [],
            'Bio::Annotation::AnnotationFactory' => [
                'Bio::Root::Root',
                'Bio::Factory::ObjectFactoryI'
            ],
            'Bio::Ontology::Relationship' => [
                'Bio::Root::Root',
                'Bio::Ontology::RelationshipI'
            ],
            'Bio::Annotation::StructuredValue' => [
                'Bio::Annotation::SimpleValue'
            ],
            'Bio::TreeIO::TreeEventBuilder' => [
                'Bio::Root::Root',
                'Bio::Event::EventHandlerI'
            ],
            'Bio::SeqIO::exp' => [
                'Bio::SeqIO'
            ],
            'Bio::SeqIO::pln' => [
                'Bio::SeqIO'
            ],
            'Bio::Map::MappableI' => [
                'Bio::Map::EntityI',
                'Bio::AnnotatableI'
            ],
            'Bio::Search::SearchUtils' => [],
            'Bio::Expression::Platform' => [
                'Bio::Root::Root'
            ],
            'Bio::Tools::Glimmer' => [
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::SeqIO::game::gameSubs' => [
                'Bio::Root::Root'
            ],
            'Bio::AnalysisI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Restriction::IO::withrefm' => [
                'Bio::Restriction::IO::base'
            ],
            'Bio::SeqIO::game::featHandler' => [
                'Bio::SeqIO::game::gameSubs'
            ],
            'Bio::SeqFeature::Generic' => [
                'Bio::Root::Root',
                'Bio::SeqFeatureI',
                'Bio::FeatureHolderI'
            ],
            'Bio::SeqFeature::Computation' => [
                'Bio::SeqFeature::Generic'
            ],
            'Bio::DB::GFF::Aggregator' => [
                'Bio::Root::Root'
            ],
            'Bio::Seq::Meta::Array' => [
                'Bio::LocatableSeq',
                'Bio::Seq',
                'Bio::Seq::MetaI'
            ],
            'Bio::SeqIO::phd' => [
                'Bio::SeqIO'
            ],
            'Bio::SearchIO::IteratedSearchResultEventBuilder' => [
                'Bio::SearchIO::SearchResultEventBuilder'
            ],
            'Bio::Graph::SimpleGraph::Traversal' => [
                'Class::AutoClass'
            ],
            'Bio::Tools::Genemark' => [
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::Tools::Sigcleave' => [
                'Bio::Root::Root'
            ],
            'Bio::Species' => [
                'Bio::Taxon'
            ],
            'Bio::AlignIO::metafasta' => [
                'Bio::AlignIO'
            ],
            'Bio::Tools::Est2Genome' => [
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::Graphics::Glyph::merged_alignment' => [
                'Bio::Graphics::Glyph::graded_segments'
            ],
            'Bio::Search::Hit::Fasta' => [
                'Bio::Search::Hit::HitI'
            ],
            'Bio::Search::GenericStatistics' => [
                'Bio::Root::Root',
                'Bio::Search::StatisticsI'
            ],
            'Bio::DB::GFF::Aggregator::ucsc_unigene' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::Graphics::Glyph::tic_tac_toe' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::SeqIO::pir' => [
                'Bio::SeqIO'
            ],
            'Bio::Tools::Spidey::Exon' => [
                'Bio::SeqFeature::SimilarityPair'
            ],
            'Bio::Restriction::IO::base' => [
                'Bio::Restriction::IO'
            ],
            'Bio::DB::EUtilities::esummary' => [
                'Bio::DB::EUtilities'
            ],
            'Bio::DB::Fasta' => [
                'Bio::DB::SeqI'
            ],
            'Bio::Location::FuzzyLocationI' => [
                'Bio::LocationI'
            ],
            'Bio::DB::GFF::Adaptor::dbi::mysqlace' => [
                'Bio::DB::GFF::Adaptor::dbi::mysql',
                'Bio::DB::GFF::Adaptor::ace'
            ],
            'Bio::DB::Registry' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::EUtilities::efetch' => [
                'Bio::DB::EUtilities'
            ],
            'Bio::Annotation::TypeManager' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::SeqFeature::Segment' => [
                'Bio::SeqFeature::CollectionI',
                'Bio::RangeI'
            ],
            'Bio::Structure::Chain' => [
                'Bio::Root::Root'
            ],
            'Bio::PrimarySeq' => [
                'Bio::Root::Root',
                'Bio::PrimarySeqI',
                'Bio::IdentifiableI',
                'Bio::DescribableI'
            ],
            'Bio::Graph::IO' => [
                'Bio::Root::IO'
            ],
            'Bio::SeqIO::kegg' => [
                'Bio::SeqIO'
            ],
            'Bio::Tools::Signalp' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::DB::SeqFeature' => [
                'Bio::DB::SeqFeature::NormalizedFeature',
                'Bio::DB::SeqFeature::NormalizedTableFeatureI'
            ],
            'Bio::DB::EntrezGene' => [
                'Bio::DB::NCBIHelper'
            ],
            'Bio::Biblio::PubmedArticle' => [
                'Bio::Biblio::MedlineArticle'
            ],
            'Bio::Tools::Phylo::Phylip::ProtDist' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Biblio::Person' => [
                'Bio::Biblio::Provider'
            ],
            'Bio::Tools::Sim4::Exon' => [
                'Bio::SeqFeature::SimilarityPair'
            ],
            'Bio::Search::HSP::HSPI' => [
                'Bio::SeqFeature::SimilarityPair'
            ],
            'Bio::SearchIO::SearchWriterI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Tools::BPbl2seq' => [
                'Bio::Root::Root',
                'Bio::SeqAnalysisParserI',
                'Bio::Root::IO'
            ],
            'Bio::Matrix::IO::phylip' => [
                'Bio::Matrix::IO'
            ],
            'Bio::SeqIO::qual' => [
                'Bio::SeqIO'
            ],
            'Bio::Graph::ProteinGraph' => [
                'Bio::Graph::SimpleGraph'
            ],
            'Bio::Tools::Analysis::Protein::NetPhos' => [
                'Bio::Tools::Analysis::SimpleAnalysisBase'
            ],
            'Bio::SeqIO::excel' => [
                'Bio::SeqIO::table'
            ],
            'Bio::Graphics::Glyph::rndrect' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Phenotype::MeSH::Term' => [
                'Bio::Root::Root'
            ],
            'Bio::Search::HSP::HMMERHSP' => [
                'Bio::Search::HSP::GenericHSP'
            ],
            'Bio::Coordinate::MapperI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Graphics::Feature' => [
                'Bio::Graphics::FeatureBase'
            ],
            'Bio::Tools::Blat' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Structure::StructureI' => [
                'Bio::Root::RootI'
            ],
            'Bio::FeatureIO::ptt' => [
                'Bio::FeatureIO'
            ],
            'Bio::Coordinate::Graph' => [
                'Bio::Root::Root'
            ],
            'Bio::Biblio::IO::pubmed2ref' => [
                'Bio::Biblio::IO::medline2ref'
            ],
            'Bio::Seq::MetaI' => [
                'Bio::Root::RootI'
            ],
            'Bio::PopGen::IO::hapmap' => [
                'Bio::PopGen::IO'
            ],
            'Bio::Location::CoordinatePolicyI' => [
                'Bio::Root::RootI'
            ],
            'Bio::DB::Query::WebQuery' => [
                'Bio::Root::Root',
                'Bio::DB::QueryI'
            ],
            'Bio::Ontology::SimpleGOEngine::GraphAdaptor02' => [
                'Bio::Ontology::SimpleGOEngine::GraphAdaptor'
            ],
            'Bio::Coordinate::Collection' => [
                'Bio::Root::Root',
                'Bio::Coordinate::MapperI'
            ],
            'Bio::UpdateableSeqI' => [
                'Bio::SeqI'
            ],
            'Bio::Seq::QualI' => [
                'Bio::Root::RootI'
            ],
            'Bio::DB::GFF::Aggregator::ucsc_sanger22' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::Graph::IO::dip' => [
                'Bio::Graph::IO'
            ],
            'Bio::Graphics::Glyph::repeating_shape' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::DB::GFF::Adaptor::berkeleydb' => [
                'Bio::DB::GFF::Adaptor::memory'
            ],
            'Bio::SeqIO::ace' => [
                'Bio::SeqIO'
            ],
            'Bio::Seq::PrimaryQual' => [
                'Bio::Root::Root',
                'Bio::Seq::QualI'
            ],
            'Bio::SearchIO::Writer::GbrowseGFF' => [
                'Bio::Root::Root',
                'Bio::SearchIO::SearchWriterI'
            ],
            'Bio::SeqFeature::Similarity' => [
                'Bio::SeqFeature::Generic'
            ],
            'Bio::Search::GenericDatabase' => [
                'Bio::Root::Root',
                'Bio::Search::DatabaseI'
            ],
            'Bio::DB::GFF::Aggregator::none' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::Tools::Prediction::Exon' => [
                'Bio::SeqFeature::Gene::Exon'
            ],
            'Bio::DB::Flat::BDB::genbank' => [
                'Bio::DB::Flat::BDB'
            ],
            'Bio::LiveSeq::Gene' => [],
            'Bio::Tree::TreeI' => [
                'Bio::Tree::NodeI'
            ],
            'Bio::Map::PositionHandler' => [
                'Bio::Root::Root',
                'Bio::Map::PositionHandlerI'
            ],
            'Bio::Annotation::Reference' => [
                'Bio::Annotation::DBLink'
            ],
            'Bio::Search::Iteration::IterationI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Assembly::Scaffold' => [
                'Bio::Root::Root',
                'Bio::Assembly::ScaffoldI'
            ],
            'Bio::Tools::Phylo::PAML::Result' => [
                'Bio::Root::Root',
                'Bio::AnalysisResultI'
            ],
            'Bio::DB::GFF::Aggregator::transcript' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::DB::GFF::Adaptor::dbi::oracle' => [
                'Bio::DB::GFF::Adaptor::dbi'
            ],
            'Bio::Tools::Primer::Pair' => [
                'Bio::Root::Root'
            ],
            'Bio::Search::Hit::HitFactory' => [
                'Bio::Root::Root',
                'Bio::Factory::ObjectFactoryI'
            ],
            'Bio::Ontology::OBOterm' => [
                'Bio::Ontology::Term'
            ],
            'Bio::Annotation::Collection' => [
                'Bio::Root::Root',
                'Bio::AnnotationCollectionI',
                'Bio::AnnotationI'
            ],
            'Bio::Das::SegmentI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Graphics::Glyph::transcript2' => [
                'Bio::Graphics::Glyph::transcript'
            ],
            'Bio::Annotation::OntologyTerm' => [
                'Bio::Root::Root',
                'Bio::AnnotationI',
                'Bio::Ontology::TermI'
            ],
            'Bio::SearchIO::SearchResultEventBuilder' => [
                'Bio::Root::Root',
                'Bio::SearchIO::EventHandlerI'
            ],
            'Bio::SearchIO::Writer::BSMLResultWriter' => [
                'Bio::Root::Root',
                'Bio::SearchIO::SearchWriterI'
            ],
            'Bio::Restriction::IO' => [
                'Bio::SeqIO'
            ],
            'Bio::TreeIO::svggraph' => [
                'Bio::TreeIO'
            ],
            'Bio::Search::HSP::PSLHSP' => [
                'Bio::Search::HSP::GenericHSP'
            ],
            'Bio::Matrix::PSM::PsmHeader' => [
                'Bio::Root::Root',
                'Bio::Matrix::PSM::PsmHeaderI'
            ],
            'Bio::Graphics::Glyph::group' => [
                'Bio::Graphics::Glyph::segmented_keyglyph'
            ],
            'Bio::Variation::IO::xml' => [
                'Bio::Variation::IO'
            ],
            'Bio::Graphics::Glyph::merge_parts' => [
                'Bio::Graphics::Glyph'
            ],
            'Bio::Tools::OddCodes' => [
                'Bio::Root::Root'
            ],
            'Bio::Variation::AAChange' => [
                'Bio::Variation::VariantI'
            ],
            'Bio::DB::EUtilities::ElinkData' => [
                'Bio::Root::Root'
            ],
            'Bio::Expression::FeatureI' => [
                'Bio::Root::RootI',
                'Bio::PrimarySeqI'
            ],
            'Bio::AlignIO::msf' => [
                'Bio::AlignIO'
            ],
            'Bio::Location::Split' => [
                'Bio::Location::Atomic',
                'Bio::Location::SplitLocationI'
            ],
            'Bio::Biblio::BiblioBase' => [
                'Bio::Root::Root'
            ],
            'Bio::Tools::Run::RemoteBlast' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Seq::LargeSeqI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Graphics::Glyph::whiskerplot' => [
                'Bio::Graphics::Glyph::xyplot'
            ],
            'Bio::Annotation::Comment' => [
                'Bio::Root::Root',
                'Bio::AnnotationI'
            ],
            'Bio::Seq::BaseSeqProcessor' => [
                'Bio::Root::Root',
                'Bio::Factory::SequenceProcessorI'
            ],
            'Bio::AlignIO::prodom' => [
                'Bio::AlignIO'
            ],
            'Bio::Graphics::Glyph::diamond' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Tools::Prints' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::DB::Biblio::biofetch' => [
                'Bio::DB::DBFetch',
                'Bio::Biblio'
            ],
            'Bio::Biblio::IO::medlinexml' => [
                'Bio::Biblio::IO'
            ],
            'Bio::DB::Expression' => [
                'Bio::Root::HTTPget'
            ],
            'Bio::DB::WebDBSeqI' => [
                'Bio::DB::RandomAccessI'
            ],
            'Bio::Taxonomy::FactoryI' => [
                'Bio::Root::Root'
            ],
            'Bio::Graphics::Glyph::box' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::SeqFeature::SiRNA::Oligo' => [
                'Bio::SeqFeature::Generic'
            ],
            'Bio::AnnotationCollectionI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Biblio::MedlineArticle' => [
                'Bio::Biblio::Article'
            ],
            'Bio::Graphics::Glyph::arrow' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Biblio::Service' => [
                'Bio::Biblio::Provider'
            ],
            'Bio::Tools::RepeatMasker' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Graphics::Glyph::splice_site' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::LiveSeq::Prim_Transcript' => [
                'Bio::LiveSeq::Range'
            ],
            'Bio::DB::Failover' => [
                'Bio::Root::Root',
                'Bio::DB::RandomAccessI'
            ],
            'Bio::Biblio::WebResource' => [
                'Bio::Biblio::Ref'
            ],
            'Bio::Biblio::PubmedJournalArticle' => [
                'Bio::Biblio::PubmedArticle',
                'Bio::Biblio::MedlineJournalArticle'
            ],
            'Bio::PopGen::Population' => [
                'Bio::Root::Root',
                'Bio::PopGen::PopulationI'
            ],
            'Bio::DB::GFF::Adaptor::dbi::mysql' => [
                'Bio::DB::GFF::Adaptor::dbi'
            ],
            'Bio::Tree::Statistics' => [
                'Bio::Root::Root'
            ],
            'Bio::SeqIO::chadoxml' => [
                'Bio::SeqIO'
            ],
            'Bio::SeqFeature::Tools::Unflattener' => [
                'Bio::Root::Root'
            ],
            'Bio::SeqFeature::Primer' => [
                'Bio::Root::Root',
                'Bio::SeqFeature::Generic'
            ],
            'Bio::Restriction::EnzymeI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Taxon' => [
                'Bio::Tree::Node',
                'Bio::IdentifiableI'
            ],
            'Bio::Tools::Analysis::Protein::Sopma' => [
                'Bio::Tools::Analysis::SimpleAnalysisBase'
            ],
            'Bio::Biblio::Provider' => [
                'Bio::Biblio::BiblioBase'
            ],
            'Bio::Graphics::Glyph::flag' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Tools::HMMER::Domain' => [
                'Bio::SeqFeature::FeaturePair'
            ],
            'Bio::Location::SplitLocationI' => [
                'Bio::LocationI'
            ],
            'Bio::FeatureIO::bed' => [
                'Bio::FeatureIO'
            ],
            'Bio::LocationI' => [
                'Bio::RangeI'
            ],
            'Bio::Tools::ipcress' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::Taxonomy::flatfile' => [
                'Bio::DB::Taxonomy'
            ],
            'Bio::Matrix::PhylipDist' => [
                'Bio::Root::Root',
                'Bio::Matrix::MatrixI'
            ],
            'Bio::DB::SeqFeature::Store::memory' => [
                'Bio::DB::SeqFeature::Store'
            ],
            'Bio::Seq::RichSeqI' => [
                'Bio::SeqI'
            ],
            'Bio::Graph::SimpleGraph' => [
                'Class::AutoClass'
            ],
            'Bio::SeqIO::embl' => [
                'Bio::SeqIO'
            ],
            'Bio::Tools::AnalysisResult' => [
                'Bio::Root::Root',
                'Bio::SeqAnalysisParserI',
                'Bio::AnalysisResultI',
                'Bio::Root::IO'
            ],
            'Bio::Coordinate::Result' => [
                'Bio::Location::Split',
                'Bio::Coordinate::ResultI'
            ],
            'Bio::Biblio::IO::medline2ref' => [
                'Bio::Root::Root'
            ],
            'Bio::Tools::EMBOSS::Palindrome' => [
                'Bio::Root::IO'
            ],
            'Bio::Structure::Entry' => [
                'Bio::Root::Root',
                'Bio::Structure::StructureI'
            ],
            'Bio::DB::GFF::Aggregator::so_transcript' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::Matrix::PSM::IO::psiblast' => [
                'Bio::Matrix::PSM::PsmHeader',
                'Bio::Matrix::PSM::IO'
            ],
            'Bio::Factory::SequenceStreamI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Index::Hmmer' => [
                'Bio::Index::Abstract'
            ],
            'Bio::Graphics::Glyph::ex' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Matrix::IO::scoring' => [
                'Bio::Matrix::IO'
            ],
            'Bio::DB::SeqFeature::Store' => [
                'Bio::SeqFeature::CollectionI'
            ],
            'Bio::DB::CUTG' => [
                'Bio::WebAgent'
            ],
            'Bio::PopGen::IO::prettybase' => [
                'Bio::PopGen::IO'
            ],
            'Bio::ClusterIO::dbsnp' => [
                'Bio::ClusterIO'
            ],
            'Bio::Graph::Edge' => [
                'Bio::Root::Root',
                'Bio::IdentifiableI'
            ],
            'Bio::Root::Exception' => [
                'Error'
            ],
            'Bio::Biblio::MedlineJournalArticle' => [
                'Bio::Biblio::MedlineArticle',
                'Bio::Biblio::JournalArticle'
            ],
            'Bio::Align::DNAStatistics' => [
                'Bio::Root::Root',
                'Bio::Align::StatisticsI'
            ],
            'Bio::SeqFeature::Gene::ExonI' => [
                'Bio::SeqFeatureI'
            ],
            'Bio::Graphics::Glyph::segmented_keyglyph' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Variation::IO::flat' => [
                'Bio::Variation::IO'
            ],
            'Bio::SeqIO::game::seqHandler' => [
                'Bio::SeqIO::game::gameSubs'
            ],
            'Bio::WebAgent' => [
                'LWP::UserAgent',
                'Bio::Root::Root'
            ],
            'Bio::Biblio::Proceeding' => [
                'Bio::Biblio::Ref'
            ],
            'Bio::Tools::Run::WrapperBase' => [
                'Bio::Root::Root'
            ],
            'Bio::Map::Contig' => [
                'Bio::Map::SimpleMap'
            ],
            'Bio::CodonUsage::Table' => [
                'Bio::Root::Root'
            ],
            'Bio::Graphics::Glyph::xyplot' => [
                'Bio::Graphics::Glyph::minmax'
            ],
            'Bio::Search::Result::BlastResult' => [
                'Bio::Search::Result::GenericResult'
            ],
            'Bio::Search::DatabaseI' => [
                'Bio::Root::RootI'
            ],
            'Bio::DB::GFF::Aggregator::ucsc_genscan' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::PopGen::MarkerI' => [
                'Bio::Root::RootI',
                'Bio::AnnotatableI'
            ],
            'Bio::Annotation::DBLink' => [
                'Bio::Root::Root',
                'Bio::AnnotationI',
                'Bio::IdentifiableI'
            ],
            'Bio::Tools::SiRNA::Ruleset::saigo' => [
                'Bio::Tools::SiRNA'
            ],
            'Bio::Seq::LargeSeq' => [
                'Bio::Seq',
                'Bio::Seq::LargeSeqI'
            ],
            'Bio::FeatureIO' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::TreeIO' => [
                'Bio::Root::Root',
                'Bio::Root::IO',
                'Bio::Event::EventGeneratorI',
                'Bio::Factory::TreeFactoryI'
            ],
            'Bio::SeqIO::swiss' => [
                'Bio::SeqIO'
            ],
            'Bio::Matrix::PSM::InstanceSite' => [
                'Bio::LocatableSeq',
                'Bio::Matrix::PSM::InstanceSiteI'
            ],
            'Bio::Biblio::JournalArticle' => [
                'Bio::Biblio::Article'
            ],
            'Bio::Graphics::Glyph::alignment' => [
                'Bio::Graphics::Glyph::graded_segments'
            ],
            'Bio::Tools::Analysis::Protein::Domcut' => [
                'Bio::Tools::Analysis::SimpleAnalysisBase'
            ],
            'Bio::LiveSeq::Intron' => [
                'Bio::LiveSeq::Range'
            ],
            'Bio::Map::PositionI' => [
                'Bio::Map::EntityI',
                'Bio::RangeI'
            ],
            'Bio::Assembly::IO::phrap' => [
                'Bio::Assembly::IO'
            ],
            'Bio::Map::MapI' => [
                'Bio::Map::EntityI',
                'Bio::AnnotatableI'
            ],
            'Bio::Ontology::RelationshipFactory' => [
                'Bio::Factory::ObjectFactory'
            ],
            'Bio::Variation::VariantI' => [
                'Bio::Root::Root',
                'Bio::SeqFeature::Generic',
                'Bio::DBLinkContainerI'
            ],
            'Bio::Range' => [
                'Bio::Root::Root',
                'Bio::RangeI'
            ],
            'Bio::Matrix::PSM::IO::mast' => [
                'Bio::Matrix::PSM::PsmHeader',
                'Bio::Matrix::PSM::IO'
            ],
            'Bio::Root::IO' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::EUtilities::Cookie' => [
                'Bio::Root::Root'
            ],
            'Bio::Tools::SiRNA::Ruleset::tuschl' => [
                'Bio::Tools::SiRNA'
            ],
            'Bio::DB::GFF' => [
                'Bio::Root::Root',
                'Bio::DasI'
            ],
            'Bio::FeatureIO::gtf' => [
                'Bio::FeatureIO::gff'
            ],
            'Bio::Expression::ProbeI' => [
                'Bio::Expression::FeatureI'
            ],
            'Bio::SeqIO::tinyseq::tinyseqHandler' => [
                'Bio::Root::Root'
            ],
            'Bio::SeqIO::gcg' => [
                'Bio::SeqIO'
            ],
            'Bio::Tools::Spidey::Results' => [
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::DB::Ace' => [
                'Bio::DB::RandomAccessI'
            ],
            'Bio::SeqFeature::FeaturePair' => [
                'Bio::SeqFeature::Generic'
            ],
            'Bio::AlignIO::maf' => [
                'Bio::AlignIO'
            ],
            'Bio::SearchIO::blast' => [
                'Bio::SearchIO'
            ],
            'Bio::SeqIO::alf' => [
                'Bio::SeqIO'
            ],
            'Bio::SearchIO::blastxml' => [
                'Bio::SearchIO'
            ],
            'Bio::LiveSeq::Translation' => [
                'Bio::LiveSeq::Transcript'
            ],
            'Bio::Map::CytoPosition' => [
                'Bio::Map::Position'
            ],
            'Bio::Tools::Analysis::Protein::Mitoprot' => [
                'Bio::Tools::Analysis::SimpleAnalysisBase'
            ],
            'Bio::Search::Result::GenericResult' => [
                'Bio::Root::Root',
                'Bio::Search::Result::ResultI'
            ],
            'Bio::AlignIO::po' => [
                'Bio::AlignIO'
            ],
            'Bio::Graphics::Glyph::three_letters' => [
                'Bio::Graphics::Glyph::repeating_shape'
            ],
            'Bio::OntologyIO' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Graphics::Glyph::redgreen_box' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::SeqIO::asciitree' => [
                'Bio::SeqIO'
            ],
            'Bio::MapIO::mapmaker' => [
                'Bio::MapIO'
            ],
            'Bio::SearchIO::exonerate' => [
                'Bio::SearchIO'
            ],
            'Bio::Ontology::OBOEngine' => [
                'Bio::Root::Root',
                'Bio::Ontology::OntologyEngineI'
            ],
            'Bio::Coordinate::Utils' => [
                'Bio::Root::Root'
            ],
            'Bio::PopGen::Genotype' => [
                'Bio::Root::Root',
                'Bio::PopGen::GenotypeI'
            ],
            'Bio::Graphics::Glyph::minmax' => [
                'Bio::Graphics::Glyph::segments'
            ],
            'Bio::LiveSeq::DNA' => [
                'Bio::LiveSeq::SeqI'
            ],
            'Bio::Coordinate::ResultI' => [
                'Bio::LocationI'
            ],
            'Bio::Expression::Sample' => [
                'Bio::Root::Root'
            ],
            'Bio::SearchIO::psl' => [
                'Bio::SearchIO'
            ],
            'Bio::AnalysisParserI' => [
                'Bio::Root::RootI'
            ],
            'Bio::SeqAnalysisParserI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Graphics::Glyph::cds' => [
                'Bio::Graphics::Glyph::segmented_keyglyph',
                'Bio::Graphics::Glyph::translation'
            ],
            'Bio::SeqFeature::TypedSeqFeatureI' => [
                'Bio::SeqFeatureI'
            ],
            'Bio::DB::GFF::Aggregator::processed_transcript' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::SearchIO::axt' => [
                'Bio::SearchIO'
            ],
            'Bio::TreeIO::tabtree' => [
                'Bio::TreeIO'
            ],
            'Bio::Graph::IO::psi_xml' => [
                'Bio::Graph::IO'
            ],
            'Bio::Variation::IO' => [
                'Bio::SeqIO'
            ],
            'Bio::Graphics::Glyph::primers' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Tree::AlleleNode' => [
                'Bio::Tree::Node',
                'Bio::PopGen::IndividualI'
            ],
            'Bio::Matrix::PSM::PsmHeaderI' => [
                'Bio::Matrix::PSM::PsmI'
            ],
            'Bio::Coordinate::GeneMapper' => [
                'Bio::Root::Root',
                'Bio::Coordinate::MapperI'
            ],
            'Bio::Index::AbstractSeq' => [
                'Bio::Index::Abstract',
                'Bio::DB::SeqI'
            ],
            'Bio::DB::GFF::Util::Rearrange' => [
                'Exporter'
            ],
            'Bio::Graphics::Glyph::gene' => [
                'Bio::Graphics::Glyph::processed_transcript'
            ],
            'Bio::Biblio::BookArticle' => [
                'Bio::Biblio::Article'
            ],
            'Bio::DB::FileCache' => [
                'Bio::Root::Root',
                'Bio::DB::SeqI'
            ],
            'Bio::Graphics::Glyph::graded_segments' => [
                'Bio::Graphics::Glyph::minmax',
                'Bio::Graphics::Glyph::merge_parts'
            ],
            'Bio::Graphics::Glyph::dashed_line' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::DB::BiblioI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Expression::Contact' => [
                'Bio::Root::Root'
            ],
            'Bio::OntologyIO::Handlers::BaseSAXHandler' => [
                'Bio::Root::Root'
            ],
            'Bio::Tools::Fgenesh' => [
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::SeqFeature::SimilarityPair' => [
                'Bio::SeqFeature::FeaturePair'
            ],
            'Bio::DB::GFF::Adaptor::memory::feature_serializer' => [
                'Exporter'
            ],
            'Bio::PrimarySeqI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Search::StatisticsI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Biblio::Ref' => [
                'Bio::Biblio::BiblioBase'
            ],
            'Bio::Tools::HMMER::Results' => [
                'Bio::Root::Root',
                'Bio::Root::IO',
                'Bio::SeqAnalysisParserI'
            ],
            'Bio::PopGen::IO' => [
                'Bio::Root::IO'
            ],
            'Bio::Search::HSP::HmmpfamHSP' => [
                'Bio::Search::HSP::PullHSPI'
            ],
            'Bio::Biblio::MedlineBookArticle' => [
                'Bio::Biblio::BookArticle',
                'Bio::Biblio::MedlineArticle'
            ],
            'Bio::Biblio::TechReport' => [
                'Bio::Biblio::Ref'
            ],
            'Bio::DB::Biblio::eutils' => [
                'Bio::Biblio'
            ],
            'Bio::SeqIO::game::gameHandler' => [
                'Bio::SeqIO::game::gameSubs'
            ],
            'Bio::SeqIO::abi' => [
                'Bio::SeqIO'
            ],
            'Bio::Factory::AnalysisI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Index::EMBL' => [
                'Bio::Index::AbstractSeq'
            ],
            'Bio::Matrix::PSM::ProtPsm' => [
                'Bio::Matrix::PSM::ProtMatrix',
                'Bio::Matrix::PSM::PsmI',
                'Bio::Annotation::Collection'
            ],
            'Bio::Graphics::Glyph::wave' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::OntologyIO::simplehierarchy' => [
                'Bio::OntologyIO'
            ],
            'Bio::DB::GFF::Aggregator::coding' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::AlignIO::emboss' => [
                'Bio::AlignIO'
            ],
            'Bio::Map::OrderedPosition' => [
                'Bio::Map::Position'
            ],
            'Bio::Tools::EPCR' => [
                'Bio::Root::Root',
                'Bio::SeqAnalysisParserI',
                'Bio::Root::IO'
            ],
            'Bio::Tools::Gel' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::GFF::Adaptor::dbi::iterator' => [],
            'Bio::AlignIO::mega' => [
                'Bio::AlignIO'
            ],
            'Bio::Factory::ObjectBuilderI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Tools::Analysis::DNA::ESEfinder' => [
                'Bio::Tools::Analysis::SimpleAnalysisBase'
            ],
            'Bio::SeqIO::FTHelper' => [
                'Bio::Root::Root'
            ],
            'Bio::Tree::RandomFactory' => [
                'Bio::Root::Root',
                'Bio::Factory::TreeFactoryI'
            ],
            'Bio::Seq' => [
                'Bio::Root::Root',
                'Bio::SeqI',
                'Bio::IdentifiableI',
                'Bio::DescribableI'
            ],
            'Bio::Restriction::Analysis' => [
                'Bio::Root::Root'
            ],
            'Bio::Seq::PrimedSeq' => [
                'Bio::Root::Root',
                'Bio::SeqFeature::Generic'
            ],
            'Bio::DB::UpdateableSeqI' => [
                'Bio::DB::SeqI'
            ],
            'Bio::Ontology::Term' => [
                'Bio::Root::Root',
                'Bio::Ontology::TermI',
                'Bio::IdentifiableI',
                'Bio::DescribableI'
            ],
            'Bio::SeqIO::chaos' => [
                'Bio::SeqIO'
            ],
            'Bio::DB::GFF::Homol' => [
                'Bio::DB::GFF::Segment'
            ],
            'Bio::Index::Fastq' => [
                'Bio::Index::AbstractSeq'
            ],
            'Bio::TreeIO::nhx' => [
                'Bio::TreeIO'
            ],
            'Bio::Phenotype::PhenotypeI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Graphics::Glyph::text_in_box' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::SeqIO::ctf' => [
                'Bio::SeqIO'
            ],
            'Bio::Graphics::Glyph::processed_transcript' => [
                'Bio::Graphics::Glyph::transcript2'
            ],
            'Bio::Graphics::Glyph::image' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::DB::Flat::BDB::embl' => [
                'Bio::DB::Flat::BDB'
            ],
            'Bio::SeqIO::locuslink' => [
                'Bio::SeqIO'
            ],
            'Bio::DB::BioFetch' => [
                'Bio::DB::WebDBSeqI'
            ],
            'Bio::Search::HSP::BlastHSP' => [
                'Bio::SeqFeature::SimilarityPair',
                'Bio::Search::HSP::HSPI'
            ],
            'Bio::Tools::Alignment::Trim' => [
                'Bio::Root::Root'
            ],
            'Bio::SeqIO::fastq' => [
                'Bio::SeqIO'
            ],
            'Bio::Tree::TreeFunctionsI' => [
                'Bio::Tree::TreeI'
            ],
            'Bio::DB::GDB' => [
                'Bio::Root::Root'
            ],
            'Bio::Ontology::RelationshipI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Tools::Analysis::Protein::HNN' => [
                'Bio::Tools::Analysis::SimpleAnalysisBase'
            ],
            'Bio::Tools::IUPAC' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::EUtilities::esearch' => [
                'Bio::DB::EUtilities'
            ],
            'Bio::SeqI' => [
                'Bio::PrimarySeqI',
                'Bio::AnnotatableI',
                'Bio::FeatureHolderI'
            ],
            'Bio::Symbol::SymbolI' => [
                'Bio::Root::RootI'
            ],
            'Bio::AnnotatableI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Tools::PrositeScan' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Graphics::Glyph::Factory' => [
                'Bio::Root::Root'
            ],
            'Bio::SeqFeature::CollectionI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Tools::Eponine' => [
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::Graphics' => [],
            'Bio::Tools::Phylo::PAML::ModelResult' => [
                'Bio::Root::Root'
            ],
            'Bio::SeqFeature::Annotated' => [
                'Bio::Root::Root',
                'Bio::SeqFeatureI',
                'Bio::FeatureHolderI'
            ],
            'Bio::TreeIO::pag' => [
                'Bio::TreeIO'
            ],
            'Bio::Graphics::Glyph::track' => [
                'Bio::Graphics::Glyph'
            ],
            'Bio::SeqIO::MultiFile' => [
                'Bio::SeqIO'
            ],
            'Bio::SimpleAlign' => [
                'Bio::Root::Root',
                'Bio::Align::AlignI',
                'Bio::AnnotatableI'
            ],
            'Bio::Matrix::PSM::SiteMatrix' => [
                'Bio::Root::Root',
                'Bio::Matrix::PSM::SiteMatrixI'
            ],
            'Bio::SeqIO::lasergene' => [
                'Bio::SeqIO'
            ],
            'Bio::LiveSeq::Repeat_Unit' => [
                'Bio::LiveSeq::Repeat_Region'
            ],
            'Bio::Factory::ObjectFactory' => [
                'Bio::Root::Root',
                'Bio::Factory::ObjectFactoryI'
            ],
            'Bio::Assembly::Contig' => [
                'Bio::Root::Root',
                'Bio::Align::AlignI'
            ],
            'Bio::Map::Relative' => [
                'Bio::Root::Root',
                'Bio::Map::RelativeI'
            ],
            'Bio::Matrix::PSM::ProtMatrix' => [
                'Bio::Root::Root',
                'Bio::Matrix::PSM::SiteMatrixI'
            ],
            'Bio::Tools::Coil' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::AlignIO::nexus' => [
                'Bio::AlignIO'
            ],
            'Bio::Variation::DNAMutation' => [
                'Bio::Variation::VariantI'
            ],
            'Bio::Matrix::PSM::Psm' => [
                'Bio::Matrix::PSM::SiteMatrix',
                'Bio::Matrix::PSM::PsmI',
                'Bio::Annotation::Collection'
            ],
            'Bio::SearchIO::Writer::HitTableWriter' => [
                'Bio::SearchIO::Writer::ResultTableWriter'
            ],
            'Bio::DB::EMBL' => [
                'Bio::DB::DBFetch'
            ],
            'Bio::OntologyIO::dagflat' => [
                'Bio::OntologyIO'
            ],
            'Bio::Map::CytoMarker' => [
                'Bio::Map::Marker'
            ],
            'Bio::Map::CytoMap' => [
                'Bio::Map::SimpleMap'
            ],
            'Bio::Location::Simple' => [
                'Bio::Location::Atomic'
            ],
            'Bio::Matrix::PSM::IO::meme' => [
                'Bio::Matrix::PSM::PsmHeader',
                'Bio::Matrix::PSM::IO'
            ],
            'Bio::Tools::QRNA' => [
                'Bio::Root::IO',
                'Bio::SeqAnalysisParserI'
            ],
            'Bio::Symbol::Alphabet' => [
                'Bio::Root::Root',
                'Bio::Symbol::AlphabetI'
            ],
            'Bio::Seq::EncodedSeq' => [
                'Bio::LocatableSeq'
            ],
            'Bio::Graphics::Glyph::weighted_arrow' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::DB::GFF::Adaptor::ace' => [],
            'Bio::Graphics::Glyph::saw_teeth' => [
                'Bio::Graphics::Glyph::repeating_shape'
            ],
            'Bio::Search::Hit::PullHitI' => [
                'Bio::PullParserI',
                'Bio::Search::Hit::HitI'
            ],
            'Bio::Map::Microsatellite' => [
                'Bio::Map::Marker'
            ],
            'Bio::SeqFeature::Gene::Transcript' => [
                'Bio::SeqFeature::Generic',
                'Bio::SeqFeature::Gene::TranscriptI'
            ],
            'Bio::Graphics::Glyph::triangle' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::DB::SeqVersion' => [
                'Bio::WebAgent'
            ],
            'Bio::Index::Swissprot' => [
                'Bio::Index::AbstractSeq'
            ],
            'Bio::Ontology::PathI' => [
                'Bio::Ontology::RelationshipI'
            ],
            'Bio::Ontology::TermI' => [
                'Bio::Root::RootI'
            ],
            'Bio::SeqUtils' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::GFF::Adaptor::biofetch' => [
                'Bio::DB::GFF::Adaptor::dbi::mysql'
            ],
            'Bio::Graphics::Glyph::christmas_arrow' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Symbol::DNAAlphabet' => [
                'Bio::Symbol::Alphabet'
            ],
            'Bio::DB::GFF::Adaptor::dbi::oracleace' => [
                'Bio::DB::GFF::Adaptor::ace',
                'Bio::DB::GFF::Adaptor::dbi::oracle'
            ],
            'Bio::Factory::SequenceFactoryI' => [
                'Bio::Factory::ObjectFactoryI'
            ],
            'Bio::Tree::NodeI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Graphics::Pictogram' => [
                'Bio::Root::Root'
            ],
            'Bio::Tools::pICalculator' => [
                'Bio::Root::Root'
            ],
            'Bio::PopGen::Utilities' => [
                'Bio::Root::Root'
            ],
            'Bio::AlignIO::fasta' => [
                'Bio::AlignIO'
            ],
            'Bio::DB::Universal' => [
                'Bio::DB::RandomAccessI'
            ],
            'Bio::Map::MarkerI' => [
                'Bio::Map::MappableI'
            ],
            'Bio::Tools::Run::ParametersI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Graphics::Glyph::span' => [
                'Bio::Graphics::Glyph::anchored_arrow'
            ],
            'Bio::DB::GFF::Adaptor::memory' => [
                'Bio::DB::GFF'
            ],
            'Bio::Graphics::Glyph::ragged_ends' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Tools::FootPrinter' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Search::Result::HmmpfamResult' => [
                'Bio::Root::Root',
                'Bio::Search::Result::PullResultI'
            ],
            'Bio::Location::NarrowestCoordPolicy' => [
                'Bio::Root::Root',
                'Bio::Location::CoordinatePolicyI'
            ],
            'Bio::Tools::BPlite' => [
                'Bio::Root::Root',
                'Bio::SeqAnalysisParserI',
                'Bio::Root::IO'
            ],
            'Bio::Tree::NodeNHX' => [
                'Bio::Tree::Node'
            ],
            'Bio::Phenotype::OMIM::OMIMparser' => [
                'Bio::Root::Root'
            ],
            'Bio::Tools::Profile' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Graphics::Glyph::dot' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Graphics::RendererI' => [
                'Bio::Root::RootI'
            ],
            'Bio::SeqFeature::Gene::Intron' => [
                'Bio::SeqFeature::Gene::NC_Feature'
            ],
            'Bio::Biblio::IO' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Seq::SeqFastaSpeedFactory' => [
                'Bio::Root::Root',
                'Bio::Factory::SequenceFactoryI'
            ],
            'Bio::Graphics::FeatureBase' => [
                'Bio::Root::Root',
                'Bio::SeqFeatureI',
                'Bio::LocationI',
                'Bio::SeqI'
            ],
            'Bio::Graphics::Glyph::crossbox' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::SeqIO::interpro' => [
                'Bio::SeqIO'
            ],
            'Bio::Structure::Atom' => [
                'Bio::Root::Root'
            ],
            'Bio::Tools::Lucy' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Index::Abstract' => [
                'Bio::Root::Root'
            ],
            'Bio::Tools::MZEF' => [
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::Graphics::Glyph::toomany' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Matrix::Scoring' => [
                'Bio::Matrix::Generic'
            ],
            'Bio::Ontology::SimpleGOEngine' => [
                'Bio::Ontology::OBOEngine'
            ],
            'Bio::Search::Result::PullResultI' => [
                'Bio::PullParserI',
                'Bio::Search::Result::ResultI'
            ],
            'Bio::Index::Blast' => [
                'Bio::Index::Abstract'
            ],
            'Bio::Graphics::Glyph::dna' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::DB::GFF::Segment' => [
                'Bio::Root::Root',
                'Bio::RangeI',
                'Bio::SeqI',
                'Bio::Das::SegmentI'
            ],
            'Bio::Tools::RandomDistFunctions' => [
                'Bio::Root::Root'
            ],
            'Bio::Graphics::Glyph::two_bolts' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::DBLinkContainerI' => [
                'Bio::Root::RootI'
            ],
            'Bio::DB::GFF::Featname' => [
                'Bio::Root::RootI'
            ],
            'Bio::SearchIO::hmmer' => [
                'Bio::SearchIO'
            ],
            'Bio::Biblio::Book' => [
                'Bio::Biblio::Ref'
            ],
            'Bio::Seq::Meta' => [
                'Bio::LocatableSeq',
                'Bio::Seq::MetaI'
            ],
            'Bio::Tools::SeqPattern' => [
                'Bio::Root::Root'
            ],
            'Bio::Graphics::Glyph::ellipse' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::DB::GFF::Adaptor::dbi::mysqlopt' => [
                'Bio::DB::GFF::Adaptor::dbi::mysql'
            ],
            'Bio::Search::HSP::GenericHSP' => [
                'Bio::Search::HSP::HSPI'
            ],
            'Bio::ClusterIO::unigene' => [
                'Bio::ClusterIO'
            ],
            'Bio::Phenotype::Phenotype' => [
                'Bio::Root::Root',
                'Bio::Phenotype::PhenotypeI'
            ],
            'Bio::OntologyIO::goflat' => [
                'Bio::OntologyIO::dagflat'
            ],
            'Bio::SeqFeature::Gene::Promoter' => [
                'Bio::SeqFeature::Gene::NC_Feature'
            ],
            'Bio::Event::EventGeneratorI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Restriction::IO::bairoch' => [
                'Bio::Restriction::IO::base'
            ],
            'Bio::Variation::Allele' => [
                'Bio::PrimarySeq',
                'Bio::DBLinkContainerI'
            ],
            'Bio::SimpleAnalysisI' => [
                'Bio::Root::RootI'
            ],
            'Bio::PopGen::Individual' => [
                'Bio::Root::Root',
                'Bio::PopGen::IndividualI'
            ],
            'Bio::Root::Storable' => [
                'Bio::Root::Root'
            ],
            'Bio::Cluster::UniGeneI' => [
                'Bio::ClusterI'
            ],
            'Bio::Search::Result::ResultI' => [
                'Bio::AnalysisResultI'
            ],
            'Bio::Search::BlastUtils' => [],
            'Bio::Phenotype::Measure' => [
                'Bio::Root::Root'
            ],
            'Bio::LiveSeq::IO::BioPerl' => [
                'Bio::LiveSeq::IO::Loader'
            ],
            'Bio::DB::SeqHound' => [
                'Bio::DB::WebDBSeqI'
            ],
            'Bio::Root::RootI' => [],
            'Bio::Graphics::Glyph::translation' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::SeqIO::metafasta' => [
                'Bio::SeqIO'
            ],
            'Bio::Tools::GuessSeqFormat' => [
                'Bio::Root::Root'
            ],
            'Bio::Cluster::FamilyI' => [
                'Bio::ClusterI'
            ],
            'Bio::Tools::Pseudowise' => [
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::DB::Flat::BDB::swiss' => [
                'Bio::DB::Flat::BDB'
            ],
            'Bio::Coordinate::Result::Match' => [
                'Bio::Location::Simple',
                'Bio::Coordinate::ResultI'
            ],
            'Bio::DB::GFF::Aggregator::clone' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::Das::FeatureTypeI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Graphics::Glyph::anchored_arrow' => [
                'Bio::Graphics::Glyph::arrow'
            ],
            'Bio::DB::SeqFeature::Store::bdb' => [
                'Bio::DB::SeqFeature::Store'
            ],
            'Bio::SeqIO::entrezgene' => [
                'Bio::SeqIO'
            ],
            'Bio::SeqFeature::Gene::UTR' => [
                'Bio::SeqFeature::Gene::Exon'
            ],
            'Bio::PopGen::Statistics' => [
                'Bio::Root::Root'
            ],
            'Bio::SeqIO::tinyseq' => [
                'Bio::SeqIO'
            ],
            'Bio::SeqIO' => [
                'Bio::Root::Root',
                'Bio::Root::IO',
                'Bio::Factory::SequenceStreamI'
            ],
            'Bio::SearchIO' => [
                'Bio::Root::IO',
                'Bio::Event::EventGeneratorI',
                'Bio::AnalysisParserI'
            ],
            'Bio::Ontology::DocumentRegistry' => [
                'Bio::Root::Root'
            ],
            'Bio::Align::Utilities' => [
                'Exporter'
            ],
            'Bio::TreeIO::lintree' => [
                'Bio::TreeIO'
            ],
            'Bio::DasI' => [
                'Bio::Root::RootI',
                'Bio::SeqFeature::CollectionI'
            ],
            'Bio::Biblio::Article' => [
                'Bio::Biblio::Ref'
            ],
            'Bio::Tools::Analysis::Protein::Scansite' => [
                'Bio::Tools::Analysis::SimpleAnalysisBase'
            ],
            'Bio::Assembly::ContigAnalysis' => [
                'Bio::Root::Root'
            ],
            'Bio::Biblio::Organisation' => [
                'Bio::Biblio::Provider'
            ],
            'Bio::PopGen::IO::phase' => [
                'Bio::PopGen::IO'
            ],
            'Bio::Map::PositionHandlerI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Tree::Compatible' => [
                'Bio::Root::Root'
            ],
            'Bio::SearchIO::EventHandlerI' => [
                'Bio::Event::EventHandlerI'
            ],
            'Bio::PopGen::Marker' => [
                'Bio::Root::Root',
                'Bio::PopGen::MarkerI'
            ],
            'Bio::SeqIO::chaosxml' => [
                'Bio::SeqIO::chaos'
            ],
            'Bio::Location::AvWithinCoordPolicy' => [
                'Bio::Location::WidestCoordPolicy'
            ],
            'Bio::Tools::SeqWords' => [
                'Bio::Root::Root'
            ],
            'Bio::Variation::SeqDiff' => [
                'Bio::Root::Root'
            ],
            'Bio::Align::AlignI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Biblio::Journal' => [
                'Bio::Biblio::BiblioBase'
            ],
            'Bio::Biblio::IO::pubmedxml' => [
                'Bio::Biblio::IO::medlinexml'
            ],
            'Bio::Map::LinkageMap' => [
                'Bio::Map::SimpleMap'
            ],
            'Bio::Graphics::Glyph::lightning' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Map::RelativeI' => [
                'Bio::Root::RootI'
            ],
            'Bio::LiveSeq::Mutator' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::Query::GenBank' => [
                'Bio::DB::Query::WebQuery'
            ],
            'Bio::SeqIO::bsml' => [
                'Bio::SeqIO'
            ],
            'Bio::DB::NCBIHelper' => [
                'Bio::DB::WebDBSeqI'
            ],
            'Bio::PullParserI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Taxonomy::Taxon' => [
                'Bio::Root::Root',
                'Bio::Tree::NodeI'
            ],
            'Bio::DB::GFF::Adaptor::dbi::pg_fts' => [
                'Bio::DB::GFF::Adaptor::dbi::pg'
            ],
            'Bio::DB::EUtilities' => [
                'Bio::DB::GenericWebDBI'
            ],
            'Bio::Index::SwissPfam' => [
                'Bio::Index::Abstract'
            ],
            'Bio::FeatureIO::gff' => [
                'Bio::FeatureIO'
            ],
            'Bio::SeqFeature::SiRNA::Pair' => [
                'Bio::SeqFeature::Generic'
            ],
            'Bio::SearchIO::sim4' => [
                'Bio::SearchIO'
            ],
            'Bio::LiveSeq::Mutation' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::Taxonomy' => [
                'Bio::Root::Root'
            ],
            'Bio::Search::Iteration::GenericIteration' => [
                'Bio::Root::Root',
                'Bio::Search::Iteration::IterationI'
            ],
            'Bio::AlignIO::bl2seq' => [
                'Bio::AlignIO'
            ],
            'Bio::Graphics::Glyph::segments' => [
                'Bio::Graphics::Glyph::segmented_keyglyph'
            ],
            'Bio::TreeIO::newick' => [
                'Bio::TreeIO'
            ],
            'Bio::Location::WidestCoordPolicy' => [
                'Bio::Root::Root',
                'Bio::Location::CoordinatePolicyI'
            ],
            'Bio::Tools::BPlite::HSP' => [
                'Bio::SeqFeature::SimilarityPair'
            ],
            'Bio::DB::RefSeq' => [
                'Bio::DB::DBFetch'
            ],
            'Bio::DB::GFF::Aggregator::ucsc_softberry' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::Event::EventHandlerI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Factory::SequenceProcessorI' => [
                'Bio::Factory::SequenceStreamI'
            ],
            'Bio::PopGen::IndividualI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Tools::Phylo::Molphy' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Map::Marker' => [
                'Bio::Map::Mappable',
                'Bio::Map::MarkerI'
            ],
            'Bio::Root::HTTPget' => [
                'Bio::Root::Root'
            ],
            'Bio::Index::Fasta' => [
                'Bio::Index::AbstractSeq'
            ],
            'Bio::Search::HSP::PullHSPI' => [
                'Bio::Search::HSP::HSPI',
                'Bio::PullParserI'
            ],
            'Bio::Graphics::Panel' => [
                'Bio::Root::Root'
            ],
            'Bio::Matrix::PSM::IO' => [
                'Bio::Root::IO'
            ],
            'Bio::OntologyIO::obo' => [
                'Bio::OntologyIO'
            ],
            'Bio::SeqIO::genbank' => [
                'Bio::SeqIO'
            ],
            'Bio::DB::SwissProt' => [
                'Bio::DB::WebDBSeqI'
            ],
            'Bio::Phenotype::OMIM::OMIMentryAllelicVariant' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::GFF::Typename' => [
                'Bio::Root::Root',
                'Bio::Das::FeatureTypeI'
            ],
            'Bio::SearchIO::FastHitEventBuilder' => [
                'Bio::Root::Root',
                'Bio::SearchIO::EventHandlerI'
            ],
            'Bio::Ontology::Ontology' => [
                'Bio::Root::Root',
                'Bio::Ontology::OntologyI',
                'Bio::AnnotatableI'
            ],
            'Bio::Annotation::Target' => [
                'Bio::Root::Root',
                'Bio::AnnotationI',
                'Bio::Range'
            ],
            'Bio::OntologyIO::soflat' => [
                'Bio::OntologyIO::dagflat'
            ],
            'Bio::Factory::MapFactoryI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Graphics::Glyph::so_transcript' => [
                'Bio::Graphics::Glyph::processed_transcript'
            ],
            'Bio::SeqFeatureI' => [
                'Bio::RangeI',
                'Bio::AnnotatableI'
            ],
            'Bio::Factory::HitFactoryI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Assembly::IO' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::SeqFeature::Tools::TypeMapper' => [
                'Bio::Root::Root'
            ],
            'Bio::SeqIO::agave' => [
                'Bio::SeqIO'
            ],
            'Bio::Tools::Analysis::Protein::GOR4' => [
                'Bio::Tools::Analysis::SimpleAnalysisBase'
            ],
            'Bio::DB::SeqFeature::Store::GFF3Loader' => [
                'Bio::Root::Root'
            ],
            'Bio::Location::Atomic' => [
                'Bio::Root::Root',
                'Bio::LocationI'
            ],
            'Bio::Coordinate::Chain' => [
                'Bio::Coordinate::Collection'
            ],
            'Bio::Structure::IO' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Factory::ObjectFactoryI' => [
                'Bio::Root::RootI'
            ],
            'Bio::LiveSeq::SeqI' => [
                'Bio::Root::Root',
                'Bio::LiveSeq::ChainI',
                'Bio::PrimarySeqI'
            ],
            'Bio::AlignIO::clustalw' => [
                'Bio::AlignIO'
            ],
            'Bio::Tools::Run::StandAloneBlast' => [
                'Bio::Root::Root',
                'Bio::Tools::Run::WrapperBase',
                'Bio::Factory::ApplicationFactoryI'
            ],
            'Bio::Factory::TreeFactoryI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Seq::LargeLocatableSeq' => [
                'Bio::Seq::LargePrimarySeq',
                'Bio::LocatableSeq'
            ],
            'Bio::Perl' => [
                'Exporter'
            ],
            'Bio::PopGen::GenotypeI' => [
                'Bio::Root::RootI'
            ],
            'Bio::DB::GFF::Aggregator::ucsc_ensgene' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::SeqFeature::Gene::TranscriptI' => [
                'Bio::SeqFeatureI'
            ],
            'Bio::DB::GFF::Adaptor::memory::iterator' => [],
            'Bio::SeqIO::ztr' => [
                'Bio::SeqIO'
            ],
            'Bio::Restriction::Enzyme' => [
                'Bio::Root::Root',
                'Bio::Restriction::EnzymeI'
            ],
            'Bio::Tools::ERPIN' => [
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::TreeIO::nexus' => [
                'Bio::TreeIO'
            ],
            'Bio::Restriction::Enzyme::MultiCut' => [
                'Bio::Restriction::Enzyme'
            ],
            'Bio::Biblio::MedlineJournal' => [
                'Bio::Biblio::Journal'
            ],
            'Bio::Tools::Analysis::Protein::ELM' => [
                'Bio::Tools::Analysis::SimpleAnalysisBase'
            ],
            'Bio::Seq::SeqFactory' => [
                'Bio::Root::Root',
                'Bio::Factory::SequenceFactoryI'
            ],
            'Bio::DB::DBFetch' => [
                'Bio::DB::WebDBSeqI'
            ],
            'Bio::SeqIO::strider' => [
                'Bio::SeqIO'
            ],
            'Bio::AlignIO::mase' => [
                'Bio::AlignIO'
            ],
            'Bio::Phenotype::Correlate' => [
                'Bio::Root::Root'
            ],
            'Bio::Tools::Genscan' => [
                'Bio::Tools::AnalysisResult'
            ],
            'Bio::Biblio::Thesis' => [
                'Bio::Biblio::Ref'
            ],
            'Bio::Graphics::Glyph::pinsertion' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::DB::Flat::BDB::fasta' => [
                'Bio::DB::Flat::BDB'
            ],
            'Bio::Graphics::Glyph::pentagram' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Tools::Geneid' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Biblio::MedlineBook' => [
                'Bio::Biblio::Book'
            ],
            'Bio::Map::Physical' => [
                'Bio::Map::SimpleMap'
            ],
            'Bio::LiveSeq::Chain' => [],
            'Bio::SeqFeature::AnnotationAdaptor' => [
                'Bio::Root::Root',
                'Bio::AnnotationCollectionI',
                'Bio::AnnotatableI'
            ],
            'Bio::Tools::Primer3' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Ontology::OntologyEngineI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Tools::Seg' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Graphics::Glyph::heterogeneous_segments' => [
                'Bio::Graphics::Glyph::graded_segments'
            ],
            'Bio::Matrix::PSM::IO::masta' => [
                'Bio::Matrix::PSM::IO'
            ],
            'Bio::Index::GenBank' => [
                'Bio::Index::AbstractSeq'
            ],
            'Bio::SeqFeature::Gene::Exon' => [
                'Bio::SeqFeature::Generic',
                'Bio::SeqFeature::Gene::ExonI'
            ],
            'Bio::Tools::HMMER::Set' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::SeqVersion::gi' => [
                'Bio::DB::SeqVersion'
            ],
            'Bio::Graphics::Glyph::extending_arrow' => [
                'Bio::Graphics::Glyph::anchored_arrow'
            ],
            'Bio::Phenotype::OMIM::MiniMIMentry' => [
                'Bio::Root::Root'
            ],
            'Bio::Matrix::PSM::PsmI' => [
                'Bio::Matrix::PSM::SiteMatrixI'
            ],
            'Bio::AlignIO::meme' => [
                'Bio::AlignIO'
            ],
            'Bio::DB::GFF::Adaptor::dbi::caching_handle' => [
                'Bio::Root::Root'
            ],
            'Bio::Ontology::OntologyStore' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::Biblio::pdf' => [
                'Bio::Biblio'
            ],
            'Bio::Restriction::IO::itype2' => [
                'Bio::Restriction::IO::base'
            ],
            'Bio::Map::FPCMarker' => [
                'Bio::Root::Root',
                'Bio::Map::MappableI'
            ],
            'Bio::DB::GenBank' => [
                'Bio::DB::NCBIHelper'
            ],
            'Bio::Search::HSP::WABAHSP' => [
                'Bio::Search::HSP::GenericHSP'
            ],
            'Bio::Graphics::Glyph::line' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Tree::Draw::Cladogram' => [
                'Bio::Root::Root'
            ],
            'Bio::LiveSeq::AARange' => [
                'Bio::LiveSeq::SeqI'
            ],
            'Bio::SeqFeature::Collection' => [
                'Bio::Root::Root'
            ],
            'Bio::Seq::TraceI' => [],
            'Bio::DB::Expression::geo' => [
                'Bio::DB::Expression'
            ],
            'Bio::DB::XEMBL' => [
                'Bio::DB::RandomAccessI'
            ],
            'Bio::AlignIO::largemultifasta' => [
                'Bio::AlignIO',
                'Bio::SeqIO',
                'Bio::SimpleAlign'
            ],
            'Bio::DB::EUtilities::egquery' => [
                'Bio::DB::EUtilities'
            ],
            'Bio::SeqFeature::Gene::GeneStructureI' => [
                'Bio::SeqFeatureI'
            ],
            'Bio::Tools::Phylo::Molphy::Result' => [
                'Bio::Root::Root'
            ],
            'Bio::Tools::CodonTable' => [
                'Bio::Root::Root'
            ],
            'Bio::Structure::Residue' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::Biblio::soap' => [
                'Bio::Biblio'
            ],
            'Bio::Seq::SequenceTrace' => [
                'Bio::Root::Root',
                'Bio::Seq::Quality',
                'Bio::Seq::TraceI'
            ],
            'Bio::Taxonomy::Node' => [
                'Bio::Taxon'
            ],
            'Bio::Tools::Primer::Feature' => [
                'Bio::SeqFeature::Generic'
            ],
            'Bio::Restriction::Enzyme::MultiSite' => [
                'Bio::Restriction::Enzyme'
            ],
            'Bio::SearchIO::fasta' => [
                'Bio::SearchIO'
            ],
            'Bio::DB::MeSH' => [
                'Bio::Tools::Analysis::SimpleAnalysisBase'
            ],
            'Bio::Tools::Primer::Assessor::Base' => [
                'Bio::Root::Root'
            ],
            'Bio::SeqFeature::PositionProxy' => [
                'Bio::Root::Root',
                'Bio::SeqFeatureI'
            ],
            'Bio::Align::PairwiseStatistics' => [
                'Bio::Root::Root',
                'Bio::Align::StatisticsI'
            ],
            'Bio::SeqFeature::Tools::IDHandler' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::GFF::RelSegment' => [
                'Bio::DB::GFF::Segment'
            ],
            'Bio::LiveSeq::Transcript' => [
                'Bio::LiveSeq::SeqI'
            ],
            'Bio::Tools::Alignment::Consed' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::DB::EUtilities::einfo' => [
                'Bio::DB::EUtilities'
            ],
            'Bio::Seq::LargePrimarySeq' => [
                'Bio::PrimarySeq',
                'Bio::Root::IO',
                'Bio::Seq::LargeSeqI'
            ],
            'Bio::Restriction::EnzymeCollection' => [
                'Bio::Root::Root'
            ],
            'Bio::Search::Hit::HmmpfamHit' => [
                'Bio::Root::Root',
                'Bio::Search::Hit::PullHitI'
            ],
            'Bio::Cluster::UniGene' => [
                'Bio::Root::Root',
                'Bio::Cluster::UniGeneI',
                'Bio::IdentifiableI',
                'Bio::DescribableI',
                'Bio::AnnotatableI',
                'Bio::Factory::SequenceStreamI'
            ],
            'Bio::SeqIO::bsml_sax' => [
                'Bio::SeqIO',
                'XML::SAX::Base'
            ],
            'Bio::AlignIO' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::PopGen::PopStats' => [
                'Bio::Root::Root'
            ],
            'Bio::Coordinate::Pair' => [
                'Bio::Root::Root',
                'Bio::Coordinate::MapperI'
            ],
            'Bio::Tree::Tree' => [
                'Bio::Root::Root',
                'Bio::Tree::TreeI',
                'Bio::Tree::TreeFunctionsI'
            ],
            'Bio::Expression::FeatureGroup' => [
                'Bio::Root::Root',
                'Bio::Expression::FeatureI'
            ],
            'Bio::Seq::SeqWithQuality' => [
                'Bio::Root::Root',
                'Bio::PrimarySeqI',
                'Bio::Seq::QualI'
            ],
            'Bio::Tools::BPpsilite' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::Search::Hit::GenericHit' => [
                'Bio::Root::Root',
                'Bio::Search::Hit::HitI'
            ],
            'Bio::DB::SeqFeature::Store::DBI::mysql' => [
                'Bio::DB::SeqFeature::Store'
            ],
            'Bio::SeqFeature::Tools::FeatureNamer' => [
                'Bio::Root::Root'
            ],
            'Bio::DB::GFF::Aggregator::alignment' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::IdCollectionI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Biblio' => [
                'Bio::Root::Root',
                'Bio::DB::BiblioI'
            ],
            'Bio::Ontology::RelationshipType' => [
                'Bio::Ontology::Term'
            ],
            'Bio::Graphics::Glyph::generic' => [
                'Bio::Graphics::Glyph'
            ],
            'Bio::DB::Taxonomy::entrez' => [
                'Bio::WebAgent',
                'Bio::DB::Taxonomy'
            ],
            'Bio::Matrix::PSM::InstanceSiteI' => [
                'Bio::Root::RootI'
            ],
            'Bio::SearchIO::hmmer_pull' => [
                'Bio::SearchIO',
                'Bio::PullParserI'
            ],
            'Bio::SeqIO::tab' => [
                'Bio::SeqIO'
            ],
            'Bio::DB::GFF::Aggregator::ucsc_acembly' => [
                'Bio::DB::GFF::Aggregator'
            ],
            'Bio::LiveSeq::IO::Loader' => [],
            'Bio::Factory::FTLocationFactory' => [
                'Bio::Root::Root',
                'Bio::Factory::LocationFactoryI'
            ],
            'Bio::Tools::Analysis::SimpleAnalysisBase' => [
                'Bio::WebAgent',
                'Bio::SimpleAnalysisI'
            ],
            'Bio::Tools::Grail' => [
                'Bio::Root::IO'
            ],
            'Bio::AnnotationI' => [
                'Bio::Root::RootI'
            ],
            'Bio::Graphics::Glyph::protein' => [
                'Bio::Graphics::Glyph::generic'
            ],
            'Bio::Tools::Genewise' => [
                'Bio::Root::Root',
                'Bio::Root::IO'
            ],
            'Bio::SearchIO::blasttable' => [
                'Bio::SearchIO'
            ],
            'Bio::SeqIO::table' => [
                'Bio::SeqIO'
            ]
        };
        #}}}
        foreach ( keys %$isa ) {
            my $parent = $isa->{$_};
            foreach my $p ( @$parent ) {
                push @{$risa->{$p}}, $_;
            }
        }
    }
    my ($tree, $show_child);
    parse_args(\@args, {'-child'=> \$show_child, '-tree' => \$tree });
    save_history(\@args);
    my $db = ( $show_child ? $risa : $isa );
    my @history;
    my $cnt = 0;
    if ( $tree ) {
        eval { require Data::TreeDumper };
        if ( $@ ) {
            print "The Data::TreeDumper seem not installed.\n",
                "Use \"cpan -i Data::TreeDumper\" to install it first.\n";
            return;
        }
        foreach my $mod ( @args ) {
            next if !exists $db->{$mod};
            print Data::TreeDumper::DumpTree(
                [ $mod ],
                $mod,
                FILTER => sub {
                    my $s = shift;
                    if ( ref($s) eq 'ARRAY' ) {
                        my $i = 0;
                        return (
                            'ARRAY',
                            [ map { [$_] } @{$db->{$s->[0]}} ],
                            map {
                                push @history, $_;
                                $cnt++;
                                [ $i++, $_ . "($cnt)" ]
                            } @{$db->{$s->[0]}}
                        );
                    }
                    return(Data::TreeDumper::DefaultNodesToDisplay($s)) ;
                },
                USE_ASCII => 1,
                DISPLAY_ADDRESS => 0,
            );
        }
    } else {
        foreach my $mod ( @args ) {
            next if !exists $db->{$mod};
            print "* $mod\n";
            foreach ( @{$db->{$mod}} ) {
                $cnt++;
                print " ", sprintf("%3d. ", $cnt), $_, "\n";
                push @history, $_;
            }
        }
    }
    if ( @history ) {
        $module_history->insert(
            [ "isa " . ( $show_child ? "-child " : "") .
                  ($tree ? "-tree " : "") .
                      join(" ", @args),
              \@history ]);
    }
}

sub search {
    my @args = @_;
    my $ignorecase = $Config{ignorecase};
    my $case;
    my $is_method;
    parse_args(
        \@args,
        {
            '-ignorecase' => \$ignorecase,
            '-case' => \$case,
            '-method' => \$is_method,
        } );
    unless ( $case ) {
        $case = !$ignorecase;
    }
    my $pattern = shift @args;
    if ( !$case ) {
        $pattern = '(?i)'.$pattern;
    }
    my $i = 1;
    if ( $is_method ) {
        my @table = map {
            my $first = $_;
            $first =~ /^(.+)::/;
            my $package_name = $1;
            my $return = trim(Deobfuscator::get_method_docs($methods, $first, 'returns'));
            if ( $return eq '0' ) {
                $return = 'not documented';
            }
            my $usage = trim(Deobfuscator::get_method_docs($methods, $first, 'usage'));
            if ( $usage eq '0' ) {
                $usage = 'not documented';
            }
            [
                $i++,
                substr($first, length($package_name)+2),
                $package_name,
                $return,
                $usage,
            ]
        } grep { /$pattern/ } sort keys %$methods;
        return unless @table;
        trim_table(\@table);
        print_table(
            \@table,
            header => ['Id', 'Method', 'Class', 'Return', 'Usage'],
            style => $Config{table_style},
            max_width => $Config{max_width},
            width => $Config{width}{method},
            row_separator => $Config{row_separator}{method},
        );
        $method_history->insert(
            ["search -method " . ( $case ? "-case " : "-ignorecase ") . $pattern,
             [map { $_->[2]."::".$_->[1] } @table]]
        );
    } else {
        my @table = map {
            [ $i++, $_, trim(normal_space(Deobfuscator::get_pkg_docs($packages, $_, 'short_desc'))) ]
        } grep { /$pattern/ } sort keys %$packages;
        return unless @table;
        trim_table(\@table);
        print_table(
            \@table,
            header => ["Id", "Module", "Description"],
            style => $Config{table_style},
            max_width => $Config{max_width},
            width => $Config{width}{search},
            row_separator => $Config{row_separator}{search},
        );
        $module_history->insert(
            ["search " . ( $case ? "-case " : "-ignorecase " ) . $pattern,
             [map { $_->[1] } @table]]
        );
    }
}
    
sub method {
    my @args = @_;
    my ($sortby, $remove_root);
    parse_args(\@args,
               {
                   '-sort|1'=> \$sortby,
                   -remove_root => \$remove_root
               });
    $sortby = (defined $sortby ? $sortby->[0] : $Config{sort_method_by});
    $remove_root = ($remove_root xor $Config{remove_root_method});
    save_history(\@args);
    my (@all_method, @methods);
    my $i = 1;
    foreach ( @args ) {
        my $remove = $remove_root;
        if ( /^Bio::Root::RootI?/ ) {
            $remove = 0;
        }
        print "* $_\n";
        my @table;
        my $all = eval { Deobfuscator::return_methods($_) };
        if ( $@ ) {
            print "Can't find methods for $_:\n$@\n";
            return;
        }
        my %full;
        foreach my $array_ref ( @{ $all->{$_} } ) {
            my $key = $array_ref->[1] . "::" . $array_ref->[0];
            next if $remove && $key =~ /^Bio::Root::RootI?::/;
            $full{$key} = $array_ref->[0];
        }
        if ( 'class' =~ /^\Q$sortby\E/ ) {
            @methods = sort keys %full;
        }
        else {
            @methods = sort { $full{$a} cmp $full{$b} } keys %full
        }
        foreach my $first ( @methods ) {
            my @row;
            push @row, $i++;
            $first =~ /^(.+)::/;
            my $package_name = $1;
            my $return = trim(Deobfuscator::get_method_docs($methods, $first, 'returns'));
            if ( $return eq '0' ) {
                $return = 'not documented';
            }
            my $usage = trim(Deobfuscator::get_method_docs($methods, $first, 'usage'));
            if ( $usage eq '0' ) {
                $usage = 'not documented';
            }
            push @row, ($full{$first}, $package_name, $return, $usage);
            push @table, \@row;
        }
        print_table(
            \@table,
            header => ['Id', 'Method', 'Class', 'Return', 'Usage'],
            style => $Config{table_style},
            max_width => $Config{max_width},
            width => $Config{width}{method},
            row_separator => $Config{row_separator}{method},
        );
        push @all_method, @methods;
    }
    if ( @all_method ) {
        $method_history->insert(
            [join(" ", "method", @args), 
             \@all_method]
        );
    }
}

sub desc {
    my @args = @_;
    my ($short);
    parse_args(\@args, {'-short' => \$short });
    save_history(\@args);
    if ( $short ) {
        print_table(
            [ map {
                [ $_, trim(Deobfuscator::get_pkg_docs($packages, $_, 'short_desc')) ]
            } @args ],
            style => $Config{table_style},
            max_width => $Config{max_width},
            width => $Config{width}{desc},
            row_separator => $Config{row_separator}{desc},
        );
    } else {
        foreach ( @args ) {
            print "* $_\n";
            print Deobfuscator::get_pkg_docs($packages, $_, 'desc');
            print "\n";
        }
    }
}
#}}}

#{{{  Utils
sub add_abbrev {
    my ($hashref, @abbv) = @_;
    my %table = map {$_ => 1} keys %$hashref;
 WORD:
    foreach my $word (@abbv) {
        for (my $len = (length $word) - 1; $len > 0; --$len) {
            my $abbrev = substr($word,0,$len);
            my $seen = ++$table{$abbrev};
            if ($seen == 1) {   # We're the first word so far to have
                # this abbreviation.
                $hashref->{$abbrev} = $word;
            } elsif ($seen == 2) { # We're the second word to have this
                # abbreviation, so we can't use it.
                delete $hashref->{$abbrev};
            } else {         # We're the third word to have this
                # abbreviation, so skip to the next word.
                next WORD;
            }
        }
    }
    # Non-abbreviations always get entered, even if they aren't unique
    foreach my $word (@abbv) {
        $hashref->{$word} = $word;
    }
}

sub uniq {
    my (%seen, @uniq);
    foreach ( @_ ) {
        next if exists $seen{$_};
        push @uniq, $_;
    }
    return @uniq;
}

sub trim {
    $_[0] =~ s/^\s+//;
    $_[0] =~ s/\s+$//;
    return $_[0];
}

sub normal_space {
    $_[0] =~ s/[ \t]+/ /g;
    return $_[0];
}

sub parse_args {
    my ($args, $options) = @_;
    return if $#$args == -1;
    my @options;
    foreach ( keys %$options ) {
        if ( /^(.*)\|(\d+)$/) {
            push @options, $1;
            $options->{$1} = $2;
        } else {
            push @options, $_;
        }
    }
    my %abbrev = abbrev(@options);
    while ( defined $args->[0] && exists $abbrev{$args->[0]} ) {
        my $opt = $abbrev{$args->[0]};
        if ( exists $options->{$opt} && !ref $options->{$opt} ) {
            shift @$args;
            my @val = splice(@$args, 0, $options->{$opt});
            ${$options->{$opt."|".$options->{$opt}}} = \@val;
        } else {
            ${$options->{$opt}} = 1;
            shift @$args;
        }
    }
}

# col width prorioty: length > width > max_width
sub print_table {
    my ($table, %options) = @_;
    return unless $#$table != -1;
    my ($header, $valign, $halign, $style, $row_separator,
        $max_width, $width) = (
            $options{header},
            $options{valign},
            $options{halign},
            $options{style},
            $options{row_separator},
            $options{max_width},
            $options{width},
        );
    if ( $style eq 'tab' ) {
        foreach ( $header, @$table ) {
            print join("\t", @{$_}), "\n";
        }
        return;
    }
    local $Text::Wrap::columns;
    if ( !defined $max_width ) {
        $max_width = 1000;
    }
    my %table_style = (
        'orgtbl' => {
            'horizontal' => '-',
            'vertical' => '|',
            'center' => '+',
            'leftup_corner' => '|',
            'rightup_corner' => '|',
            'leftbot_corner' => '|',
            'rightbot_corner' => '|',
            'up_edge' => '+',
            'left_edge' => '|',
            'right_edge' => '|',
            'bot_edge' => '+',
        },
        'table' => {
            'horizontal' => '-',
            'vertical' => '|',
            'center' => '+',
            'leftup_corner' => '+',
            'rightup_corner' => '+',
            'leftbot_corner' => '+',
            'rightbot_corner' => '+',
            'up_edge' => '+',
            'left_edge' => '+',
            'right_edge' => '+',
            'bot_edge' => '+',
        },
    );
    if ( !defined $style || !exists $table_style{$style} ) {
        $style = 'table';
    }
    my %table_char = %{$table_style{$style}};
    my $cols = $#{$table->[0]};
    my $last = $#$table;
    my $i = 0;
    my @colwid;
    if ( $header ) {
        @colwid = map { max(length($_), 1) } @$header;
    } else {
        @colwid = (3)x($cols+1);
    }
    foreach my $c ( 0..$cols ) {
        $colwid[$c] = max($colwid[$c],
                          map { max(length($_->[$c]), 1) } @$table);
    }
    @colwid = map { min($_+2, $max_width) } @colwid;
    if ( defined $width ) {
        @colwid = map {
            defined $width->[$_] ?
                min($width->[$_], $colwid[$_]) : $colwid[$_]
            } 0..$#colwid;
    }
    my $top = $table_char{leftup_corner} .
        join($table_char{up_edge}, map { $table_char{horizontal} x $_ } @colwid) .
            $table_char{rightup_corner}."\n";
    my $center = $table_char{left_edge} .
        join($table_char{center}, map { $table_char{horizontal} x $_ } @colwid) .
            $table_char{right_edge}."\n";
    my $bottom = $table_char{leftbot_corner} .
        join($table_char{bot_edge}, map { $table_char{horizontal} x $_ } @colwid) .
            $table_char{rightbot_corner}."\n";
    my $fill = sub {
        my ($str, $len, $just) = @_;
        if ( defined $just && $just == 2 ) { # right
            return ' 'x($len-length($str)).$str;
        } elsif ( defined $just && $just == 1 ) { # center
            my $l = int(($len-length($str))/2);
            my $r = ($len-length($str)-$l);
            return ' 'x$l . $str . ' 'x$r;
        } else {                # left
            return $str . ' 'x($len-length($str));
        }
    };
    my $format_row = sub {
        my $row = shift;
        my (@lines, $max);
        $max = 0;
        foreach my $c ( 0..$cols ) {
            my $len = length($row->[$c]);
            my @row_lines;
            if ( $len <= $colwid[$c]-2 ) {
                push @row_lines, $row->[$c];
            } else {
                $Text::Wrap::columns = $colwid[$c]-2;
                @row_lines = split("\n", wrap('', '', $row->[$c]));
            }
            if ( $halign && $halign eq 'center' ) {
                foreach ( @row_lines ) {
                    $_ = $fill->($_, $colwid[$c], 1);
                }
            } else {
                foreach ( @row_lines ) {
                    $_ = ' ' . $fill->($_, $colwid[$c]-2) . ' ';
                }
            }
            $max = max($max, $#row_lines);
            push @lines, \@row_lines;
        }
        if ( $max != 0 ) {
            foreach ( 0..$cols ) {
                my $lines = $lines[$_];
                if ( $#$lines != $max ) {
                    if ( defined $valign && $valign ) {
                        my $l = int(($max-$#$lines)/2);
                        my $r = ($max-$#$lines-$l);
                        unshift @$lines, (' 'x$colwid[$_])x$l;
                        push @$lines, (' 'x$colwid[$_])x$r;
                    } else {
                        push @$lines, (' 'x$colwid[$_])x($max-$#$lines);
                    }
                }
            }
        }
        my $text = "";
        foreach my $i ( 0..$max ) {
            $text .= $table_char{vertical} .
                join($table_char{vertical},
                     map { $_->[$i] } @lines) .
                         $table_char{vertical}."\n";
        }
        return $text;
    };
    print $top;
    if ( $header) {
        print $format_row->($header);
        print $center;
    }
    foreach ( @$table ) {
        print $format_row->($_);
        if ( $row_separator && $i != $last ) {
            print $center;
        }
        $i++;
    }
    print $bottom;
}
#}}}

__END__

=head1 NAME

deob -  A command line interface to Deobfuscaotr.pm

=head1 SYNOPSIS

perl deob.pl - console interface of Deobfuscaotr

=head1 DESCRIPTION

This script is an console version of Deobfuscaotr. It is designed
for easily query method and module documents without a web server.

This is a session of using the program:

    $ perl deob.pl
    deob> se SeqIO
    +----+-------------------------------------------------+--------------------------------------------------+
    | Id | Module                                          | Description                                      |
    +----+-------------------------------------------------+--------------------------------------------------+
    | 1  | Bio::Bio::SeqIO::Handler::GenericRichSeqHandler | Bio::HandlerI-based data handler for             |
    |    |                                                 | GenBank/EMBL/UniProt (and other) sequence data   |
    | 2  | Bio::SeqIO                                      | Handler for SeqIO Formats                        |
    | .....                                                                                                   |
    | 52 | Bio::SeqIO::ztr                                 | ztr trace sequence input/output stream           |
    +----+-------------------------------------------------+--------------------------------------------------+
    deob> se seqfe
    +----+----------------------------------------------+--------------------------------------------------+
    | Id | Module                                       | Description                                      |
    +----+----------------------------------------------+--------------------------------------------------+
    | 1  | Bio::DB::SeqFeature                          | Normalized feature for use with                  |
    |    |                                              | Bio::DB::SeqFeature::Store                       |
    | 2  | Bio::DB::SeqFeature::NormalizedFeature       | Normalized feature for use with                  |
    |    |                                              | Bio::DB::SeqFeature::Store                       |
    | ......                                                                                               |   
    | 42 | Bio::SeqFeatureI                             | Abstract interface of a Sequence Feature         |
    +----+----------------------------------------------+--------------------------------------------------+
    deob> se -c seqfe
    deob> hi
    1. search -ignorecase (?i)SeqIO
        1. Bio::Bio::SeqIO::Handler::GenericRichSeqHandler
        2. Bio::SeqIO
       ...
    2. search -ignorecase (?i)seqfe
        1. Bio::DB::SeqFeature
        2. Bio::DB::SeqFeature::NormalizedFeature
       ...
    deob> me 42
    * Bio::SeqFeatureI
    +----+-----------------------+------------------+------------------------------+------------------------------+
    | Id | Method                | Class            | Return                       | Usage                        |
    +----+-----------------------+------------------+------------------------------+------------------------------+
    | 1  | contains              | Bio::RangeI      | true if the argument is      | if($r1->contains($r2) { do   |
    |    |                       |                  | totally contained within     | stuff }                      |
    |    |                       |                  | this range                   |                              |
    +----+-----------------------+------------------+------------------------------+------------------------------+
    | 2  | disconnected_ranges   | Bio::RangeI      | a list of objects of the     | my @disc_ranges =            |
    |    |                       |                  | same type as the input       | Bio::Range->disconnected_ra  |
    |    |                       |                  | (conforms to RangeI)         | nges(@ranges);               |
    | .....                                                                                                       |
    +----+-----------------------+------------------+------------------------------+------------------------------+
    | 37 | source_tag            | Bio::SeqFeatureI | a string                     | $tag = $feat->source_tag()   |
    +----+-----------------------+------------------+------------------------------+------------------------------+
    | 38 | spliced_seq           | Bio::SeqFeatureI | A L<Bio::PrimarySeqI> object | $seq =                       |
    |    |                       |                  |                              | $feature->spliced_seq()      |
    |    |                       |                  |                              | $seq =                       |
    |    |                       |                  |                              | $feature_with_remote_locati  |
    |    |                       |                  |                              | ons->spliced_seq($db_for_se  |
    |    |                       |                  |                              | qs)                          |
    +----+-----------------------+------------------+------------------------------+------------------------------+
    deob> de
    * Bio::SeqFeatureI
    
    This interface is the functions one can expect for any Sequence
    Feature, whatever its implementation or whether it is a more complex
    type (eg, a Gene). This object does not actually provide any
    implemention, it just provides the definitions of what methods one can
    call. See Bio::SeqFeature::Generic for a good standard implementation
    of this object
    
    deob> de -s 
    +------------------+------------------------------------------+
    | Bio::SeqFeatureI | Abstract interface of a Sequence Feature |
    +------------------+------------------------------------------+
    deob> show 37
    * Bio::SeqFeatureI::source_tag
    +----------+--------------------------------------------------+
    | Title    | source_tag                                       |
    | Usage    | $tag = $feat->source_tag()                       |
    | Function | Returns the source tag for a feature, eg,        |
    |          | 'genscan'                                        |
    | Returns  | a string                                         |
    | Args     | none                                             |
    +----------+--------------------------------------------------+
    deob> hi -m 
    1. method Bio::SeqFeatureI
        1. Bio::RangeI::contains
        2. Bio::RangeI::disconnected_ranges
        3. Bio::RangeI::end
        4. Bio::RangeI::equals
       ...
    deob> hi -s 1
    1. search -ignorecase (?i)seqfe
        1. Bio::DB::SeqFeature
        2. Bio::DB::SeqFeature::NormalizedFeature
       .....
       42. Bio::SeqFeatureI
    deob> h 
    Unknown command "h"
    deob> alias h help
    "h" alias to "help"
    deob> h 
    Syntax: command [options] [parameters]
    Available commands:
      alias    [ -quiet ] alias command 
      desc     [ -short ] [ module ]
      exit  
      help     [ command ]
      history  [ -method -show_all ] number
      isa      [ -tree -child ] [ modlue ]
      method   [-sort method|class ] [ module ]
      pop      [ -method ] [ number ]
      quit  
      search   [ -ignorecase -case -method ] pattern
      show     method
      synopsis [ module ]
            
    deob> isa 
    * Bio::SeqFeatureI
       1. Bio::RangeI
       2. Bio::AnnotatableI
    deob> isa -t 
    Bio::SeqFeatureI
    |- Bio::RangeI(1) 
    |  `- Bio::Root::RootI(3) 
    `- Bio::AnnotatableI(2) 
       `- Bio::Root::RootI(4) 
    deob> hi
    1. search -ignorecase (?i)SeqIO
        1. Bio::Bio::SeqIO::Handler::GenericRichSeqHandler
        2. Bio::SeqIO
        3. Bio::SeqIO::FTHelper
        4. Bio::SeqIO::MultiFile
       ...
    2. search -ignorecase (?i)seqfe
        1. Bio::DB::SeqFeature
        2. Bio::DB::SeqFeature::NormalizedFeature
        3. Bio::DB::SeqFeature::NormalizedFeatureI
        4. Bio::DB::SeqFeature::NormalizedTableFeatureI
       ...
    3. isa Bio::SeqFeatureI
        1. Bio::RangeI
        2. Bio::AnnotatableI
    4. isa -tree Bio::SeqFeatureI
        1. Bio::RangeI
        2. Bio::AnnotatableI
        3. Bio::Root::RootI
        4. Bio::Root::RootI
    deob> pop
    deob> hi
    1. search -ignorecase (?i)SeqIO
        1. Bio::Bio::SeqIO::Handler::GenericRichSeqHandler
        2. Bio::SeqIO
        3. Bio::SeqIO::FTHelper
        4. Bio::SeqIO::MultiFile
       ...
    2. search -ignorecase (?i)seqfe
        1. Bio::DB::SeqFeature
        2. Bio::DB::SeqFeature::NormalizedFeature
        3. Bio::DB::SeqFeature::NormalizedFeatureI
        4. Bio::DB::SeqFeature::NormalizedTableFeatureI
       ...
    3. isa Bio::SeqFeatureI
        1. Bio::RangeI
        2. Bio::AnnotatableI
    deob> q
    
    Byebye!

=head1 CONFIGURATION

The configuration file should be the file with name ".deob" inside the
home directory. If File::HomeDir is install, the home directory is
determine by the module, otherwise it is in $ENV{HOME}. For the OS the
doesn't have $ENV{HOME}, the file could be with same directory with
this directory.

The file could contain any perl code. This is an example:

   %Config = (
       %Config,
       'packages' => "c:/Program Files/Apache Group/Apache2/cgi-bin/packages.db",
       'methods' => "c:/Program Files/Apache Group/Apache2/cgi-bin/methods.db",
   );
   alias("-q", "?", "help");
   # helpful for debug
   add_abbrev(\%cmd_abbv, 'eval');
   $commands{'eval'} = \&eval_input;

The customizable value in %Config is as following:

  packages           - the full path of packages.db
  methods            - the full path of methods.db
  ignorecase         - ignore case for search pattern and commands
  sort_method_by     - the order for list methods
  remove_root_method - list methods that exclude root method
  history_length     - the length of history ring
  history_max_items  - the max number of item to list using command "history"
  max_rows           - Max rows in the table(in case too slow after search)
  table_style        - Table output style, one of ('table', 'orgtbl', 'tab')
  max_width          - Max column width of table
  width              - Column width for each command that output table
  row_separator      - Output row seperator or not for each command

=head1 AUTHOR

Ye Wenbin <wenbinye@gmail.com>

=head1 SEE ALSO

L<Deobfuscaotr>, L<Bioperl>

=cut

