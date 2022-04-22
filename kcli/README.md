# Running RHCOS SLB scripts with a kcli libvirt cluster

## Overview 
To test the ignition + machine config files this directory contains some 
scripts to start a [kcli](https://github.com/karmab/kcli) libvirt cluster that
will start OCP 4.10 cluster applying ignition (after patching it) and the
machine config here.

## Prerequisites
- passswordless sudo: To use virt-customize and apply cmdline
- openshift json pull secret file
- kcli: Follow the instructions at https://kcli.readthedocs.io/en/latest/#installation

## Usage

### Start a OCP 4.10 cluster with the ignition + machine config

This will start a two nodes cluster (supervisor/worker) passing the expected 
init cmdline to specify `custom-config` with mac addresses, and apply patched
ignition (it disable create-datastore and remove systemd dependencies at 
capture-macs.sh unit) and the machince config with the OVS bridge setup.

Start the cluster
```bash
./kcli/run.sh ./kcli/ocp.yaml openshift-pull.json
```

Configure the bond with kubernetes-nmstate
```bash
./kcli/add-slb.sh
```

Remove the bond with kubernetes-nmstate
```bash
./kcli/del-slb.sh
```

To apply changes on already deployed cluster.
```bash
./kcli/apply.sh
./kcli/deploy-knmstate.sh
./kcli/add-slb.sh
```

### Start a RHCOS 4.10 image with ignition

To do a quick test just for ingition + kernel cmdline is possible to start a 
RHCOS image that will patch ignition and and start the image.

```bash
./kcli/run.sh ./kcli/rhcos.yaml openshift-pull.json
```
