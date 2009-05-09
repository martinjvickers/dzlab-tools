#!/usr/bin/perl

use warnings;
use strict;
use Data::Dumper;
use Carp;
use Getopt::Long;
use Pod::Usage;

my @range;
my $seqid;
my $output;
my $list;

# Grabs and parses command line options
my $result = GetOptions (
    'list|l'       => \$list,
    'seqid|s=s'    => \$seqid,
    'range|r=i{2}' => \@range,
    'output|o=s'   => \$output,
    'verbose|v'    => sub { use diagnostics; },
    'quiet|q'      => sub { no warnings; },
    'help|h'       => sub { pod2usage ( -verbose => 1 ); },
    'manual|m'     => sub { pod2usage ( -verbose => 2 ); }
);

# Check required command line parameters
pod2usage ( -verbose => 1 )
unless @ARGV;

if ($output) {
    open my $USER_OUT, '>', $output or croak "Can't open $output for writing: $!";
    select $USER_OUT;
}

my $reference = $ARGV[0];
my %reference = %{ index_fasta ($reference) };

if ($list) {
    print "Available sequence IDs:\n";
    print "$_\t", length $reference{$_}, "\n" for sort keys %reference;
}

if ($seqid) {

    @range = (0, 0)
    unless @range;

    my $sequence
    = _sequence (\%reference, $seqid, @range);

    print ">lcl|$seqid $range[0] $range[1]\n";
    print $sequence, "\n";

}


sub _sequence {
    my ($reference, $seqid, $start, $end) = @_;

    $seqid =~ tr/A-Z/a-z/;

    croak "Sequence ID does not exist"
    unless exists $reference{$seqid};

    if ($start and $end) {

        croak "Coordinates out of bounds"
        if $start < 0 or $end > length $reference->{$seqid};

        return
        substr ($reference{$seqid}, $start - 1, $end - $start - 1);
    }
    else {
        return $reference{$seqid};
    }
}


sub index_fasta {
    my $reference_file = shift;

    my %reference = ();

    return \%reference unless $reference_file;

    # reads in the reference genome file into @fastaseq
    open my $REF, '<', "$reference_file" or croak "Can't open $reference for reading: $!";
    my @fastaseq = <$REF>;
    close $REF;

    # find and store indices for each chromosome change and corresponding descriptions
    my ( @idx, @dsc ) = ();
    for my $i ( 0 .. @fastaseq - 1 ) {
        if ( $fastaseq[$i] =~ m/^>/ ) {
            $fastaseq[$i] =~ s/>//g;
            $fastaseq[$i] = ( split /\s/, "$fastaseq[$i]" )[0];
            $fastaseq[$i] =~ tr/A-Z/a-z/;
            push @idx, $i;
            push @dsc, $fastaseq[$i];
        }
    }

    for my $j ( 0 .. @idx - 1 ) {
        my $line;
        if ( $j == scalar @idx - 1 ) {
            $line = join( q{}, @fastaseq[ $idx[$j] + 1 .. @fastaseq - 1]);
        }
        else {
            $line = join( q{}, @fastaseq[ $idx[$j] + 1 .. $idx[$j + 1] - 1]);
        }
        $line =~ s/[\n\r]//g;
        $reference{$dsc[$j]} = $line;
    }
    return \%reference;
}


__END__

=head1 NAME

 parse_fasta.pl - Retrieve sequence information from fasta files

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 OPTIONS

 parse_fasta.pl [OPTION]... [FILE]...

 -l, --list        print list of sequence ids and lengths
 -s, --seqid       sequence id from which to print sub sequence
 -r, --range       start and end coordinates to print
 -o, --output      filename to write results to (defaults to STDOUT)
 -v, --verbose     output perl's diagnostic and warning messages
 -q, --quiet       supress perl's diagnostic and warning messages
 -h, --help        print this information
 -m, --manual      print the plain old documentation page

=head1 REVISION

 Version 0.0.1

 $Rev: $:
 $Author: $:
 $Date: $:
 $HeadURL: $:
 $Id: $:

=head1 AUTHOR

 Pedro Silva <psilva@nature.berkeley.edu/>
 Zilberman Lab <http://dzlab.pmb.berkeley.edu/>
 Plant and Microbial Biology Department
 College of Natural Resources
 University of California, Berkeley

=head1 COPYRIGHT

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program. If not, see <http://www.gnu.org/licenses/>.

=cut
