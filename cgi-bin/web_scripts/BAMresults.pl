#!/usr/bin/perl -w
use strict;
use warnings;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use FindBin;
use File::Spec;

BEGIN { require File::Spec->catfile( $FindBin::Bin, 'requireLibrary.pl' ); }
use miRkwood;
use miRkwood::Paths;
use miRkwood::Pipeline;
use miRkwood::WebTemplate;
use miRkwood::Results;
use miRkwood::ResultsExporterMaker;


##### Page settings
my $header_menu = miRkwood::WebTemplate::get_header_menu();
my $footer      = miRkwood::WebTemplate::get_footer();
my $web_scripts = miRkwood::WebPaths->get_web_scripts();

my @css = (
	miRkwood::WebTemplate->get_server_css_file(),
	miRkwood::WebTemplate->get_css_file()
);
my @js = (
	File::Spec->catfile( miRkwood::WebPaths->get_js_path(), 'results.js' ),
	File::Spec->catfile( miRkwood::WebPaths->get_js_path(), 'graphics.js' ),
	File::Spec->catfile( miRkwood::WebPaths->get_js_path(), 'miARN.js' ),
	File::Spec->catfile( miRkwood::WebPaths->get_js_path(), 'jquery.min.js' ),
	File::Spec->catfile( miRkwood::WebPaths->get_js_path(),
		'imgpreview.full.jquery.js' )

);

##### Parameters
my $cgi = CGI->new();
my $id_job = $cgi->param('run_id');    # get id job

my $genome_file;
my $mirbase_file;


##### Create page
my $valid = miRkwood::Results->is_valid_jobID($id_job);
my $html = '';
my $HTML_additional = '';
my $page = '';

my $known_mirnas = '';
my $new_mirnas   = '';

my $mirna_bed    = '';
my $other_bed    = '';
my $final_bed    = '';
    
$HTML_additional .= '<p class="header-results" id="job_id"><b>Job ID:</b> ' . $id_job . '</p>';

