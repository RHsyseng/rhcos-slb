# <u>Setting Bond to specific nics in the ignition process</u>

## Overview 
This guide explaines how to bond specific nics during the initial installation with OVS and supplies the Ignition and scripts to achive this. 

## Importent
- All Rew Files and scripts are located in the RewFiles folder 
- Note: This Guide is aiming for installation using PXE server
<br>

## Prerequisits
- PXE server with change host args permissions 
- Shared location to upload the <i> capturemacs.ign </i> file  

## Usage  
<br>

### <U>1. Adding parameters to PXE server </u>
Key   |  Type | Value | Exmaple |Discription
---   | --- | --- | --- | --- |
extra-kargs  | String | ignition.config.url=http://{Location Which the PXE and remote VM can reach in order to get the ignition file }/capturemacs.ign custom-config | ignition.config.url=http://my.pxe.server.redhat.com//capturemacs.ign custom-config | This parmeter is used to allow the server to reload an extra ignition file which captures the MAC addresses and save them into a file for the machine config later use
macAddressList | string | List of MAC address should be set per host | 00:01:02:03:04:05,06:07:08:09:10:11 ... |This will be the list of MAC addresses which exists on the node and will be grebed by the ignition file 
<br>

### <u>2. Preper the files</u>
- Copy/Upload <i> capturemacs.ign </i> to shared location which the PXE,Worker can access and get the file once needed

- File <i>96-configure-ovs-bonding.yaml</i> is a machine config , you can run it manually once the cluster is up or add it to you installaion process/scripts 
<br>

### <u>3. Run the installation </u>







