#!/usr/bin/perl -w
#
#This Perl Nagios/Icinga plugin retrieves all alarms from VMWare vSphere.
#You can filter the alarms with various options for ex- and including items.
#If you're already using alarm rules in vSphere this plugin may help you to have 
#your monitoring in one place instead of two.
#
#The pluging needs the VMWare Perl SDK to be installed on your monitoring server.
#This plugin has been tested with the SDK v5.0, v5.5 and 6.0.
#
#
#Copyright (c) 2016 www.usolved.net 
#Published under https://github.com/usolved/check_usolved_vsphere_alarms
#
#
#This program is free software; you can redistribute it and/or
#modify it under the terms of the GNU General Public License
#as published by the Free Software Foundation; either version 2
#of the License, or (at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty
#of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program. If not, see <http://www.gnu.org/licenses/>.
#
#---------------------------------------------------------------------------------------
#
#   v1.3 2017-01-12
# - Added possibility to filter for the name of the alarm message
#
#   v1.2 2016-12-06
# - Removed unnecessary function for accessing the "alarmManager"
#
#   v1.1 2016-09-12
# - Acknowledged alarms won't count as warning or critical anymore
# - Number of acknowledged alarms in the status info output
#
#   v1.0 2015-07-02
# - Initial release
#



use strict;
use warnings;

#---------------------------------------------------------------------------------------
# Load modules

use VMware::VIRuntime;	#To access the VMWare SDK
use Getopt::Long;		#Parse the parameters
use File::Spec;			#For splitting the path to get the filename


#---------------------------------------------------------------------------------------
# Define variables

my $output_nagios 			= "";
my $output_nagios_extended	= "";
my $output_return_code 		= 0;

my $count_warning 			= 0;
my $count_critical 			= 0;
my $count_acknowledged		= 0;

my ($option_host, $option_username, $option_password, $option_authfile, $option_check);
my %checks;


my ($volume, $directory, $file) = File::Spec->splitpath(__FILE__);
my $scriptname = $file;


#---------------------------------------------------------------------------------------
# Define functions


#Print out the help information
sub output_usage
{
   print <<EOT;
-H, --hostname=HOST
    Name or IP address of host to check
-U, --username=USERNAME
    Local or domain user for vSphere. If you use windows login make sure to escape the backslash like domainname\\\\username
-P, --password=PASSWORD
    Password for the given username
-F, --authfile=PATH
    Authentication file with login and password.
    File syntax :
       username=<login>
       password=<password>
-C, --check=CHECK
    Specify what you want to check. By default the plugin checks all alarms.

    Syntax:
    <MODE>:<SELECT>=<SUBSELECT>

    MODE:
    	i = include check
    	e = exclude check

    SELECT:
    	type = just check vms, ds or esx hosts alarms

    		SUBSELECT:
    		vm  = virtual machine
    		ds  = datastore
    		esx = host system

    	object = to check a specific object name like a vm name

    		SUBSELECT:
    		name of the vm, ds or esx host. wildcard is allowed like *vmname*

    	name = to filter for a specific alarm message

    		SUBSELECT:
    		name of the alarm message. wildcard is allowed like *Virtual SAN*

    	status = just show either warnings or criticals

    		SUBSELECT:
    		warning  = alarms marked as warnings
    		critical = alarms marked as criticals

    	datacenter = to filter alarms for a specific datacenter

    		SUBSELECT:
    		name of your datacenter


    <i|e>:type:<vm|ds|esx>
    <i|e>:object:<name of your vm, ds or esx>
    <i|e>:name:<alarm message>
    <i|e>:status:<warning|critical>
    <i|e>:datacenter:<name of your datacenter>

    Examples:
    1. just show alarms from esx hosts
    ./$scriptname -H 172.0.1.1 -U username -P password -C i:type=esx

    2. just show alarms from esx hosts using credentials from authfile
    ./$scriptname -H 172.0.1.1 -F /path/to/authfile -C i:type=esx

    3. check all datastores with critical alarms but don't show datastores with name dsname03
    ./$scriptname -H 172.0.1.1 -U username -P password -C i:type=ds,i:status=critical,e:object=dsname03

    Remember that the include has a higher priority than the exclude.

EOT
	exit 3;
}


#get all the parameters and to a little error handling
sub get_options
{
	if(@ARGV < 1)
	{
		output_usage();
	}

	Getopt::Long::Configure ("bundling");
	GetOptions(
		"H|hostname=s"     => \$option_host,
		"U|username=s"     => \$option_username,
		"P|password=s"     => \$option_password,
		"F|authfile=s"     => \$option_authfile,
		"C|check=s"        => \$option_check
	);

	if(!defined($option_host))
	{
		print "Error - hostname is required.\n";
		output_usage();
	}

	if (!defined($option_username) || !defined($option_password))
	{
		if (!defined($option_authfile))
		{
			print "Error - username and password or authfile are required.\n";
			output_usage();
		}
	}

	if (defined($option_authfile))
	{
		open (AUTH_FILE, $option_authfile) || die "Unable to open auth file \"$option_authfile\"\n";
		while( <AUTH_FILE> ) {
			if(s/^[ \t]*username[ \t]*=//){
				s/^\s+//;s/\s+$//;
				$option_username = $_;
			}
			if(s/^[ \t]*password[ \t]*=//){
				s/^\s+//;s/\s+$//;
				$option_password = $_;
			}
		}
	}
}

