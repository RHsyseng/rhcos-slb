#!/bin/bash -ex

tmpdir=$(mktemp -d)

butane() {
	podman run --rm --interactive \
	  --security-opt label=disable \
	    --volume ${PWD}:/pwd --workdir /pwd \
	      quay.io/coreos/butane:release
}

trap 'rm -rf -- "$tmpdir"'  EXIT

cp -r * $tmpdir

cd $tmpdir

patch -p1 < kcli/ignition.patch

export base64_capture_macs_script_content=$(cat capture-macs.sh|base64 -w 0) 
envsubst < custom-config.fcc.tmpl  > custom-config.fcc
butane < custom-config.fcc > rhocs-slb-worker-0.ign
cp rhocs-slb-worker-0.ign rhocs-slb-ctlplane-0.ign

mkdir -p manifests
export base64_script_content=$(cat init-interfaces.sh|base64 -w 0) 
envsubst < mco_ovs_workers.yml.tmpl > manifests/mco_ovs_workers.yml
envsubst < mco_ovs_supervisor.yml.tmpl > manifests/mco_ovs_supervisor.yml

if [[ $0 =~ run.sh ]]; then
    plan=$1
    openshift_pull=$2
    if [ "$openshift_pull" != "" ]; then
        cp $openshift_pull $tmpdir/openshift_pull.json
    fi
    kcli create plan --force -f $plan rhcos-slb
elif [[ $0 =~ apply.sh ]]; then
    oc apply $tmpdir/manifests
fi
