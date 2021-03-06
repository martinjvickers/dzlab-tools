#!/usr/bin/env perl
use strict;
use warnings;
use List::MoreUtils qw/all/;
use List::Util qw/max min/;
use Data::Dumper;
use feature 'say';
use Carp;
use autodie;
use Pod::Usage;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin/lib";
#use GFF::Parser::Attributes;
use GFF::Parser::Locus;

my $output = q{-};
my $help;
my $result = GetOptions (
    "output|o=s"    => \$output,
    "help"          => \$help,
);
pod2usage(-verbose => 1) if (!$result || $help || ! @ARGV);

# return elements in @x not in @y
sub complement{
    my ($xx,$yy) = @_;
    my @x = @$xx;
    my @y = @$yy;
    my %seen;
    my @accum;
    for (@y){ $seen{$_} = 1;}
    for (@x){ if (!exists $seen{$_}) {push @accum, $_}}
    return @accum;
}

unless ($output eq '-'){
    close STDOUT;
    open STDOUT, '>', $output or die "can't open $output for writing";
}

my @mains = qw/seqname source feature start end score   strand frame   attribute/;
my %seen;

# read through all files once, recording all attribute names
foreach my $file (@ARGV) {
    my $parser = GFF::Parser::Locus->new(file => $file,locus => 'ID');
    while (my $gff = $parser->next()){
        my @record_cols = keys %$gff;
        my @attributes = complement \@record_cols, \@mains;
        @seen{@attributes} = map { 1 } @attributes;
    }
}

my @columns = (qw/seqname source feature start end score strand frame/, sort keys %seen);

# read through them again, this time printing.

say join "\t",@columns;
foreach my $file (@ARGV) {
    my $parser = GFF::Parser::Locus->new(file => $file,locus => 'ID');
    while (my $gff = $parser->next()){
        say join "\t", map {$_ // '.'} @{$gff}{@columns};
    }
}

=head1 NAME

gff2tsv.pl - convert a GFF file to TSV, tab seperated file

=head1 SYNOPSIS

 gff2tsv.pl -o output-tsv.txt input1.gff input2.gff ...

=head1 DESCRIPTION

The first 8 columns are always seqname, source, feature, start, end, score, strand, frame.  The
ninth and further columns are the attributes split up into individual column.  First line of output
is the column names.

=head1 OPTIONS

 --input      name of input exon gff file (required)
  -i

 --help       print this information

=cut

