#!/usr/bin/perl -w -I/opt/eprints3/perl_lib
use EPrints;
use strict;
use warnings;
use HTTP::Request;
use LWP::UserAgent;
use open qw/:std :utf8/;
use JSON;
use utf8;
use Encode;
use Data::Dumper;


#use Data::Dumper;

#Repository Name, e.g.: Spectrum, used for formatting autocomplete text
my $repositoryName= "";

#Specify your Sherpa Romeo API key
my $api_key = "";

#Specify the file, out_file is the final file, construct_file is the in-progress file
#the location should be set to where you have the autocomplete file, normally /opt/eprints3/archives/REPOID/cfg/autocomplete/
#out_file should be something like /opt/eprints3/archives/REPOID/cfg/autocomplete/romeo_journals.autocomplete
my $out_file = "";
#construct_file should be something like /opt/eprints3/archives/REPOID/cfg/autocomplete/romeo_journals.construct
my $construct_file = "";

#Open same file for writing, reusing STDOUT
open (OUTFILE, ">$construct_file") or die "Can't open $construct_file: $!\n";

my $return_str="";
my $done = 0;

my $step=100;
my $offset=0;
my $max=99999;

if ($api_key eq ""){
	print STDOUT "You must set a Sherpa Romeo api_key.  Exiting.\n";
	$done = 1;
}

if ($out_file eq ""){
	print STDOUT "You must set out_file.  Exiting.\n";
	$done = 1;
}

if ($construct_file eq ""){
	print STDOUT "You must set construct_file.  Exiting.\n";
	$done = 1;
}

if ($repositoryName eq ""){
	print STDOUT "You must set repositoryName.  Exiting.\n";
	$done = 1;
}

while (!$done){
	$done = fetchBatch ($step, $offset);
	$offset=$offset+$step;
	print STDOUT $offset."\n";
    last if ($offset > $max);
}

sub contains_one_of
{
				my ($strings, $matches) = @_;

				foreach my $string (@{$strings})
				{
								return 1 if equals_one_of($string, $matches);
				}
				return 0;
}

sub equals_one_of
{
				my ($string, $matches) = @_;

				foreach my $match (@{$matches})
				{
								return 1 if $string eq $match;
				}
				return 0;
}


sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}
	

sub fetchBatch{

    my ($limit, $offset) = @_;
	
	my $done = 0;
	
	my $query = "https://v2.sherpa.ac.uk/cgi/retrieve?item-type=publication&api-key=".$api_key."&format=Json&limit=".$limit."&offset=".$offset;
	#print STDOUT $query."\n";
	my $request = HTTP::Request->new(GET => "$query");
	my $ua = LWP::UserAgent->new();
	$ua->default_header('Accept-Encoding' => 'utf8');
	my $respond = $ua->request($request);
	my $content = $respond->content();
	$content = decode_utf8( $content );
	my $json = JSON->new;
	my $json_text = $json->decode( $content );
	my $length = @{ $json_text->{'items'} };
	if ($length == 0){$done = 1;return $done;}
	processBatch($json_text);
	
	return $done;

}



