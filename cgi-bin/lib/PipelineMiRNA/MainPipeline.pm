package PipelineMiRNA::MainPipeline;

# ABSTRACT: The actual pipeline

use strict;
use warnings;

use CGI::Carp qw(fatalsToBrowser);
use File::Path 'rmtree';
use File::Basename;
use Cwd qw( abs_path );
use File::Copy;
use PipelineMiRNA;
use PipelineMiRNA::Paths;
use PipelineMiRNA::Utils;
use PipelineMiRNA::Parsers;
use PipelineMiRNA::Programs;
use PipelineMiRNA::Candidate;
use PipelineMiRNA::Results;
use PipelineMiRNA::Components;
use PipelineMiRNA::PosterioriTests;
use Log::Message::Simple qw[msg error debug];

### Data ##
my $dirData = PipelineMiRNA::Paths->get_data_path();

=method write_config

Write the run options to the job configuration file.

=cut

sub write_config {
	my ( $mfe, $randfold, $align, $run_options_file ) = @_;
	my $run_options = PipelineMiRNA->CONFIG();
	$run_options->param( "options.mfe",      $mfe );
	$run_options->param( "options.randfold", $randfold );
	$run_options->param( "options.align",    $align );
	PipelineMiRNA->CONFIG($run_options);
}

=method main_entry

Run the pipeline.

 Usage : PipelineMiRNA::MainPipeline::main_entry( $ifilterCDS, $imfei, $irandfold, $ialign, $idirJob, $iplant );
 Input : Booleans for pipeline options, job directory, plant identifier
 Return: -

=cut

sub main_entry {
	my ( $check, $mfe, $randfold, $align, $job_dir, $plant ) = @_;
	my $debug    = 1;
	my $log_file = File::Spec->catfile( $job_dir, 'log.log' );
	local $Log::Message::Simple::DEBUG_FH = PipelineMiRNA->LOGFH($log_file);

	my $run_options_file = PipelineMiRNA::Paths->get_job_config_path($job_dir);
	PipelineMiRNA->CONFIG_FILE($run_options_file);
	write_config( $mfe, $randfold, $align, $run_options_file );

	debug( 'BEGIN execute_scripts', $debug );
	my $sequences_input = File::Spec->catfile( $job_dir, 'Sequences.fas' );
	if ( $check eq 'checked' ) {
		debug( 'FilteringCDS', $debug );

		#Filtering CDS
		PipelineMiRNA::Components::filter_CDS( $dirData, $job_dir, $plant );
	}
	else {
		my $sequence_uploaded =
		  File::Spec->catfile( $job_dir, 'sequenceUpload.fas' );
		debug( "Moving file $sequence_uploaded to $sequences_input", $debug );
		File::Copy::move( $sequence_uploaded, $sequences_input );
	}

	##Passage du multifasta -> fasta et appel au script Stemloop
	debug( "Opening multifasta $sequences_input", $debug );
	open my $ENTREE_FH, '<', $sequences_input
	  or die "Error when opening sequences -$sequences_input-: $!";
	debug( "Calling parse_multi_fasta() on $sequences_input", $debug );
	my %tab = PipelineMiRNA::Utils::parse_multi_fasta($ENTREE_FH);
	close $ENTREE_FH;

	debug( 'Iterating over names', $debug );

	foreach my $name ( keys %tab ) {
		debug( "Considering $name", $debug );
		my $temp_file = File::Spec->catfile( $job_dir, 'tempFile.txt' );
		open( my $TEMPFILE_FH, '>', $temp_file )
		  or die "Error when opening tempfile -$temp_file-: $!";
		chmod 0777, $temp_file;
		print $TEMPFILE_FH "$name\n$tab{$name}";
		my $name = substr $name, 1;
		my $sequence_dir = File::Spec->catdir( $job_dir, $name );
		mkdir $sequence_dir;

		my $rnalfold_output =
		  File::Spec->catfile( $sequence_dir, 'RNALfold.out' );
		debug( 'Running RNAfold', $debug );
		PipelineMiRNA::Programs::run_rnalfold( $temp_file, $rnalfold_output )
		  or die("Problem when running RNALfold: $!");

		## Appel de RNAstemloop
		my $rnastemloop_out_optimal =
		  File::Spec->catfile( $sequence_dir, 'rnastemloop_optimal.out' );
		my $rnastemloop_out_stemloop =
		  File::Spec->catfile( $sequence_dir, 'rnastemloop_stemloop.out' );
		debug( "Running RNAstemloop on $rnalfold_output", $debug );
		PipelineMiRNA::Programs::run_rnastemloop( $rnalfold_output,
			$rnastemloop_out_optimal, $rnastemloop_out_stemloop )
		  or die("Problem when running RNAstemloop");
		unlink $temp_file;
		process_RNAstemloop_wrapper( $rnastemloop_out_optimal,  'optimal' );
		process_RNAstemloop_wrapper( $rnastemloop_out_stemloop, 'stemloop' );
		my $current_sequence_dir = dirname($rnastemloop_out_stemloop);
		my $rnaeval_out          =
		  File::Spec->catfile( $current_sequence_dir, "rnaeval_stemloop.out" );
		open( my $stem, '<', $rnastemloop_out_stemloop ) or die $!;
		open( my $eval, '<', $rnaeval_out ) or die $!;
		process_RNAstemloop( $current_sequence_dir, 'stemloop', $stem, $eval );
		close($stem);
		close($eval);
	}
	process_tests( $job_dir );
	return;
}

