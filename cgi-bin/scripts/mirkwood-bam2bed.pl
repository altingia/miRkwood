#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;


################################################################################
# Author : Isabelle GUIGON
# Date : 2014-11-27
# This script converts a BAM file into a BED file for use by miRkwood.
#
# Dependancies : samtools
# Make sure to have it installed in your PATH.
# For Ubuntu/Debian distributions `sudo apt-get install samtools` is enough.
################################################################################


########## Variables
my $input_file = '';
my $bed_file   = '';
my $time = time();
my $sorted_bam_file = "/tmp/mirkwood_bam2bed_${time}_sorted";
my $sorted_sam_file = "/tmp/mirkwood_bam2bed_${time}_sorted.sam";

my $counts;
my $help;
my $help_message = <<'EOF';
mirkwood-bam2bed.pl
----------
Script to convert a BAM into a BED file for use by miRkwood.

Usage : ./mirkwood-bam2bed.pl -bam <input BAM file> -bed <output BED file> 

Dependancies : samtools
Make sure to have it installed in your PATH. For Ubuntu/Debian distributions `sudo apt-get install samtools` is enough.

EOF


########## Get options
GetOptions ('in=s'  => \$input_file,
            'bed=s' => \$bed_file,
	        'help'  => \$help);


########## Validate options
if ( $help ){
    print $help_message;
    exit;
}

if ( ! -r $input_file ){
    print "Missing input file!\n";
    print $help_message;
    exit;
}

if ( $bed_file eq '' ){
    print "Missing output file!\n";
    print $help_message;
    exit;
}



########## Create sorted SAM file
if ( $input_file =~ /([^\/\\]+)[.]sam/ ){
    system("sort -k 3,3 -k 4,4n $input_file | grep -v \"^@\" > $sorted_sam_file");
}
elsif ( $input_file =~ /([^\/\\]+)[.]bam/ ){
    ##### Sort BAM file
    system("samtools sort $input_file $sorted_bam_file");

    ##### Convert sorted BAM into SAM and filter out unmapped reads
    system("samtools view -F 4 $sorted_bam_file.bam > $sorted_sam_file");
    unlink $sorted_bam_file . '.bam';
}
else{
    die "Non correct input file. We accept BAM and SAM as input formats.\n$help_message";
}



########## Read the SAM file to store counts into a hash
open(my $SAM, '<', $sorted_sam_file) or die "ERROR while reading SAM file. Program will end prematurely.\n";

while ( <$SAM> ){

    chomp;

    my @line = split ( /\t/smx );

    if ( $line[1] ne '0x4' && $line[1] ne '4' ){

        my $id = $line[0];
        my $chromosome = $line[2];
        my $start = $line[3] - 1;
        my $sequence = $line[9];
        my $strand = '+';
        if ( $line[1] eq '16' or $line[1] eq '0x10' ){
            $strand = '-';
        }

        if ( ! exists( $counts->{$chromosome}{$start}{$sequence}{$strand} ) ){
            $counts->{$chromosome}{$start}{$sequence}{$strand}{'count'} = 0;
        }
        $counts->{$chromosome}{$start}{$sequence}{$strand}{'count'}++;

        $counts->{$chromosome}{$start}{$sequence}{$strand}{'id'} = $id;

    }

}

close $SAM;
unlink $sorted_sam_file;


########## Browse hash tables and print data in BED file
open(my $BED, '>', $bed_file) or die "ERROR while creating $bed_file. Program will end prematurely.\n";
foreach my $chromosome ( sort (keys%$counts) ){
    foreach my $start ( sort {$a <=> $b} keys%{ $counts->{$chromosome} } ){
        foreach my $sequence ( sort (keys%{ $counts->{$chromosome}{$start} } ) ){
            foreach my $strand ( sort (keys%{ $counts->{$chromosome}{$start}{$sequence} } ) ){ 
                my $end = $start + length($sequence);
                print $BED "$chromosome\t";
                print $BED "$start\t";
                print $BED "$end\t";
                print $BED "$counts->{$chromosome}{$start}{$sequence}{$strand}{'id'}\t";
                print $BED "$counts->{$chromosome}{$start}{$sequence}{$strand}{'count'}\t";
                print $BED "$strand\n";
            }
        }
    }
}
close $BED;
