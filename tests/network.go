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
	"time"
	"net"
	"os"
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
		Timeout:     20 * time.Minute,
	})
	register.RegisterTest(&register.Test{
		Run:         InitInterfacesPreConfigured,
		ClusterSize: 0,
		Name:        "rhcos.network.init-interfaces-pre-configured",
		Distros:     []string{"rhcos"},
		Platforms:   []string{"qemu-unpriv"},
		Timeout:     20 * time.Minute,
	})
	register.RegisterTest(&register.Test{
		Run:         InitInterfacesNotConfigured,
		ClusterSize: 0,
		Name:        "rhcos.network.init-interfaces-not-configured",
		Distros:     []string{"rhcos"},
		Platforms:   []string{"qemu-unpriv"},
		Timeout:     20 * time.Minute,
	})
}

// NetworkSecondaryNics verifies that secondary NICs are created on the node
func NetworkSecondaryNics(c cluster.TestCluster) {
	primaryMac := "52:55:00:d1:56:00"
	secondaryMac := "52:55:00:d1:56:01"

	setupMultipleNetworkTest(c, primaryMac, secondaryMac)

	m := c.Machines()[0]
	expectedMacsList := []string{primaryMac, secondaryMac}
	checkExpectedMACs(c, m, expectedMacsList)
}

// InitInterfacesPreConfigured checks the scenario where the connections are already pre-configured so the script does
// not configured anything
// The test checks init-interfaces script on ignition context since MCO is not available on this test infra
func InitInterfacesPreConfigured(c cluster.TestCluster) {
	primaryMac := "52:55:00:d1:56:00"
	secondaryMac := "52:55:00:d1:56:01"

	setupWithInterfacesTest(c, primaryMac, secondaryMac)

	m := c.Machines()[0]
	macConnectionMap, err := getMacConnectionMap(c, m)
	if err != nil {
		c.Fatalf(fmt.Sprintf("failed to get macConnectionMap: %v", err))
	}
	err = checkExpectedInterfacesStatus(c, m, macConnectionMap, []string{primaryMac}, []string{secondaryMac})
	if err != nil {
		c.Fatalf(fmt.Sprintf("interfaces are not in expected status when connections are pre-configured: %v", err))
	}
}

// InitInterfacesNotConfigured checks the scenario where the connections don't exist the script creates them
// The test checks init-interfaces script on ignition context since MCO is not available on this test infra
func InitInterfacesNotConfigured(c cluster.TestCluster) {
	primaryMac := "52:55:00:d1:56:00"
	secondaryMac := "52:55:00:d1:56:01"

	setupWithInterfacesTest(c, primaryMac, secondaryMac)
	m := c.Machines()[0]
	simulateNoConnections(c, m, []string{primaryMac, secondaryMac})

	macConnectionMap, err := getMacConnectionMap(c, m)
	if err != nil {
		c.Fatalf(fmt.Sprintf("failed to get macConnectionMap: %v", err))
	}
	err = checkExpectedInterfacesStatus(c, m, macConnectionMap, []string{primaryMac}, []string{secondaryMac})
	if err != nil {
		c.Fatalf(fmt.Sprintf("interfaces are not in expected status when connections do not exist: %v", err))
	}
}

func simulateNoConnections(c cluster.TestCluster, m platform.Machine, macConnectionsToDelete []string) {
	macConnectionMap, err := getMacConnectionMap(c, m)
	if err != nil {
		c.Fatalf(fmt.Sprintf("failed to get macConnectionMap: %v", err))
	}

	removeConnectionsByMac(c, m, macConnectionMap, macConnectionsToDelete)
	err = m.Reboot()
	if err != nil {
		c.Fatalf("failed to reboot the machine: %v", err)
	}
}

