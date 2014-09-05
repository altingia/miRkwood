package miRkwood::Results;

# ABSTRACT: Code directly tied to the results data structure

use strict;
use warnings;

use feature 'switch';
use Time::gmtime;

use miRkwood::Candidate;
use miRkwood::CandidateHandler;;
use miRkwood::Utils;

=method make_job_id

Return a jobId (based on the current time)

=cut

sub make_job_id {
	my ( $self, @args ) = @_;
	my $now = gmctime();
	$now =~ s/[: ]//g;
	$now = substr( $now, 3 );
	return $now;
}

=method jobId_to_jobPath

Get the job path from a job identifier

=cut

sub jobId_to_jobPath {
	my ( $self, @args ) = @_;
	my $id_job      = shift @args;
	my $dirJob_name = 'job' . $id_job;
	my $results_dir = miRkwood::Paths->get_results_filesystem_path();
	my $jobPath     = File::Spec->catdir( $results_dir, $dirJob_name );
	return $jobPath;
}

=method is_job_finished

Return whether a job is finished or not

=cut

sub is_job_finished {
    my ( $self, @args ) = @_;
    my $id_job      = shift @args;
    my $job_dir     = $self->jobId_to_jobPath($id_job);
    my $is_finished_file = File::Spec->catfile( $job_dir, 'finished' );
    return (-e $is_finished_file);
}


=method get_candidates_dir


=cut

sub get_candidates_dir {
	my ( $self, @args ) = @_;
	my $id_job         = shift @args;
	my $results_dir    = $self->jobId_to_jobPath($id_job);
	my $candidates_dir = File::Spec->catdir( $results_dir, 'candidates' );
	return $candidates_dir;
}

=method is_valid_jobID

Test whether a jobID is valid - ie if there are results for it.

=cut

sub is_valid_jobID {
	my ( $self, @args ) = @_;
	my $id_job    = shift @args;
	my $full_path = $self->jobId_to_jobPath($id_job);
	return ( -e $full_path );
}

=method get_structure_for_jobID

Get the results structure of a given job identifier

Usage:
my %results = miRkwood::Results->get_structure_for_jobID($jobId);

=cut

sub get_structure_for_jobID {
	my ( $self, @args ) = @_;
	my $jobId   = shift @args;
	my $job_dir = $self->jobId_to_jobPath($jobId);
	miRkwood->CONFIG_FILE(
		miRkwood::Paths->get_job_config_path($job_dir) );
	my $candidates_dir = $self->get_candidates_dir($jobId);
	return $self->deserialize_results($candidates_dir);
}

=method has_candidates

Parse and serialize the results structure of $job_dir

Usage:
miRkwood::Results->has_candidates( \%myResults );

=cut

sub has_candidates {
	my ( $self, @args ) = @_;
	my $results = shift @args;
	my %results = %{$results};
	return ( keys %results > 0 );
}

=method deserialize_results

Retrieve the results in the given directory

Usage:
my %results = miRkwood::Results->deserialize_results( $candidates_dir );

=cut

sub deserialize_results {
	my ( $self, @args ) = @_;
	my $candidates_dir = shift @args;
	my %myResults      = ();
	opendir DIR, $candidates_dir;    #ouverture répertoire job
	my @files;
	@files = readdir DIR;
	closedir DIR;
	foreach my $file (@files)        # parcours du contenu
	{
		my $full_file = File::Spec->catfile( $candidates_dir, $file );
		if (   $file ne "."
			&& $file ne ".." )
		{
			my $candidate;
			if (
				!eval {
					$candidate =
					  miRkwood::Candidate->new_from_serialized(
						$full_file);
				}
			  )
			{

				# Catching, do nothing
			}
			else {
				my $identifier = $candidate->get_identifier();
				$myResults{$identifier} = $candidate;
			}
		}
	}
	return %myResults;
}

=method export

Convert the results

=cut

sub export {
	my ( $self, @args ) = @_;
	my $export_type             = shift @args;
	my $results_ref             = shift @args;
	my $sequences_to_export_ref = shift @args;

	my @sequences_to_export;
	if ( !eval { @sequences_to_export = @{$sequences_to_export_ref} } ) {
		@sequences_to_export = ();
	}
	my $no_seq_selected = !( scalar @sequences_to_export );

	my %results = %{$results_ref};

	my $output = "";

	# Writing the header
	my $header;
	my $gff_header = "##gff-version 3
# miRNA precursor sequences found by miRkwood have type 'miRNA_primary_transcript'.
# Note, these sequences do not represent the full primary transcript,
# rather a predicted stem-loop portion that includes the precursor.
";
	given ($export_type) {
		when (/fas/) { $header = q{}; }
		when (/dot/) { $header = q{}; }
		when (/gff/) { $header = $gff_header . "\n"; }
	}
	$output .= $header;

	my @keys = sort keys %results;
	foreach my $key (@keys) {
		if ( ( $key ~~@sequences_to_export ) || ($no_seq_selected) ) {
			my $candidate = $results{$key};
			given ($export_type) {
				when (/fas/) {
					$output .=
					  $candidate->candidateAsFasta();
				}
				when (/dot/) {
					$output .=
					  $candidate->candidateAsVienna();
				}
				when (/gff/) {
					$output .=
					  $candidate->candidate_as_gff();
				}
			}
		}
	}
	return $output;
}

