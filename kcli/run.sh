#!/bin/bash -e
plan=$1
openshift_pull=$2

tmpdir=$(mktemp -d)

butane() {
	podman run --rm --interactive \
	  --security-opt label=disable \
	    --volume ${PWD}:/pwd --workdir /pwd \
	      quay.io/coreos/butane:release
}

trap 'rm -rf -- "$tmpdir"'  EXIT

cp -r * $tmpdir


if [ "$openshift_pull" != "" ]; then
    cp $openshift_pull $tmpdir/openshift_pull.json
fi

cd $tmpdir

patch -p1 < kcli/ignition.patch

butane < custom-config.fcc > rhocs-slb-worker-0.ign
cp rhocs-slb-worker-0.ign rhocs-slb-master-0.ign

mkdir -p manifests
export base64_script_content=$(cat setup-ovs.sh|base64 -w 0) 
envsubst <  mco_ovs_workers.yml.tmpl > manifests/mco_ovs_workers.yml 
envsubst < mco_ovs_supervisor.yml.tmpl > manifests/mco_ovs_supervisor.yml

kcli create plan --force -f $plan rhcos-slb
