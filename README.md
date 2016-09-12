# check_usolved_vsphere_alarms

## Overview

This Perl Nagios/Icinga plugin retrieves all alarms from VMWare vSphere.
You can filter the alarms with various options for ex- and including items.

If you're already using alarm rules in vSphere this plugin may help you to have your monitoring in one place instead of two.

## Authors

Ricardo Klement ([www.usolved.net](http://usolved.net))

## Installation

Just copy the file check_usolved_vsphere_alarms.pl into your Nagios plugin directory.
For example into the path /usr/local/nagios/libexec/

Add execution permission for the nagios user on check_usolved_vsphere_alarms.php.
If you have at least Perl 5 and the VMWare Perl SDK  installed this plugin should run out-of-the-box.

If you get errors while executing the plugin install the missing modules.

###Install default Perl modules

With yum package manager (RedHat, CentOS, ...)
```
yum install perl-Getopt-Long-Descriptive
yum install perl-File-Spec
```

Or with CPAN
```
cpan install Getopt::Long
cpan install File::Spec
```


###Install VMWare Perl SDK

This plugin needs the VMWare Perl SDK for connecting to the vSphere or ESX servers. If you are using other plugins like check_vmware_esx.pl or check_esx3.pl you may already have this SDK installed. If you don't have it, please fallow these steps to install it.

1. Go go [VMWare](https://my.vmware.com/web/vmware/downloads) and search for Perl SDK
2. Download the proper Perl SDK for your vSphere release (you need to register at VMWare to download the SDK)
3. Upload the tar.gz to your Nagios/Icinga server and install it

```
tar -xzf VMware-vSphere-Perl-SDK-5.5.0-1384587.x86_64.tar.gz
cd vmware-vsphere-cli-distrib
./vmware-install.pl
```


## Usage

### Test on command line
If you are in the Nagios plugin directory execute this command:

```
./check_usolved_vsphere_alarms.pl -H 172.0.1.1 -U username -P password
```

The output could look like this:

```
Critical - 10 alarms found. View extended output for more information.
Critical - Network-Uplink-Redundancy lost on ESX1 (DATACENTER1: HostSystem)
Warning - CPU-Usage of Virtual Machine on SERVER3 (DATACENTER2: VirtualMachine)
Critical - CPU-Usage of Virtual Machine on SERVER1 (DATACENTER2: VirtualMachine)
Critical - Data storage disk on DATASTORE1 (DATACENTER1: Datastore)
Critical - Data storage disk on DATASTORE2 (DATACENTER1: Datastore)
Warning - Data storage disk on DATASTORE3 (DATACENTER1: Datastore)
Warning - Data storage disk on DATASTORE4 (DATACENTER1: Datastore)
Warning - Data storage disk on DATASTORE5 (DATACENTER1: Datastore)
Critical - SimpliVity OmniCube Available Physical Capacity 10 Percent or Less on ESX3 (DATACENTER1: HostSystem)
Critical - SimpliVity Datacenter Available Physical Capacity 10 Percent or Less on SERVER2 (DATACENTER1: Datacenter)
```

Here's an example with some filters:

```
./check_usolved_vsphere_alarms.pl -H 172.0.1.1 -U username -P password -C i:type=ds,i:status=critical
```

The output could look like this:

```
Critical - 2 alarms found. View extended output for more information.
Critical - Data storage disk on DATASTORE1 (DATACENTER1: Datastore)
Critical - Data storage disk on DATASTORE2 (DATACENTER1: Datastore)
```

Here are all arguments that can be used with this plugin:

```
-H, --hostname=HOST
    Name or IP address of host to check
-U, --username=USERNAME
    Local or domain user for vSphere. If you use windows login make sure to escape the backslash like domainname\\\\username
-P, --password=PASSWORD
    Password for the given username
-C, --check=CHECK
    Specify what you want to check. By default the plugin checks all alarms.

    Syntax:
    &lt;MODE&gt;:&lt;SELECT&gt;=&lt;SUBSELECT&gt;

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

    	status = just show either warnings or criticals

    		SUBSELECT:
    		warning  = alarms marked as warnings
    		critical = alarms marked as criticals

    	datacenter = to filter alarms for a specific datacenter

    		SUBSELECT:
    		name of your datacenter


    &lt;i|e&gt;:type:&lt;vm|ds|esx&gt;
    &lt;i|e&gt;:object:&lt;name of your vm, ds or esx&gt;
    &lt;i|e&gt;:status:&lt;warning|critical&gt;
    &lt;i|e&gt;:datacenter:&lt;name of your datacenter&gt;

    Examples:
    1. just show alarms from esx hosts
    ./check_usolved_vsphere_alarms.pl -H 172.0.1.1 -U username -P password -C i:type=esx

    2. check all datastores with critical alarms but don't show datastores with name dsname03
    ./check_usolved_vsphere_alarms.pl -H 172.0.1.1 -U username -P password -C i:type=ds,i:status=critical,e:object=dsname03

    Remember that the include has a higher priority than the exclude.
```

### Install in Nagios/Icinga

Edit your **commands.cfg** and add the following.

Example for basic check (with host macro for username and password):

```
define command {
    command_name    check_usolved_vsphere_alarms
    command_line    $USER1$/check_usolved_vsphere_alarms.pl -H $HOSTADDRESS$ -U $_HOSTUSER$ -P $_HOSTPASSWORD$
}
```

Example for using a filter:

```
define command {
    command_name    check_usolved_vsphere_alarms
    command_line    $USER1$/check_usolved_vsphere_alarms.pl -H $HOSTADDRESS$ -U $_HOSTUSER$ -P $_HOSTPASSWORD$ -C $ARG1$
}
```

Edit your **services.cfg** and add the following.

Example for basic check with all alarms:

```
define service{
	host_name				Test-Server
	service_description		vSphere-Alarms
	use						generic-service
	check_command			check_usolved_vsphere_alarms
}
```

Example for excluding warnings:

```
define service{
	host_name				Test-Server
	service_description		vSphere-Alarms
	use						generic-service
	check_command			check_usolved_vsphere_alarms!i:status=warning
}
```

## Whats new

v1.1 2016-09-12
- Acknowledged alarms won't count as warning or critical anymore
- Number of acknowledged alarms in the status info output

v1.0 2015-07-02
- Initial release