func setupWithInterfacesTest(c cluster.TestCluster, primaryMac, secondaryMac string) {
	interfacesScript, err := getInterfacesScript()
	if err != nil {
		c.Fatalf("failed to read interfaces Script: %v", err)
	}

	captureMacsScript, err := getCaptureMacsScript()
	if err != nil {
		c.Fatalf("failed to read interfaces Script: %v", err)
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
					"path": "/usr/local/bin/init-interfaces.sh",
					"contents": { "source": "data:text/plain;base64,%s" },
					"mode": 755
				}
			]
		},
		"systemd": {
			"units": [
				{
					"contents": "[Unit]\nDescription=Capture MAC address from kargs\nBefore=coreos-installer.target\nAfter=coreos-installer.service\n\nConditionKernelCommandLine=macAddressList\nRequiresMountsFor=/boot\n\n[Service]\nType=oneshot\nMountFlags=slave\nExecStart=/usr/local/bin/capture-macs\n\n[Install]\nRequiredBy=multi-user.target\n",
					"enabled": true,
					"name": "capture-macs.service"
				},
				{
					"contents": "[Unit]\nDescription=Initialize Interfaces\nBefore=kubelet.service\nAfter=NetworkManager.service\nAfter=capture-macs.service\n\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/init-interfaces.sh\n\n[Install]\nRequiredBy=multi-user.target\n",
					"enabled": true,
					"name": "init-interfaces.service"
				}
			]
		}
	}`,
		base64.StdEncoding.EncodeToString([]byte(captureMacsScript)),
		base64.StdEncoding.EncodeToString([]byte(interfacesScript))))

	options := platform.QemuMachineOptions{
		MachineOptions: platform.MachineOptions{
			AdditionalNics: 2,
		},
	}

	var m platform.Machine
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

func getInterfacesScript() (string, error) {
	path := "init-interfaces.sh"

	var data, err = os.ReadFile(path)
	if err != nil {
		return "", err
	}

	return string(data), nil
}

func getCaptureMacsScript() (string, error) {
	path := "capture-macs.sh"

	var data, err = os.ReadFile(path)
	if err != nil {
		return "", err
	}

	return string(data), nil
}

func removeConnectionsByMac(c cluster.TestCluster, m platform.Machine, macConnectionMap map[string]string, macsList[]string) {
	for _, mac := range macsList {
		connectionToDelete := macConnectionMap[mac]
		c.MustSSH(m, fmt.Sprintf("sudo nmcli con del '%s'", connectionToDelete))
	}
}

func checkExpectedInterfacesStatus(c cluster.TestCluster, m platform.Machine, macConnectionMap map[string]string, expectedUpInterfacesMacList, expectedDownInterfacesMacList []string) error {
	failedConnections := []string{}
	for _, ifaceMac := range expectedUpInterfacesMacList {
		connectionName := macConnectionMap[ifaceMac]
		if !isConnectionUp(c, m, connectionName) {
			failedConnections = append(failedConnections, fmt.Sprintf("expected connection %s to be UP", connectionName))
		}
	}

	for _, ifaceMac := range expectedDownInterfacesMacList {
		connectionName := macConnectionMap[ifaceMac]
		if isConnectionUp(c, m, connectionName) {
			failedConnections = append(failedConnections, fmt.Sprintf("expected connection %s to be DOWN", connectionName))
		}
	}

	if len(failedConnections) != 0 {
		return fmt.Errorf(strings.Join(failedConnections, ","))
	}
	return nil
}

func isConnectionUp(c cluster.TestCluster, m platform.Machine, connectionName string) bool {
	if getConnectionStatus(c, m, connectionName) != "activated" {
		return false
	}
	return true
}

func getConnectionStatus(c cluster.TestCluster, m platform.Machine, connectionName string) string {
	return string(c.MustSSH(m, fmt.Sprintf("nmcli -f GENERAL.STATE con show '%s' | awk '{print $2}'", connectionName)))
}

func checkExpectedMACs(c cluster.TestCluster, m platform.Machine, expectedMacsList []string) {
	macConnectionMap, err := getMacConnectionMap(c, m)
	if err != nil {
		c.Fatalf(fmt.Sprintf("failed to get macConnectionMap: %v", err))
	}

	for _, expectedMac := range expectedMacsList {
		if _, exists := macConnectionMap[expectedMac]; !exists {
			c.Fatalf(fmt.Sprintf("expected Mac %s does not appear in macConnectionMap %v", expectedMac, macConnectionMap))
		}
	}
}

func getConnectionDeviceMap(c cluster.TestCluster, m platform.Machine, connectionNamesList []string) (map[string]string, error) {
	connectionDeviceMap := map[string]string{}

	for _, connection := range connectionNamesList {
		deviceName := string(c.MustSSH(m, fmt.Sprintf("nmcli -g connection.interface-name con show '%s'", connection)))
		connectionDeviceMap[connection] = deviceName
	}
	return connectionDeviceMap, nil
}

func getConnectionsList(c cluster.TestCluster, m platform.Machine) []string {
	output := string(c.MustSSH(m, "nmcli -t -f NAME con show"))
	interfaceNames := strings.Split(output, "\n")
	return interfaceNames
}

func getMacConnectionMap(c cluster.TestCluster, m platform.Machine) (map[string]string, error) {
	connectionNamesList := getConnectionsList(c, m)
	connectionDeviceMap, err := getConnectionDeviceMap(c, m, connectionNamesList)
	if err != nil {
		return nil, fmt.Errorf("failed to get connectionDeviceMap: %v", err)
	}

	MacInterfaceMap := map[string]string{}
	for _, connection := range connectionNamesList {
		interfaceMACAddress, err := getDeviceMAC(c, m, connectionDeviceMap[connection])
		if err != nil {
			return nil, fmt.Errorf("failed to fetch connection %s MAC Address: %v", connection, err)
		}
		MacInterfaceMap[interfaceMACAddress] = connection
	}
	return MacInterfaceMap, nil
}

func getDeviceMAC(c cluster.TestCluster, m platform.Machine, deviceName string) (string, error) {
	output := string(c.MustSSH(m, fmt.Sprintf("nmcli -g GENERAL.HWADDR device show '%s'", deviceName)))
	output = strings.Replace(output, "\\:", ":", -1)

	var macAddress net.HardwareAddr
	var err error
	if macAddress, err = net.ParseMAC(output); err != nil {
		return "", fmt.Errorf("failed to parse MAC address %v for device Name %s: %v", output, deviceName, err)
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

func getUserData(c cluster.TestCluster) (string, error) {
	path := "custom-config.ign"

	var data, err = os.ReadFile(path)
	if err != nil {
		return "", err
	}

	return string(data), nil
}

func setupMultipleNetworkTest(c cluster.TestCluster, primaryMac, secondaryMac string) {
	var m platform.Machine
	var err error

	options := platform.QemuMachineOptions{
		MachineOptions: platform.MachineOptions{
			AdditionalNics: 2,
		},
	}

	ignition_config, err := getUserData(c)
	if err != nil {
		c.Fatal(err)
	}

	var userdata *conf.UserData = conf.Ignition(ignition_config)

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
