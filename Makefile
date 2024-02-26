SHELL := /bin/bash

PULL_SECRET ?= openshift_pull.json
OUT_DIR = $(CURDIR)/build/_output/

all: build-manifests test

test:
	./tests/test-coreos.sh

build-manifests:
	./hack/build-manifests.sh ${OUT_DIR}

kcli-run-ocp:
	./kcli/run.sh ./kcli/ocp.yaml ${PULL_SECRET}

kcli-run-rhcos:
	./kcli/run.sh ./kcli/rhcos.yaml ${PULL_SECRET}

.PHONY: \
	test \
	build-manifests \
	kcli-run-ocp \
	kcli-run-rhcos
