#!/usr/bin/env bash

set -ex

dnf install -y git go make wget qemu qemu-img swtpm npm >/dev/null
npm i -D tap-junit >/dev/null
