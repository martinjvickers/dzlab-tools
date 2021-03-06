package DZLab::Tools::GFF;

=head1 NAME

DZLab::Tools::GFF - IO and parsing utilities for GFFv3

=head1 VERSION

This document describes DZLab::Tools::GFF version 0.0.1

=head1 SYNOPSIS

    use DZLab::Tools::GFF qw/gff_read gff_make_iterator/;

    my $iterator = gff_make_iterator( parser => \&gff_read, handle => \*STDIN );

    # or your own parser:
    $iterator = gff_make_iterator( sub { split /\t/ }, file => 'file.gff');

    while (my $gff = iterator->()) {
        # do stuff with $gff
    }

=head1 DESCRIPTION

Using BioPerl for simple parsing of GFF3 files can be overkill, given its dependencies. 
This module offers a functional approach to the problem.

=cut

use strict; use warnings;
use version; our $VERSION = '0.0.1';
use Carp;
require Exporter;

our @ISA       = qw/Exporter/;
our @EXPORT    = qw/gff_read gff_make_iterator gff_validate gff_slurp_by_seq
                    gff_to_string parse_gff_arrayref parse_gff_hashref gff_slurp/;
our @EXPORT_OK = qw//;


=head1 EXPORTED FUNCTIONS

=head2 parse_gff_arrayref $gffline $attribute1 $attribute2 ...

returns arrayref [col1, .. col9, attr1, attr2, ...] 
maps '.' dot columns and non-existenct attributes to undef.
returns 0 on non-parseable lines or comments. *Returns pragmas as strings*.
Check that ref $result eq 'ARRAY'

=cut

sub parse_gff_arrayref{
    my ($line, @wanted) = @_;
    my $gff_ref = parse_gff_hashref($line);
    return [@{$gff_ref}{qw/seqname source feature start end score strand frame attribute/, @wanted}]; 
}

=head2 parse_gff_hashref $line

parse gff into a hashref with all attributes. attributes are returned the same level,
not in a sub hash.  maps '.' dot columns and non-existenct attributes to undef
returns 0 on non-parseable lines or comments. *Returns pragmas as strings*.
Check that ref $result eq 'HASH'

If a locus_tag is given as a second argument, and locus is of the form "SOME.THING",
locus_tag.prefix is set to SOME and locus_tag.suffix is set to THING.  If locus does 
not have a dot, locus_tag.prefix and suffix are undef.  

=cut

sub parse_gff_hashref{
    my ($line, $locus_tag) = @_;
     
    return 0 unless $line;
    $line =~ tr/\n\r//d;

    if ($line =~ m/^\s*#(#)?/o){
        return defined $1 ? $' : 0; # $' = regex postmatch
    }

    my %accum;
    @accum{qw/seqname source feature start end score strand frame attribute/}
    = map { $_ eq q{.} ? undef : $_ } split /\t/, $line;

    (carp "unparseable GFF line" && return 0) unless keys %accum == 9;

    if (defined $accum{seqname}){
        $accum{seqname} = lc $accum{seqname};
    }

    if (defined($accum{attribute}) ){
        for (split /;/, $accum{attribute}){
            my ($key, $val) = split /=/, $_;
            $key =~ s/^\s+//;
            $key =~ s/\s+$//;
            if (defined $val){
                $val =~ s/^\s+//;
                $val =~ s/\s+$//;
                $accum{$key} = $val;
            }
            else {
                $accum{Note} = $key;
            }
        }
    }

    if ($locus_tag){
        if ($accum{$locus_tag} =~ /([^\.]+)\.([^\.]+)/){
            $accum{$locus_tag . '.prefix'} = $1;
            $accum{$locus_tag . '.suffix'} = $2;
        } else {
            $accum{$locus_tag . '.prefix'} = undef;
            $accum{$locus_tag . '.suffix'} = undef;
        }
    }

    return \%accum;
}

=head2 gff_read $string

Parses a single GFF3 line.

Returns undef or empty list on undefined $string (EOF).

Returns [] on blank lines and comments.

Returns [pragma, value, ...] on comments of form '##pragma value value ...'

Returns reference to hash with keys otherwise:

    seqname       => string | undef
    source        => string | undef
    feature       => string | undef
    start         => int
    end           => int
    score         => float  | undef
    strand        => + | -  | undef
    frame         => 0 | 1 | 2 | undef
    attribute     => string | undef
    attributes    => {key => string | [string, ...] | undef, ...}

