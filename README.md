# Setting up network bonding on specific interfaces during the ignition process

## Overview 
This guide explains how to bond specific NICs during the initial OpenShift installation with OVS and supplies the Ignition and scripts to achieve this.

## Important
This guide describes the customisations needed for installation when using a PXE server.

## Prerequisites
- [Fcct](https://github.com/coreos/butane) software to be able to convert fcc to ign files.
- PXE server with ability to set kernel arguments.
- Web accessible location (HTTP only) to upload the custome ign files.

## Usage  

### 1. Adding parameters to PXE server
Key   |  Type | Value | Exmaple |Discription
---   | --- | --- | --- | --- |
ignition.config.url  | String | http://{location reachable to PXE and remote VM in order to get the ignition file}/```file.ign``` custom-config | ignition.config.url=```http://my.web.server.redhat.com/file.ign``` custom-config | This parameter is used to allow the server to load an extra ignition file which captures the MAC addresses and saves them into a file for later use in  machine config.
macAddressList | String | List of MAC address should be set per host In the following order:  1. Primary NIC  2. Secondary NIC  3. All the rest (optional)| 00:01:02:03:04:05,06:07:08:09:10:11 ... | This will be the list of MAC addresses which exist on the host and will be grabbed by the ignition file.


### 2. Prepare the files
- Create the ign file from the custom-config.fcc: 
```
fcct custom-config.fcc > file.ign
```

  - Upload `file.ign` to a shared location which the OpenShift nodes can access.

- Base64 encode the `setup-ovs.sh` file and paste the content into each MCO file into "base64_script_content" section. 

    **TIP:** To update the content you can use:

```
export base64_script_content=$(cat setup-ovs.sh|base64 -w 0) && envsubst <  mco_ovs_workers.yml.tmpl > mco_ovs_workers.yml && envsubst < mco_ovs_supervisor.yml.tmpl > mco_ovs_supervisor.yml
```

- MCO files are MachineConfig, which you can apply manually once the cluster is up or add it to the installation automation/pipeline.

### 3. Run the installation
- Follow the guide to install a bare-metal cluster in the [OpenShift production documentation.
](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.7/html/installing/installing-on-bare-metal)

## Notes
- Changing network configuration is done with the `setup-ovs.sh` file. 

- In order to change the bond type to something other than balance-slb (for example active-backup) ,open the  `setup-ovs.sh` file and search for the “#make bond” section. 
Change *“ovs-port.bond-mode”* to the desired type and make sure that all other related settings are aligned. 

- MachineConfig file is a “Day 2” tool that allows to configure or run scripts on a machine with an installed OS (post-installation).

## CI and Testing
This repo uses [coreos-assembler repo](https://github.com/coreos/coreos-assembler) to run important scenarios relevant to this use-case.
The test downloads the latest RHCOS image and runs network related tests, using the local `setup-ovs.sh` script.
You can run these tests manually on Fedora by running the test script:
```bash
sudo dnf install -y git go make wget qemu qemu-img swtpm
./tests/test-coreos.sh
```

## Additional Documentation 
 - [Redhat CoreOS (RHCORS) features including ignition and machineConfig explanation](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.7/html/architecture/architecture-rhcos)

- [Understanding Machine Config](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.7/html/post-installation_configuration/post-install-machine-configuration-tasks)

 
