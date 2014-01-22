#!/usr/bin/perl -w
use strict;
use warnings;

use FindBin;

BEGIN { require File::Spec->catfile( $FindBin::Bin, 'requireLibrary.pl' ); }
use PipelineMiRNA::WebTemplate;

my $bioinfo_menu = PipelineMiRNA::WebTemplate::get_bioinfo_menu();
my $header_menu  = PipelineMiRNA::WebTemplate::get_header_menu();
my $footer       = PipelineMiRNA::WebTemplate::get_footer();

my $bioinfo_css = PipelineMiRNA::WebTemplate->get_server_css_file();
my $project_css = PipelineMiRNA::WebTemplate->get_css_file();
my $js  = PipelineMiRNA::WebTemplate->get_js_file();

print <<"DATA" or die("Error when displaying HTML: $!");
Content-type: text/html

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1" />
<meta name="keywords" content="RNA, ARN, mfold, fold, structure, prediction, secondary structure" />
<link title="test" type="text/css" rel="stylesheet" href="$project_css" />
<link title="test" type="text/css" rel="stylesheet" href="$bioinfo_css" />
       <script src="$js" type="text/javascript" LANGUAGE="JavaScript"></script>
        <title>miREST</title>


</head>
<body>
<div class="theme-border"></div>
<div class="logo"></div>

$bioinfo_menu

<div class="bloc_droit">

$header_menu

<div class="main">

        <form  name="form" onsubmit="return verifySequence();" onsubmit="wainting()" method="post" action="./results.pl" enctype="multipart/form-data">
            <fieldset id="fieldset">    
				 <div class="forms">
				<tr>
					<td class="label"> 
						Enter a <b> name </b>for your job  <i>(optional)</i></i>: 
						<input type="text" name="job" size="20">
					</td>
				  </tr>
				</div>
				<div class="forms">
					
				    <p class="label"><b>Paste</b> your RNA sequences in FASTA
					  format &nbsp;&nbsp;[<a href="./help.pl">?</a>]
					</p>
					<textarea id='seqArea' name="seqArea"  rows="10" cols="150" ></textarea>
					
					<p>
					  or
					</p>
					<p class="label">
					  <b>upload</b> a file 
					  <input type="file" name="seqFile" id="file" />
					</p>
					
					<input id="seq_button" type="button" value="Example" onclick="generateExample();" />
				</div>
				  <div class="forms">
					<p class="label"><b>Mask coding regions [<a href="./help.pl">?</a>] <i><small>(may be slow) </small></i></b> :
					<input  id ="CDS" type="checkbox" name="check" value="checked" onclick="showHideBlock()"> </p>               
					<div id="menuDb"> 
					<p class="choixDiv" for="db">Choose organism database :</p>
						<select class="db" name="db">
							<option class="db" selected>ATpepTAIR10</option>
							<option class="db">plante</option>
						</select>
					</div>
               </div>
               <div class="forms">
				<p><b>Select additional features</b>:</p>
				<P>
               <P > <input class="checkbox" type="checkbox" checked="checked" name="randfold" value="randfoldChecked">Compute thermodynamic stability [<a href="./help.pl">?</a>]</input></P>
                  
               <P > <input class="checkbox" type="checkbox" checked="checked" name="mfei" value="mfeiChecked">Compute MFE/MFEI/AMFE (minimal folding energy)[<a href="./help.pl">?</a>]</input></P>
             
               <P > <input  class="checkbox" type="checkbox" checked="checked" name="align" value="alignChecked">Align against mature microRNAs miRBase [<a href="./help.pl">?</a>]</input></P>
                
                </div>
               </P>
                
                </label>
				<div class="forms">
				<tr>
					<td class="label"> 
						Enter your <b>E-mail</b> address <i>(optional)</i>: 
						<input type="text" name="mail" size="20">
					</td>
				  </tr>
				</div>
	
 		 <div class="center">

              <input type="submit" name="upload" id="upload" value="Run MiRNA">
                
       </div>      
            
            </fieldset>
        
        </form>
        
        
        
        
        
        
</div><!-- main -->



</div><!-- bloc droit-->
$footer
</body>
</html>

DATA
###End###
