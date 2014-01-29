#!/usr/bin/perl -w

use warnings;
use strict;

use Pod::Usage;
use Getopt::Long;
use File::Copy;
use File::Spec;

use PipelineMiRNA::MainPipeline;

my $man = 0;
my $help = 0;

# Pipeline options
my $randfold = 0;
my $mfei = 0;
my $align = 0;
my $species_mask = '';

my $mask = 0;
my $output_folder = 'results_directory';

## Parse options
GetOptions(
randfold   => \$randfold,
mfei       => \$mfei,
align      => \$align,
'species-mask=s' => \$species_mask,
'output=s' => \$output_folder,
'help|?'   => \$help,
man        => \$man
)
 ||  pod2usage(-verbose => 0);
pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);

pod2usage("$0: No FASTA files given.")  if (@ARGV == 0);

if($species_mask){
    $mask = 1;
}
my $fasta_file = $ARGV[0];
(-e $fasta_file) or die("$fasta_file is not a file");

mkdir $output_folder;

my $seq_name = 'Sequences.fas';
my $seq_path = File::Spec->catfile($output_folder, $seq_name);
File::Copy::copy( $fasta_file, $seq_path);

PipelineMiRNA::MainPipeline::main_entry( $mask, $mfei, $randfold, $align, $output_folder, $species_mask );


__END__

=head1 NAME

MiREST - A micro-RNA analysis pipeline

=head1 SYNOPSIS

sample [options] [FASTA files]

=head1 OPTIONS

=over 8

=item B<-species-mask>

Mask coding regions against the given organism

=item B<-randfold>

Compute thermodynamic stability

=item B<-mfei>

Compute MFE/MFEI/AMFE (minimal folding energy)

=item B<-align>

Align against mature microRNAs miRBase

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<MiREST> will read the given input file(s) and do something
useful with the contents thereof.

=cut