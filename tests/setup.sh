#!/usr/bin/env bash

set -ex

install_go() {
	destination=/usr/local
	version=1.18.7
	tarball=go$version.linux-amd64.tar.gz
	url=https://dl.google.com/go/

	mkdir -p $destination
	curl -L -s $url/$tarball -o $destination/$tarball
	tar -xf $destination/$tarball -C $destination
}

install_docker_ce() {
	dnf -y install dnf-plugins-core >/dev/null
	dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
	dnf -y install docker-ce docker-ce-cli containerd.io >/dev/null
	systemctl start docker
}

dnf install -y git go make wget qemu qemu-img swtpm npm tar >/dev/null
npm i -D tap-junit >/dev/null
install_go
install_docker_ce
