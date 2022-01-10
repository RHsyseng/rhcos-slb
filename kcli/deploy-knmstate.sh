#/bin/bash -e

knmstate_version=v0.64.4

oc apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/$knmstate_version/nmstate.io_nmstates.yaml
oc apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/$knmstate_version/namespace.yaml
oc apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/$knmstate_version/service_account.yaml
oc apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/$knmstate_version/role.yaml
oc apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/$knmstate_version/role_binding.yaml
oc apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/$knmstate_version/operator.yaml

cat <<EOF | kubectl apply -f -
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
 name: nmstate
allowPrivilegedContainer: true
allowHostDirVolumePlugin: true
allowHostNetwork: true
allowHostIPC: false
allowHostPID: false
allowHostPorts: false
readOnlyRootFilesystem: false
runAsUser:
 type: RunAsAny
seLinuxContext:
 type: RunAsAny
users:
- system:serviceaccount:nmstate:nmstate-handler
EOF

cat <<EOF | kubectl apply -f -
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF

sleep 30

oc rollout status -w -n nmstate ds nmstate-handler
oc rollout status -w -n nmstate deployment nmstate-webhook