#connect to the vsphere server with user and password
sub connect_vsphere
{
	Util::connect("https://" . $option_host . "/sdk/webService", $option_username, $option_password);
}

#when parameter -C is given check for all the include/exclude rules
sub check_rules
{
	my($e_or_i, %alarm_item) 	= @_;

	my $return_value_default 	= 1;
	my $return_value_onresult 	= 0;


	if($e_or_i eq "i")
	{
		#if nothing is found, then continue to the excluded checks
		$return_value_default 	= 1;
		$return_value_onresult 	= 0;
	}
	elsif($e_or_i eq "e")
	{
		#if nothing is found, then continue to the output of the alarm
		$return_value_default 	= 1;
	}




	#reset hash by reading elements from hash, else the while would be skipped
	scalar keys %checks;

	while((my $item) = each %checks)
	{
		#Check if object is excluded
		if($checks{$item}{'MODE'} eq $e_or_i && $checks{$item}{'SELECT'} eq "object")
		{
			my $first_char = substr($checks{$item}{'SUBSELECT'}, 0, 1);
			my $last_char 	= substr($checks{$item}{'SUBSELECT'}, -1);

			#if wildcard syntax is used
			if($first_char eq "*" && $last_char eq "*")
			{

				my $tmp1 = substr($checks{$item}{'SUBSELECT'}, 1);
				my $tmp2 = substr($tmp1, 0,-1);

				#check if the alarm contains the check option 
				if(index($alarm_item{'OBJECT'}, $tmp2) != -1)
				{
					return $return_value_onresult;
				}
			}
			else
			{
				#else check for and exact match
				if($checks{$item}{'SUBSELECT'} eq $alarm_item{'OBJECT'})
				{
					return $return_value_onresult;
				}
			}

			
		}
		#Check if name is excluded
		elsif($checks{$item}{'MODE'} eq $e_or_i && $checks{$item}{'SELECT'} eq "name")
		{
			my $first_char = substr($checks{$item}{'SUBSELECT'}, 0, 1);
			my $last_char 	= substr($checks{$item}{'SUBSELECT'}, -1);

			#if wildcard syntax is used
			if($first_char eq "*" && $last_char eq "*")
			{

				my $tmp1 = substr($checks{$item}{'SUBSELECT'}, 1);
				my $tmp2 = substr($tmp1, 0,-1);

				#check if the alarm contains the check option 
				if(index($alarm_item{'NAME'}, $tmp2) != -1)
				{
					return $return_value_onresult;
				}
			}
			else
			{
				#else check for and exact match
				if($checks{$item}{'SUBSELECT'} eq $alarm_item{'NAME'})
				{
					return $return_value_onresult;
				}
			}

			
		}
		#Check if status warning or critical is excluded
		elsif($checks{$item}{'MODE'} eq $e_or_i && $checks{$item}{'SELECT'} eq "status")
		{

			if($checks{$item}{'SUBSELECT'} eq "warning" && $alarm_item{'STATUS'} eq "yellow")
			{
				return $return_value_onresult;
			}
			elsif($checks{$item}{'SUBSELECT'} eq "critical" && $alarm_item{'STATUS'} eq "red")
			{
				return $return_value_onresult;
			}
		}
		#Check if type like vm, ds or esx is excluded
		elsif($checks{$item}{'MODE'} eq $e_or_i && $checks{$item}{'SELECT'} eq "type")
		{
			if($checks{$item}{'SUBSELECT'} eq "vm" && $alarm_item{'TYPE'} eq "VirtualMachine")
			{
				return $return_value_onresult;
			}
			elsif($checks{$item}{'SUBSELECT'} eq "ds" && $alarm_item{'TYPE'} eq "Datastore")
			{
				return $return_value_onresult;
			}
			elsif($checks{$item}{'SUBSELECT'} eq "esx" && $alarm_item{'TYPE'} eq "HostSystem")
			{
				return $return_value_onresult;
			}
		}
		#Check if type like vm, ds or esx is excluded
		elsif($checks{$item}{'MODE'} eq $e_or_i && $checks{$item}{'SELECT'} eq "datacenter" && $checks{$item}{'SUBSELECT'} eq $alarm_item{'DATACENTER'})
		{
			return $return_value_onresult;
		}


	}

	#return true or false depending on the rule match
	return($return_value_default);
}