=method resultstruct2csv

Convert the results structure to CSV

=cut

sub resultstruct2csv {
	my ( $self, @args ) = @_;
	my $results_ref             = shift @args;
	my $sequences_to_export_ref = shift @args;

	my @sequences_to_export;
	if ( !eval { @sequences_to_export = @{$sequences_to_export_ref} } ) {
		@sequences_to_export = ();
	}
	my $no_seq_selected = !( scalar @sequences_to_export );
	my %results         = %{$results_ref};
	my @optional_fields = miRkwood::Candidate->get_optional_candidate_fields();
	my @csv_headers     = (
		'name', 'start_position', 'end_position', 'quality', '%GC',
		@optional_fields, 'Vienna', 'DNASequence'
	);
	my $result = join( ',', @csv_headers ) . "\n";

	my @keys = sort {
		( $results{$a}->{'name'} cmp $results{$b}->{'name'} )
		  || (
			$results{$a}->{'start_position'} <=> $results{$b}->{'start_position'} )
	} keys %results;
	foreach my $key (@keys) {
		if ( ( $key ~~@sequences_to_export ) || ($no_seq_selected) ) {
			my $value = $results{$key};
			for my $header (@csv_headers) {
				my $contents = ${$value}{$header};
				if ( !defined $contents ) {
					$contents = q{};
				}
				$result .= "$contents,";
			}
			$result .= "\n";
		}
	}
	return $result;
}

=method resultstruct2pseudoXML

Convert the results structure to to pseudo XML format

=cut

sub resultstruct2pseudoXML {
	my ( $self, @args ) = @_;
	my $results = shift @args;
	my %results = %{$results};

	my $result = "<results id='all'>\n";
	my @keys = sort {
		( $results{$b}->{'name'} cmp $results{$a}->{'name'} )
		  || (
			$results{$a}->{'start_position'} <=> $results{$b}->{'start_position'} )
	} keys %results;

	foreach my $key (@keys) {
		my $candidate = $results{$key};
        $result .= $candidate->candidate_as_pseudoXML() . "\n";
	}
	$result .= "</results>\n";
	$result .= "<results id='all2'>\n";
	@keys = sort keys %results;
	@keys = sort {
		( $results{$b}->{'quality'} cmp $results{$a}->{'quality'} )
		  || (
			$results{$a}->{'start_position'} <=> $results{$b}->{'start_position'} )
	} keys %results;
	foreach my $key (@keys) {
		my $candidate = $results{$key};
		$result .= $candidate->candidate_as_pseudoXML() . "\n";
	}
	$result .= "</results>";
	return $result;
}

=method number_of_results

return total number of candidates 

=cut

sub number_of_results {
	my ( $self, @args ) = @_;
	my $results = shift @args;
	my %results = %{$results};
	my $size    = scalar keys %results;
	return $size;
}

=method resultstruct2table

Convert the results structure to HTML table

=cut

sub resultstruct2table {
	my ( $self, @args ) = @_;
	my $results = shift @args;
	my %results = %{$results};

	my @optional_fields = miRkwood::Candidate->get_optional_candidate_fields();
	my @headers         =
	  ( 'position', 'length', 'strand', 'quality', @optional_fields );

	my $HTML_results = '';
	$HTML_results .= "<table>\n<tbody>";
	$HTML_results .= "<tr>";
	for my $header ( ('name'), @headers ) {

		$HTML_results .= "<th>$header</th>\n";
	}
	$HTML_results .= "</tr>\n";
	while ( my ( $key, $value ) = each %results ) {
		$HTML_results .= '<tr>';
		my $anchor   = "${$value}{'name'}-${$value}{'position'}";
		my $contents = "<a href='#$anchor'>${$value}{'name'}</a>";
		$HTML_results .= "<td>$contents</td>\n";
		for my $header (@headers) {
			my $td_content = "";
			my $contents   = ${$value}{$header};
			if ( !defined $contents ) {
				$contents = q{};
			}
			$HTML_results .= "<td>$contents</td>\n";
		}
		$HTML_results .= "\n</tr>\n";
	}
	$HTML_results .= "</tbody>\n</table>\n";

	return $HTML_results;
}

1;