=cut
sub gff_read {
    my ($gff_line) = @_;
    return unless defined $gff_line;
    chomp $gff_line;

    # get pragmas of the form: '##gff-version 3' and '##sequence-region ctg123 1 1497228'
    return [split /\s+/, $1] if $gff_line =~ m/^
                                               \s*
                                               \#{2}
                                               \s*
                                               (.*)
                                               $/mx;

    # ignore blank lines and lines starting with '#'
    return [] if $gff_line =~ m/^ \s* (?:\#+ .*)? $/mx;

    my ($seqname, $source, $feature, $start, $end,
        $score,   $strand, $frame,   $attribute
    ) = split m/\t/xm, $gff_line || return;

    # locally convert dots to undefs
    local *d2u = sub { return $_[0]; # TODO: remove once it won't break everything
        $_[0] eq q{.} ? undef : $_[0]
    };

    my %attributes = map {
        /=/
        ? (split /=/ )
        : (Note => $_)
    } split /;/, $attribute;

    @attributes{keys %attributes} = map {
        my $v = $_;
        /,/
        ? [map { d2u( $_ ) } split /,/]
        : d2u( $_ )
    } values %attributes;

    return {
        seqname   => d2u( defined $seqname ? lc $seqname : undef ),
        source    => d2u( $source     ),
        feature   => d2u( $feature    ),
        start     => d2u( $start      ),
        end       => d2u( $end        ),
        range     => [$start,$end],
        score     => d2u( $score      ),
        strand    => d2u( $strand     ),
        frame     => d2u( $frame      ),
        attribute => d2u( $attribute  ),
        attributes=> \%attributes,
    };
}

=head2 gff_make_iterator %options

Returns an anonymous function that on, each call, reads one gff line from a $file or $handle, and returns a parsed
structure as delivered by $parser.

Returns undef or empty list on EOF.

=cut
sub gff_make_iterator {
    my %options = @_;

    my $parser = $options{parser} || \&parse_gff_hashref;
    my $file   = $options{file};
    my $handle = $options{handle};

    croak
    "Need parser function reference and file name or handle to build iterator"
    unless $parser and ref $parser eq 'CODE'
    and (
        (defined $file and -e $file)
        or
        (defined $handle and ref $handle eq 'GLOB')
    );

    if (defined $file and -e $file) {
        undef $handle;
        open $handle, '<', $file
        or croak "Can't read $file: $!";
    }

    return sub {
        my $gff_line = scalar <$handle>;
        if (defined($gff_line)){
            return $parser->($gff_line);
        }
        else {
            if (defined $file and -e $file) {
                close $handle;
            }
            return;
        }
    };
}

=head2 gff_slurp

Returns arrayref of gff-records 

=cut

sub gff_slurp{
    my ($opt) = @_;
    
    ($opt->{file} xor $opt->{handle}) 
        or (carp "slurp_gff: need filename xor filehandle" and return {});

    my $it = gff_make_iterator( 
        $opt->{file} ? (file => $opt->{file}) : (handle => $opt->{handle}),
    );

    my @accum;
    while (defined (my $gff = $it->())){
        if (ref $gff eq 'HASH'){
            push @accum, $gff;
        }
    }
    return \@accum;
}

=head2 gff_slurp_by_seq 

Returns hash of sequences to gff-records { sequence => [$gff_hashes] }. 

=cut

sub gff_slurp_by_seq {
    my ($opt) = @_;
    
    ($opt->{file} xor $opt->{handle}) 
        or (carp "slurp_gff: need filename xor filehandle" and return {});

    my %gff_records = ();
    my $it = gff_make_iterator( 
        parser => \&gff_read, 
        $opt->{file} ? (file => $opt->{file}) : (handle => $opt->{handle}),
    );

    print STDERR "Loading groups...\n" if $opt->{debug};
    while (my $gff = $it->()){
        next unless ref $gff eq 'HASH' && keys %$gff;
        my $seq = $gff->{seqname} ;
        if (! exists($gff_records{ $seq } )){
            print STDERR "Reading $seq ...\n" if $opt->{debug};
        }
        push @{ $gff_records{ $seq } }, $gff;
    }

    if ($opt->{sort}){
        foreach my $seq (keys %gff_records) {
            @{ $gff_records{$seq} }
            = sort { $a->{start} <=> $b->{start} } @{ $gff_records{$seq} };
        }
    }
    return \%gff_records;
}

=head2 gff_to_string $gffrec

return a gffrec back in original text format

=cut


sub gff_to_string{
    my $gff = shift || (croak "gff_to_string needs an argument??"); 
    if (ref $gff eq 'HASH'){
        return 
        join "\t",
        map { ! defined $_ ? q{.} : $_ } 
            @{$gff}{'seqname', 'source', 'feature', 'start', 'end',
            'score',   'strand', 'frame',   'attribute'};
    } 
    elsif (ref $gff eq 'ARRAY'){
        return 
        join "\t",
        map { ! defined $_ ? q{.} : $_ } 
        @{$gff}[0..8];
    }
    else {
        croak "non-gff record given to gff_to_string";
    }
}

1;

=head1 INSTALLATION

To install this module type the following:

   perl Build.PL
   Build
   Build test
   Build install

or

   perl Makefile.PL
   make
   make test
   make install

=head1 DIAGNOSTICS

=over

=item C<< "Need parser function reference and file name or handle to build iterator" >>

C<< gff_make_iterator >> takes a hash of options. 'parser', and either 'file' of 'handle' is mandatory.
'parser' must be a CODE ref, file must be defined and exist in the filesystem, and handle must be a GLOB ref.

=back

=head1 TODO

=over

=item

Add a GFF3 validator

=item

Add a GFF3 pretty-printer

=item

Add an output formatting function

=item

Merge other GFF-using subroutines into this module

=back

=head1 AUTHOR

Pedro Silva  C<< <pedros@berkeley.edu> >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2010, Pedro Silva C<< <pedros@berkeley.edu> >>. All rights reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see L<http://www.gnu.org/licenses/>.


