// Copyright 2016 CoreOS, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package misc

import (
	"encoding/base64"
	"fmt"
	"net"
	"strings"

	"github.com/coreos/mantle/kola/cluster"
	"github.com/coreos/mantle/kola/register"
	"github.com/coreos/mantle/platform"
	"github.com/coreos/mantle/platform/conf"
	"github.com/coreos/mantle/platform/machine/unprivqemu"
)

func init() {
	register.RegisterTest(&register.Test{
		Run:         NetworkSecondaryNics,
		ClusterSize: 0,
		Name:        "rhcos.network.multiple-nics",
		Distros:     []string{"rhcos"},
		Platforms:   []string{"qemu-unpriv"},
	})
}

// NetworkSecondaryNics verifies that secondary NICs are created on the node
func NetworkSecondaryNics(c cluster.TestCluster) {
	primaryMac := "52:55:00:d1:56:00"
	secondaryMac := "52:55:00:d1:56:01"
	ovsBridgeInterface := "brcnv-iface"

	setupMultipleNetworkTest(c, primaryMac, secondaryMac)

	m := c.Machines()[0]
	checkExpectedMAC(c, m, ovsBridgeInterface, primaryMac)
}

func checkExpectedMAC(c cluster.TestCluster, m platform.Machine, interfaceName, expectedMac string) {
	interfaceMACAddress, err := getInterfaceMAC(c, m, interfaceName)
	if err != nil {
		c.Fatalf("failed to fetch interface %s MAC Address: %v", interfaceName, err)
	}

	if interfaceMACAddress != expectedMac {
		c.Fatalf("interface %s MAC %s does not match expected MAC %s", interfaceName, interfaceMACAddress, expectedMac)
	}
}

func getInterfaceMAC(c cluster.TestCluster, m platform.Machine, interfaceName string) (string, error) {
	output := string(c.MustSSH(m, fmt.Sprintf("nmcli -g 802-3-ethernet.cloned-mac-address connection show %s", interfaceName)))
	output = strings.Replace(output, "\\:", ":", -1)

	var macAddress net.HardwareAddr
	var err error
	if macAddress, err = net.ParseMAC(output); err != nil {
		return "", fmt.Errorf("failed to parse MAC address %v for interface Name %s: %v", output, interfaceName, err)
	}

	return macAddress.String(), nil
}

func addKernelArgs(c cluster.TestCluster, m platform.Machine, args []string) {
	if len(args) == 0 {
		return
	}

	rpmOstreeCommand := "sudo rpm-ostree kargs"
	for _, arg := range args {
		rpmOstreeCommand = fmt.Sprintf("%s --append %s", rpmOstreeCommand, arg)
	}

	c.RunCmdSync(m, rpmOstreeCommand)

	err := m.Reboot()
	if err != nil {
		c.Fatalf("failed to reboot the machine: %v", err)
	}
}

func setupMultipleNetworkTest(c cluster.TestCluster, primaryMac, secondaryMac string) {
	var m platform.Machine
	var err error

	options := platform.QemuMachineOptions{
		SecondaryNics: 2,
	}

	var userdata *conf.UserData = conf.Ignition(fmt.Sprintf(`{
		"ignition": {
			"version": "3.2.0"
		},
		"storage": {
			"files": [
				{
					"path": "/usr/local/bin/capture-macs",
					"contents": { "source": "data:text/plain;base64,%s" },
					"mode": 755
				},
				{
					"path": "/usr/local/bin/setup-ovs",
					"contents": { "source": "data:text/plain;base64,%s" },
					"mode": 755
				}
			]
		},
		"systemd": {
			"units": [
				{
					"enabled": true,
					"name": "openvswitch.service"
				},
				{
					"contents": "[Unit]\nDescription=Capture MAC address from kargs\nAfter=network-online.target\nAfter=openvswitch.service\nConditionKernelCommandLine=macAddressList\nRequiresMountsFor=/boot\n\n[Service]\nType=oneshot\nMountFlags=slave\nExecStart=/usr/local/bin/capture-macs\n\n[Install]\nRequiredBy=multi-user.target\n",
					"enabled": true,
					"name": "capture-macs.service"
				},
				{
					"contents": "[Unit]\nDescription=Setup OVS bonding\nAfter=capture-macs.service\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/setup-ovs\n\n[Install]\nRequiredBy=multi-user.target\n",
					"enabled": true,
					"name": "setup-ovs.service"
				}

			]
		}
	}`,
		base64.StdEncoding.EncodeToString([]byte(captureMacsScript)),
		base64.StdEncoding.EncodeToString([]byte(setupOvsScript))))

	switch pc := c.Cluster.(type) {
	// These cases have to be separated because when put together to the same case statement
	// the golang compiler no longer checks that the individual types in the case have the
	// NewMachineWithQemuOptions function, but rather whether platform.Cluster
	// does which fails
	case *unprivqemu.Cluster:
		m, err = pc.NewMachineWithQemuOptions(userdata, options)
	default:
		panic("unreachable")
	}
	if err != nil {
		c.Fatal(err)
	}

	// Add karg needed for the ignition to configure the network properly.
	addKernelArgs(c, m, []string{fmt.Sprintf("macAddressList=%s,%s", primaryMac, secondaryMac)})
}
