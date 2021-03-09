# <u>Setting up network bonding on specific interfaces during the ignition process</u>

## Overview 
This guide explains how to bond specific NICs during the initial OpenShift installation with OVS and supplies the Ignition and scripts to achieve this.

## Important
- All raw files and scripts are located in the RewFiles folder.
- This guide describes the customisations needed for installation when using a PXE server.
<br>

## Prerequisites
- PXE server with ability to see kernel arguments.
- Web accessible location(HTTP only) to upload the <i> capturemacs.ign </i> file .

## Usage  
<br>

### <U>1. Adding parameters to PXE server </u>
Key   |  Type | Value | Exmaple |Discription
---   | --- | --- | --- | --- |
ignition.config.url  | String | http://{Location Which the PXE and remote VM can reach in order to get the ignition file }/capturemacs.ign custom-config | ignition.config.url=http://my.web.server.redhat.com/capturemacs.ign custom-config | This parameter is used to allow the server to load an extra ignition file which captures the MAC addresses and save them into a file for later use in  machine config.
macAddressList | String | List of MAC address should be set per host In the following order: <br> 1. Primary NIC <br> 2. Secondary NIC <br> 3. All the rest (optional)| 00:01:02:03:04:05,06:07:08:09:10:11 ... | This will be the list of MAC addresses which exists on the host and will be grabbed by the ignition file.
<br>

### <u>2. Prepare the files</u>
- Upload <i>capturemacs.ign</i> to a shared location which the OpenShift nodes can access and retrieve when needed
File 96-configure-ovs-bonding.yaml is a MachineConfig,which you can apply manually once the cluster is up or add it to the  installation automation/pipeline.


- File <i>96-configure-ovs-bonding.yaml</i> is a machine config , you can run it manually once the cluster is up or add it to you installaion process/scripts 
<br>

### <u>3. Run the installation </u>
- Follow the guide to installing a bare-metal cluster in the [OpenShift production documentation.
](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.7/html/installing/installing-on-bare-metal)

<br>

## Notes
- Changing network configuration is done with the <i>setup-ovs.sh</i> file . 
The contents of the <i>setup-ovs.sh</i> file should be encoded with base64 and implemented in the MachineConfig yaml file.


- In order to change the bond type to something other than balance-slb (for example active-backup) ,open the  <i>setup-ovs.sh</i> file and search for the “#make bond” section. <br>
Change <u>“ovs-port.bond-mode”</u> to the desired type and make sure that all other related settings are aligned. 


- MachineConfig file is a “Day 2” tool that allows to configure or run scripts on a machine with an installed OS(post-installation).

<br>

## Additional Documentation 
 - [Redhat CoreOS (RHCORS) features including ignition and machineConfig explanation](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.7/html/architecture/architecture-rhcos)

- [Understanding Machine Config](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.7/html/post-installation_configuration/post-install-machine-configuration-tasks)

 