sub processBatch{
	
	my $json_text = shift;
	
	my $return_str = "";

	foreach my $items ( @{ $json_text->{'items'} } ) {
		my $title=$items->{'title'}->[0]->{'title'};
		my $issn=$items->{'issns'}->[0]->{'issn'};
		my $issn2=$items->{'issns'}->[1]->{'issn'};
		my $publisher_id=$items->{'publishers'}->[0]->{'publisher'}->{'id'};
		my $publisher_url=$items->{'publishers'}->[0]->{'publisher'}->{'uri'};
		my $publication_url=$items->{'url'};
		my $publication_id=$items->{'id'};
		if (defined($title) && defined($publisher_id)){
			$return_str .= $title."	";	
			my $publisher_name=$items->{'publishers'}->[0]->{'publisher'}->{'name'}->[0]->{'name'};
			
			my $permitted_oa_versions="";
			
			my $summary_for_IR_conditions = "";
			my $summary_for_IR_prerequisites = "";
			my $summary_for_IR_prerequisite_funders = "";
			my $summary_for_IR_prerequisite_subjects = "";
			
			my $versions = "version";
			
			my @PolicySummary;
			
			my $i=0;
			my @unique_versions = ();
			my $interesting_locations = [qw/ institutional_repository any_website non_commercial_repository non_commercial_institutional_repository any_repository  /];

			foreach my $temp (@{$items->{'publisher_policy'}->[0]->{'permitted_oa'}}){
					if (contains_one_of($temp->{'location'}->{'location'}, $interesting_locations)) {

					#for each policy that has permitted_oa and appropriate location
					
					   #check to filter our any additional OA fees
					   if ($temp->{'additional_oa_fee'} eq "no"){
					  
					  		#get corresponding versions string
							$permitted_oa_versions="";
							
							foreach my $temp_versions (@{$temp->{'article_version'}}){
								push (@unique_versions, $temp_versions);
								$permitted_oa_versions.=$temp_versions.", ";
							}
							$permitted_oa_versions =~ s/,\s*$//;
							
							#get prerequisites' string
							$summary_for_IR_prerequisites = "";
							if (defined ($temp->{'prerequisites'}->{'prerequisites'})) {
								foreach (@{$temp->{'prerequisites'}->{'prerequisites'}}) {
								  $summary_for_IR_prerequisites .= "<li>".$_."</li>";
								}
							}
							
							#get prerequisites' funders string
							$summary_for_IR_prerequisite_funders = "";
							if (defined ($temp->{'prerequisites'}->{'prerequisite_funders'})) {
								foreach (@{$temp->{'prerequisites'}->{'prerequisite_funders'}}) {
								  $summary_for_IR_prerequisite_funders .= "<li>".$_->{'funder_metadata'}->{name}->[0]->{name}."</li>";
								}
							}
							
							#get prerequisites' subject string
							$summary_for_IR_prerequisite_subjects = "";
							if (defined ($temp->{'prerequisites'}->{'prerequisite_subjects'})) {
								foreach (@{$temp->{'prerequisites'}->{'prerequisite_subjects'}}) {
								  $summary_for_IR_prerequisite_subjects .= "<li>".$_."</li>";
								  print STDOUT $summary_for_IR_prerequisite_subjects;
								}
							}
							
							#get conditions' string
							$summary_for_IR_conditions = "";
							if (defined ($temp->{'conditions'})) {
								foreach (@{$temp->{'conditions'}}) {
								  $summary_for_IR_conditions .= "<li>".$_."</li>";
								}
							}
							
							#get embargo period
							my $embargo_period = '';
							if (defined ($temp->{'embargo'})) {
								$embargo_period =$temp->{'embargo'}->{'amount'}." ".$temp->{'embargo'}->{'units'};
							}
							
							#get license requirement
							my $license = '';
							if (defined ($temp->{'license'})) {
								$license =$temp->{'license'}->[0]->{'license'};
							}
							
							$PolicySummary[$i][0]=$permitted_oa_versions;
							#print STDOUT $permitted_oa_versions;
							$PolicySummary[$i][1]=$summary_for_IR_conditions;
							#print STDOUT $summary_for_IR_conditions;
							$PolicySummary[$i][2]=$embargo_period;
							$PolicySummary[$i][3]=$summary_for_IR_prerequisites;
							$PolicySummary[$i][4]=$summary_for_IR_prerequisite_funders;
							$PolicySummary[$i][5]=$summary_for_IR_prerequisite_subjects;
							$PolicySummary[$i][6]="";
							$PolicySummary[$i][7]=$license;
					  }
					  else {
					  	#OA could be possible, but with OA fee
					  	$PolicySummary[$i][6]="with_oa_fee";
					  }
					  $i++;
					}
			}
			#print STDOUT Dumper uniq(@unique_versions);
			#print STDOUT Dumper \@PolicySummary;
			
			$permitted_oa_versions="";
			my $j=0;
			foreach my $temp_versions (uniq(@unique_versions)){
							$permitted_oa_versions.=$temp_versions.", ";
							$j++;
						}
			if ($j > 1){
				$versions = "versions";
			}
			$permitted_oa_versions =~ s/,\s*$//;
			
			my $summary_for_IR = "";
			

			
			if ($permitted_oa_versions ne ""){
				
				$return_str .="<li style='border-right: solid 50px #dfeccf'>";
				$return_str .=$title." published by ".$publisher_name."<br />";
			
				$return_str .= "<small>".$permitted_oa_versions." ".$versions." can be archived in ".$repositoryName.".</small>";
			}else{
			
				$return_str .="<li style='border-right: solid 50px #f0f0f0'>";
				$return_str .=$title." published by ".$publisher_name."<br />";
				
				$return_str .= "<small>No version can be archived in ".$repositoryName.".</small>";
			}
	
			
			
			$return_str .='<ul><li id="for:value:component:_publication">'.$title.'</li><li id="for:value:component:_publisher">'.$publisher_name.'</li>';
			if (defined($issn) && (!(defined ($issn2)))) {
				$return_str .='<li id="for:value:component:_issn">'.$issn.'</li>';
			}
			
			$return_str .='<li id="for:block:absolute:publisher_policy"><a href="https://v2.sherpa.ac.uk/romeo"><img src="/style/images/sherparomeo.jpg" style="float: right; padding-right: 1em"/></a>Journal autocompletion information is derived from the <a href="https://v2.sherpa.ac.uk/romeo">Sherpa Romeo</a> database, an online resource that aggragates and analyses publisher open access policies.<p> This publication, <a title="Link to the publication information on Sherpa/RoMEO" target="_new" href="http://v2.sherpa.ac.uk/id/publication/'.$publication_id.'">'.$title.'</a>, is published by <a target="_new" title="Link to the publishers information on Sherpa/RoMEO" href="http://v2.sherpa.ac.uk/id/publisher/'.$publisher_id.'">'.$publisher_name.'</a>.</p>';
			
			if ($permitted_oa_versions ne ""){
				$return_str .='The depositor can archive '.$permitted_oa_versions." ".$versions." without additional Open Access fees.";
			}
			else{
				my $possible_with_fee=0;
				for (my $iter = 0; $iter < $i; $iter++) {
					if ($PolicySummary[$iter][6] eq 'with_oa_fee'){
						$possible_with_fee=1;
					}
				}
				if (! $possible_with_fee){
					$return_str .='The depositor cannot archive any version in '.$repositoryName.'.';
				}
				else{
					$return_str .='The depositor cannot archive any version in '.$repositoryName.' without an additional open access fee to the publisher.';
				}
				
			}
			
			
			for (my $iter = 0; $iter < $i; $iter++) {
				if ($PolicySummary[$iter][6] ne 'with_oa_fee'){
				if ($PolicySummary[$iter][1] ne ''){
						#there are conditions listed
						$return_str.= '<p>';
						#list the conditions for this version
						$return_str.='The publisher also defines the following conditions for deposit of '.$PolicySummary[$iter][0].' version:<ul>';
						if ($PolicySummary[$iter][7] ne ''){
							$return_str.='<li>Required license of deposit: '.$PolicySummary[$iter][7].'</li>';
						}
						if ($PolicySummary[$iter][3] ne ''){
							$return_str.='<li>Prerequisite condition(s):<ul>'.$PolicySummary[$iter][3].'</ul></li>';
						}
						if ($PolicySummary[$iter][4] ne ''){
							$return_str.='<li>Prerequisite funder(s):<ul>'.$PolicySummary[$iter][4].'</ul></li>';
						}
						if ($PolicySummary[$iter][5] ne ''){
							$return_str.='<li>Prerequisite subject(s):<ul>'.$PolicySummary[$iter][5].'</ul></li>';
						}
						if ($PolicySummary[$iter][2] ne ''){
							$return_str.='<li>Embargo period of '.$PolicySummary[$iter][2].'</li>';
						}
						$return_str.=$PolicySummary[$iter][1];
						$return_str.='</ul></p>';
					}else{
						#there are no conditions, but could be embargo, prerequisites or license
						if (($PolicySummary[$iter][7] ne '')||($PolicySummary[$iter][2] ne '')||($PolicySummary[$iter][3] ne '')||($PolicySummary[$iter][4] ne '')||($PolicySummary[$iter][5] ne '')){
							$return_str.='The publisher also defines the following requirements for deposit of '.$PolicySummary[$iter][0].' version:<ul>';
							if ($PolicySummary[$iter][7] ne ''){
								$return_str.='<li>Required license of deposit: '.$PolicySummary[$iter][7].'</li>';
							}
							if ($PolicySummary[$iter][2] ne ''){
								$return_str.='<li>Embargo period of '.$PolicySummary[$iter][2].'</li>';
							}
							if ($PolicySummary[$iter][3] ne ''){
								$return_str.='<li>Prerequisite condition(s):<ul>'.$PolicySummary[$iter][3].'</ul></li>';
							}
							if ($PolicySummary[$iter][4] ne ''){
								$return_str.='<li>Prerequisite funder(s):<ul>'.$PolicySummary[$iter][4].'</ul></p>';
							}
							if ($PolicySummary[$iter][5] ne ''){
								$return_str.='<li>Prerequisite subjects(s):<ul>'.$PolicySummary[$iter][5].'</ul></li>';
							}
						}
						
				}
				}
			}
			
			$return_str .="</li></ul></li>\n";
			
			
		}
	}
	print OUTFILE $return_str;
}



#Finish up
close OUTFILE;

#check if processing completed , if yes, replace live file with constructed file
rename ($construct_file, $out_file);