if ( $valid ){

    my $absolute_job_dir = miRkwood::Results->jobId_to_jobPath($id_job);
    
    my $run_options_file = miRkwood::Paths->get_job_config_path($absolute_job_dir);
    miRkwood->CONFIG_FILE($run_options_file);
    my $cfg = miRkwood->CONFIG();    

    my $species = $cfg->param('job.plant');

    if ( $species ne '' ){
        $genome_file = File::Spec->catfile( miRkwood::Paths->get_data_path(), "genomes/$species.fa");
        $mirbase_file = File::Spec->catfile( miRkwood::Paths->get_data_path(), "miRBase/${species}_miRBase.gff3");
    }
    else{
        $genome_file = "$absolute_job_dir/genome.fa";
    }
    
    my %genome_db = miRkwood::Utils::multifasta_to_hash( $genome_file );   

    opendir (my $dh, $absolute_job_dir) or die "Cannot open $absolute_job_dir : $!";
    while (readdir $dh) {
        if ( /_miRNAs.bed/ ){
            $mirna_bed = File::Spec->catfile($absolute_job_dir, $_);
        }
        elsif ( /_other.bed/ ){
            $other_bed = File::Spec->catfile($absolute_job_dir, $_);    # not used currently
        }
        elsif ( /_filtered.bed/ ){
            $final_bed = File::Spec->catfile($absolute_job_dir, $_);    # not used currently
        }
    }
    closedir $dh;
    
    my $nb_results = 0;
    
    if ( $cfg->param('job.title') ) {
        $HTML_additional .= "<p class='header-results' id='job_title'><b>Job title:</b> " . $cfg->param('job.title') . '</p>';
    }    
    
	unless ( miRkwood::Results->is_job_finished($id_job) ) {
		$HTML_additional .= "<p class='warning'>Still processing...</p>";
	} else {
        $nb_results = miRkwood::Results->number_of_results_bis( $id_job );
        #~ $HTML_additional .= "<p class='header-results' id='precursors_count'><b>" . $nb_results . " miRNA precursor(s) found</b></p>";
        $new_mirnas .= miRkwood::Results->get_basic_pseudoXML_for_jobID($id_job);
    }    
    
    if ( $mirna_bed ne '' ){
        $known_mirnas  = '<div id="table">';
        $known_mirnas .= miRkwood::Results->known_mirnas_for_jobID($id_job, $mirna_bed, $mirbase_file, \%genome_db );
        $known_mirnas .= '</div>';
    }

    if ( $nb_results != 0 ) {
    
        $page = <<"END_TXT";
<body onload="main('all');">
    <div class="theme-border"></div>
    <div class="logo"></div>
    <div class="bloc_droit">
        $header_menu
        <div class="main main-full">
            $HTML_additional
            <div id="select" >
                <div style="width: 510px"  class="forms">
                    <p class='text-results'>Export selected entries \(<a id='select-all' onclick='selectAll()' >select all<\/a>/<a id='deselect-all' onclick='deSelectAll()'  >deselect all</a>\) in one of the following formats:</p>
                    <form id= 'exportForm'>
                        <input type="radio" name="export" id="export-csv" checked='checked' value="csv" />&#160;<label for='export-csv'>tabular format (CSV)</label><br/>
                        <input type="radio" name="export" id="export-fas" value="fas" />&#160;<label for='export-fas'>FASTA format</label><br/>
                        <input type="radio" name="export" id="export-dot" value="dot" />&#160;<label for='export-dot'>dot-bracket format (plain sequence + secondary structure)</label><br/>
                        <input type="radio" name="export" id="export-odf" value="odf" />&#160;<label for='export-odf'>full report in document format (ODF)</label><br/>
                        <input type="radio" name="export" id="export-gff" value="gff" />&#160;<label for='export-gff'>GFF format</label>
                        <input style="margin-left:360px" class="myButton" type="button" name="export-button" id='export-button' value="Export" onclick='exportTo("$id_job", "$web_scripts")'/>
                    </form>
                </div>
                    <p class='helper-results'>Click on a line to see the HTML report of a pre-miRNA prediction. Click on a checkbox to select an entry.<br/>
                    <a id="hrefposition" onclick='sortBy("quality")' >Sort by position <\/a> /  <a id="hrefquality" onclick='sortBy("position")'  >sort by quality</a>
                    </p>
            </div> 
            
            <br />
            
            <h2>New miRNAs :</h2>
            <p class='header-results' id='precursors_count'><b> $nb_results miRNA precursor(s) found</b></p> 
                      
            <div id="table" ></div>
            <div id="singleCell"> </div>
            $new_mirnas   
            
            <br />
                    
            <div id="id_job" >$id_job</div>
            
        </div><!-- main -->
    </div><!-- bloc droit--> 
    $footer  
</body>    
    
END_TXT

    } # end if nb results != 0
    else {  # 0 results
		$page = <<"END_TXT";
<body onload="main('all');">
    <div class="theme-border"></div>
    <a href="/">
        <div class="logo"></div>
    </a>
    <div class="bloc_droit">
        $header_menu
        <div class="main main-full">
            $HTML_additional
        </div><!-- main -->
    </div><!-- bloc droit-->
    $footer
</body>
END_TXT
    }

    $html = miRkwood::WebTemplate::get_HTML_page_for_body($page, \@css, \@js);
}   # end if valid
else{   # job id is not a valid ID
	$page = <<"END_TXT";
<div class="main">
    $HTML_additional
    <p>No results available for the given job identifier $id_job.</p>
</div><!-- main -->
END_TXT

	$html = miRkwood::WebTemplate::get_HTML_page_for_content( $page, \@css, \@js, 1 );
}


print <<"DATA" or die("Error when displaying HTML: $!");
Content-type: text/html

$html
DATA