=method process_RNAstemloop_wrapper

Wrap process_RNAstemloop()

=cut

sub process_RNAstemloop_wrapper {
	my ( $rnastemloop_out, $suffix ) = @_;
	my $current_sequence_dir = dirname($rnastemloop_out);
	debug( "Processing RNAstemloop output for $suffix $rnastemloop_out", 1 );
	my $rnaeval_out =
	  File::Spec->catfile( $current_sequence_dir, "rnaeval_$suffix.out" );

	debug( "Running RNAeval in $rnaeval_out", 1 );
	PipelineMiRNA::Programs::run_rnaeval( $rnastemloop_out, $rnaeval_out )
	  or die("Problem when running RNAeval");

	return 0;
}

=method process_RNAstemloop

Process the outputs of RNAstemloop + RNAeval
Writes the sequence on disk (seq.txt) and outRNAFold.txt
(for a given suffix)

=cut

sub process_RNAstemloop {
	my @args                   = @_;
	my ($current_sequence_dir) = shift @args;
	my ($suffix)               = shift @args;
	my ($stem)                 = shift @args;
	my ($eval)                 = shift @args;
	my $j                      = 0;
	my $line2;
	my ( $nameSeq, $dna, $Vienna );
	my @hash = ();

	while ( my $line = <$stem> ) {

		if ( ( $line =~ /^>(.*)/ ) ) {    # nom sequence
			$nameSeq = $1;
		}
		elsif ( ( $line =~ /^[a-zA-Z]/ ) ) { # récupération de la sequence adn
			$dna = substr $line, 0, -1;
			$line2 = substr( <$eval>, 0, -1 );    # the sequence as well

			if ( $dna ne $line2 ) {
				                                  # Should not happen
			}

		}
		elsif ( ( $line =~ /(.*)/ ) ) {
			$Vienna = $1;
			$line2  = <$eval>;    # the structure as well, and the energy
			if ( my ( $structure, $energy ) =
				PipelineMiRNA::Parsers::parse_Vienna_line($line2) )
			{                     # We have a structure
				if ( $Vienna ne $structure ) {
				}

				if ( $nameSeq =~ /.*__(\d*)-(\d*)$/ ) {
					my $cg  = 0;
					my @dna = split( //, $dna );

					my $longueur = scalar @dna;
					for ( my $i = 0 ; $i < $longueur ; $i++ ) {
						if (
							$dna[$i] =~ m{
                              [cg]     # G or C
                            }smxi
						  )
						{
							$cg++;
						}
					}
					my $num = ( $energy / $longueur ) * 100;
					my $mfei = $num / ( ( $cg / $longueur ) * 100 );
					$hash[ $j++ ] = {
						"name"      => $nameSeq,
						"start"     => $1,
						"end"       => $2,
						"mfei"      => $mfei,
						"dna"       => $dna,
						"structure" => $structure,
						"energy"    => $energy
					};

				}
			}
			else {
				debug( "No structure found in $line2", 1 );
			}    # if $line2
		}
		else {

			# Should not happen
		}    #if $line1
	}    #while $line=<IN>
	my %newHash = treat_candidates( \@hash );
	create_directories( \%newHash, $current_sequence_dir );
}

=method treat_candidates

Process the candidates and try merging them.

=cut

sub treat_candidates {

	my (@hash)   = @{ +shift };
	my %newHash  = ();
	my %tempHash = ();
	my $i        = 0;
	foreach my $key ( keys @hash ) {

		my $nb        = scalar @hash;
		my $start     = $hash[$key]{"start"};
		my $end       = $hash[$key]{"end"};
		my $mfei      = $hash[$key]{"mfei"};
		
		my $nameSeq   = $hash[$key]{"name"};
		my $structure = $hash[$key]{"structure"};
		my $dna       = $hash[$key]{"dna"};
		my $energy    = $hash[$key]{"energy"};
		if (
			(
				$end >= $hash[ $key + 1 ]{"end"}
				|| ( $hash[ $key + 1 ]{"start"} < ( $start + $end ) / 2 )
			)
			&& ( $key != $nb - 1 )
		  )
		{
			$tempHash{$nameSeq} = {
				"mfei"      => $mfei,
				"dna"       => $dna,
				"structure" => $structure,
				"energy"    => $energy
			};

		}
		else {
			$tempHash{$nameSeq} = {
				"mfei"      => $mfei,
				"dna"       => $dna,
				"structure" => $structure,
				"energy"    => $energy
			};
			my $max;
			my @keys =
			  sort { $tempHash{$a}{"mfei"} <=> $tempHash{$b}{"mfei"} }
			  keys(%tempHash);
			foreach my $key (@keys) {
				if ( $i == 0 ) {
					$max = $key;
					$newHash{$max}{'max'} = {
						"mfei"      => PipelineMiRNA::Utils::restrict_num_decimal_digits($tempHash{$key}{"mfei"},3),
						"dna"       => $tempHash{$key}{"dna"},
						"structure" => $tempHash{$key}{"structure"},
						"energy"    => $tempHash{$key}{"energy"}
					};

				}
				else {

					$newHash{$max}{$key} = {
						"mfei"      => PipelineMiRNA::Utils::restrict_num_decimal_digits($tempHash{$key}{"mfei"},3),
						"dna"       => $tempHash{$key}{"dna"},
						"structure" => $tempHash{$key}{"structure"},
						"energy"    => $tempHash{$key}{"energy"}
					};

				}
				$i++;
			}
			%tempHash = ();
			$i        = 0;
		}

	}

	return %newHash;
}

=method create_directories

Create the necessary directories.

=cut

sub create_directories {

	my (%newHash) = %{ +shift };
	my $current_sequence_dir = shift;
	foreach my $key ( sort keys %newHash ) {
		my $candidate_dir = File::Spec->catdir( $current_sequence_dir, $key );
		mkdir $candidate_dir;

		#Writing seq.txt
		my $candidate_sequence =
		  File::Spec->catfile( $candidate_dir, 'seq.txt' );
		open( my $OUT, '>', $candidate_sequence )
		  or die "Error when opening $candidate_sequence: $!";
		print $OUT ">$key\n$newHash{$key}{'max'}{'dna'}\n";
		close $OUT;

		for my $name ( keys %{ $newHash{$key} } ) {
			if ( $name eq 'max' ) {
				process_outRNAFold(
					$candidate_dir,
					'optimal',
					$key,
					$newHash{$key}{'max'}{'dna'},
					$newHash{$key}{'max'}{'structure'},
					$newHash{$key}{'max'}{'energy'}
				);
				process_outRNAFold(
					$candidate_dir,
					'stemloop',
					$key,
					$newHash{$key}{'max'}{'dna'},
					$newHash{$key}{'max'}{'structure'},
					$newHash{$key}{'max'}{'energy'}
				);
			}
			else {

				#Writing alternativeCandidates.txt
				my $alternative_candidates =
				  File::Spec->catfile( $candidate_dir,
					'alternativeCandidates.txt' );
				open( my $OUT2, '>>', $alternative_candidates )
				  or die "Error when opening $alternative_candidates: $!";
				print $OUT2
">$name\t$newHash{$key}{$name}{'dna'}\t$newHash{$key}{$name}{'structure'}\t$newHash{$key}{$name}{'mfei'}\n";

			}
		}
		close $OUT;
	}

}

=method process_outRNAFold

Writing (pseudo) rnafold output

=cut

sub process_outRNAFold {
	my ( $candidate_dir, $suffix, $nameSeq, $dna, $structure, $energy ) = @_;

	my $candidate_rnafold_output =
	  File::Spec->catfile( $candidate_dir, "outRNAFold_$suffix.txt" );

	open( my $OUT2, '>', $candidate_rnafold_output )
	  or die "Error when opening $candidate_rnafold_output: $!";
	print $OUT2 ">$nameSeq\n$dna\n$structure ($energy)\n";
	close $OUT2;

}

=method process_tests

Perform the a posteriori tests for a given job

=cut

sub process_tests {
	my ( $job_dir ) = @_;
	debug( "A posteriori tests in $job_dir", 1 );
	##Traitement fichier de sortie outStemloop
	opendir DIR, $job_dir;    #ouverture répertoire job
	my @dirs;
	@dirs = readdir DIR;
	closedir DIR;

	foreach my $dir (@dirs)    # parcours du contenu
	{
		debug( "Considering $dir", 1 );
		my $sequence_dir = File::Spec->catdir( $job_dir, $dir );
		if (   $dir ne '.'
			&& $dir ne '..'
			&& -d $sequence_dir )    #si fichier est un répertoire
		{
			debug( "Entering sequence $sequence_dir", 1 );
			opendir DIR, $sequence_dir;    # ouverture du sous répertoire
			my @files;
			@files = readdir DIR;
			closedir DIR;
			foreach my $subDir (@files) {
				debug( "Considering $subDir", 1 );
				my $candidate_dir =
				  File::Spec->catdir( $sequence_dir, $subDir );
				if (   $subDir ne '.'
					&& $subDir ne '..'
					&& -d $candidate_dir
				  )    # si le fichier est de type repertoire
				{
					debug( "Entering candidate $subDir", 1 );
					process_tests_for_candidate( $candidate_dir, $subDir );
					debug( "Done with candidate $subDir", 1 );
					debug(
"Pseudo Serializing candidate information:\n $job_dir, $dir, $subDir",
						1
					);
					debug( "Like, really", 1 );

					if (
						!eval {
							PipelineMiRNA::Candidate
							  ->serialize_candidate_information(
								$job_dir, $dir, $subDir );
						}
					  )
					{

						# Catching
						debug( "Serialization failed", 1 );
					}
					else {
						debug( "Done with serializing $subDir", 1 );

						# All is well
					}
				}    # foreach my $file (@files)
			}    # if directory
			debug( "Done with initial sequence $dir", 1 );
		}    # foreach my $dir (@dirs)
	}    #process_tests
	return 0;
}

=method process_tests_for_candidate

Perform the a posteriori tests for a given candidate

=cut

sub process_tests_for_candidate {

	my @args = @_;
	my ( $candidate_dir, $file ) = @args;

	####Traitement fichier de sortie outStemloop
	chmod 0777, $candidate_dir;

	my $seq_file = File::Spec->catfile( $candidate_dir, 'seq.txt' );
	my $candidate_rnafold_optimal_out =
	  File::Spec->catfile( $candidate_dir, 'outRNAFold_optimal.txt' );
	my $candidate_rnafold_stemploop_out =
	  File::Spec->catfile( $candidate_dir, 'outRNAFold_stemloop.txt' );

	####conversion en format CT
	my $candidate_ct_optimal_file =
	  File::Spec->catfile( $candidate_dir, 'outB2ct_optimal.ct' );
	debug( "Converting optimal to CT in $candidate_ct_optimal_file", 1 );
	PipelineMiRNA::Programs::convert_to_ct( $candidate_rnafold_optimal_out,
		$candidate_ct_optimal_file )
	  or die('Problem when converting to CT format');

	my $candidate_ct_stemloop_file =
	  File::Spec->catfile( $candidate_dir, 'outB2ct_stemloop.ct' );
	debug( "Converting stemloop to CT in $candidate_ct_stemloop_file", 1 );
	PipelineMiRNA::Programs::convert_to_ct( $candidate_rnafold_stemploop_out,
		$candidate_ct_stemloop_file )
	  or die('Problem when converting to CT format');

	my $varna_image = File::Spec->catfile( $candidate_dir, 'image.png' );
	debug( "Generating image using VARNA in $varna_image", 1 );
	PipelineMiRNA::Programs::run_varna( $candidate_ct_stemloop_file,
		$varna_image )
	  or die('Problem during image generation using VARNA');

	my $cfg = PipelineMiRNA->CONFIG();

	####calcul MFEI (appel script energie.pl)
	if ( $cfg->param('options.mfe') ) {
		debug( "Running test_mfei on $file", 1 );
		PipelineMiRNA::PosterioriTests::test_mfei( $candidate_dir,
			$candidate_ct_optimal_file, $file );
	}
	####calcul p-value randfold
	if ( $cfg->param('options.randfold') ) {
		debug( "Running test_randfold on $seq_file", 1 );
		PipelineMiRNA::PosterioriTests::test_randfold( $candidate_dir,
			$seq_file );
	}
	if ( $cfg->param('options.align') ) {
		debug( "Running test_alignment on $candidate_ct_stemloop_file", 1 );
		PipelineMiRNA::PosterioriTests::test_alignment( $candidate_dir,
			$candidate_ct_stemloop_file );
	}    # if file

	return;
}

1;