#get all alarms from the vpshere
sub get_alarms
{
	my $datacenter_views = Vim::find_entity_views(view_type => "Datacenter");


	if(!defined($datacenter_views))
	{
		die("Datacenter objects not found\n");
		exit 3;
	}


	if(defined($option_check))
	{
		#split explicit checks to array
		my @option_check_splitted = split /,/, $option_check;

		my $i = 0;
		foreach(@option_check_splitted)
		{
			#seperate include and exclude from the select
	    	my @splitted = split /:/, $_;

	    	$checks{$i}{"MODE"} 		= $splitted[0];

	   
	    	#split the select and subselect
	    	if(defined($splitted[1]))
	    	{
		    	my @splitted_select = split /=/, $splitted[1];
				foreach(@splitted_select)
				{
		    		$checks{$i}{"SELECT"} 		= $splitted_select[0];
		    		$checks{$i}{"SUBSELECT"} 	= $splitted_select[1];
		    	}
	    	}
	    	else
	    	{
	    		print "Value for -C is not correct. Type parameter --help for more information.\n";
	    		exit 3;
	    	}

	    	$i++;
		}
	}



	#----------------------------------------------------------------------
	#Loop through all alarms

	foreach my $datacenter_view (@$datacenter_views)
	{
		if(defined($datacenter_view->triggeredAlarmState))
		{
			foreach my $alarms (@{$datacenter_view->triggeredAlarmState})
			{
				#API documentation
				#https://www.vmware.com/support/developer/converter-sdk/conv60_apireference/vim.alarm.AlarmState.html
				my $entity 					= Vim::get_view(mo_ref => $alarms->entity);
				my $alarm 					= Vim::get_view(mo_ref => $alarms->alarm);
				my $acknowledged 			= $alarms->acknowledged;
				my $time					= $alarms->time;
				my $check_rule_status_i 	= 0;
				my $check_rule_status_e 	= 1;
				my %alarm_item;

				#check only not acknowledged alarms
				if($acknowledged == 0)
				{
					$alarm_item{"NAME"} 		= $alarm->info->name;
					$alarm_item{"STATUS"} 		= $alarms->overallStatus->val;
					$alarm_item{"OBJECT"} 		= $entity->name;
					$alarm_item{"DATACENTER"} 	= $datacenter_view->name;
					$alarm_item{"TYPE"} 		= $alarms->entity->type;


					#only if parameter -C is given
					if(defined($option_check))
					{
						$check_rule_status_i = check_rules("i", %alarm_item);
					}


					#by default just ignore the statement if no included found or -C is not given
					if($check_rule_status_i == 0)
					{
						#only if parameter -C is given
						if(defined($option_check))
						{
							$check_rule_status_e = check_rules("e", %alarm_item);
						}

						#if no check rules are defined, this will always be true
						if($check_rule_status_e == 1)
						{

							if($alarms->overallStatus->val eq "yellow")
							{
								$output_nagios_extended .= "Warning - ";
								$count_warning++;
							}
							elsif($alarms->overallStatus->val eq "red")
							{
								$output_nagios_extended .= "Critical - ";
								$count_critical++;
							}
							else
							{
								$output_nagios_extended .= "Unknown - ";
							}

							$output_nagios_extended .= $alarm_item{"NAME"}." on ".$alarm_item{"OBJECT"} ." (".$alarm_item{"DATACENTER"}.": ".$alarm_item{"TYPE"}.")\n";
						}
					}
				}
				else
				{
					#count each acknowledged alarm for later output
					$count_acknowledged++
				}
			}
		}
	} 


	#if any critical alarms found exit with critical code
	if($count_critical > 0)
	{
		$output_return_code = 2;
	}
	elsif($count_warning > 0)
	{
		$output_return_code = 1;
	}
	else
	{	
		$output_return_code = 0;
	}


	Util::disconnect();
}

#summarize alarms and build output string for nagios/icinga return
sub output_nagios
{
	my $count_alarms_all 	= $count_warning + $count_critical;
	my $output_acknowledged = "";


	if($count_acknowledged > 0)
	{
		$output_acknowledged = " (".$count_acknowledged." acknowledged)";
	}


	if($output_return_code == 0)
	{
		$output_nagios .= "OK - No alarms found".$output_acknowledged;	
	}
	elsif($output_return_code == 1)
	{
		$output_nagios .= "Warning - ".$count_alarms_all." alarms found".$output_acknowledged.". View extended output for more information.";
	}
	elsif($output_return_code == 2)
	{
		$output_nagios .= "Critical - ".$count_alarms_all." alarms found".$output_acknowledged.". View extended output for more information.";
	}
	else
	{
		$output_nagios .= "Unknown - No Status available";
	}

	print $output_nagios."\n".$output_nagios_extended;
}


#---------------------------------------------------------------------------------------
# Call functions

get_options();
connect_vsphere();
get_alarms();
output_nagios();

#exit with the appropriate code for nagios or icinga
exit $output_return_code;
