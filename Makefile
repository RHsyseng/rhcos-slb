SHELL := /bin/bash

OUT_DIR = $(CURDIR)/build/_output/

all: build-manifests test

test:
	./tests/test-coreos.sh

build-manifests:
	./hack/build-manifests.sh ${OUT_DIR}

kcli-run-ocp:
	./kcli/run.sh ./kcli/ocp.yaml openshift-pull.json

kcli-add-slb:
	./kcli/add-slb.sh

kcli-del-slb:
	./kcli/del-slb.sh

kcli-run-rhcos:
	./kcli/run.sh ./kcli/rhcos.yaml openshift-pull.json

.PHONY: \
	test \
	build-manifests \
	kcli-run-ocp \
	kcli-add-slb \
	kcli-del-slb \
	kcli-run-rhcos
