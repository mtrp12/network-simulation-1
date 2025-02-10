#!/bin/bash

create_namespace() {
    sudo ip netns add "$1" && echo "Namespace $1 created successfully" || { echo "Failed to create namespace $1"; cleanup; }
}

create_bridge() {
    sudo ip link add "$1" type bridge && echo "Bridge $1 created successfully" || { echo "Failed to create bridge $1"; cleanup; }
    sudo ip link set "$1" up || { echo "Failed to bring UP bridge $1"; cleanup; }
}

create_veth_pair() {
    sudo ip link add "$1" type veth peer name "$2" && echo "Veth pair $1-$2 created successfully" || { echo "Failed to create veth pair $1-$2"; cleanup; }
}

set_veth_to_ns() {
    sudo ip link set "$1" netns "$2" && echo "$1 assigned to namespace $2" || { echo "Failed to set $1 to $2"; cleanup; }
    sudo ip netns exec "$2" ip link set "$1" up && echo "$1 brought up inside $2" || { echo "Failed bring UP veth $1 inside $2"; cleanup; }
}

set_veth_to_bridge() {
    sudo ip link set "$1" master "$2" && echo "$1 connected to bridge $2" || { echo "Failed to set $1 to $2"; cleanup; }
    sudo ip link set "$1" up || { echo "Failed bring UP veth $1"; cleanup; }
}

setup_ip() {
    sudo ip netns exec "$1" ip addr add "$2" dev "$3" && echo "IP $2 assigned to $3 in $1" || { echo "Failed to assign IP $2 to $3 in $1"; cleanup; }
}

setup_route() {
    sudo ip netns exec "$1" ip route add default via "$2" && echo "Default route set in $1 via $2" || { echo "Failed to set default route in $1"; cleanup; }
}

enable_forwarding() {
    sudo ip netns exec router-ns sysctl -w net.ipv4.ip_forward=1
	echo "Enabled IPv4 forwarding inside router-ns"
	sudo iptables --append FORWARD --in-interface br0 --jump ACCEPT
	sudo iptables --append FORWARD --out-interface br0 --jump ACCEPT
	echo "Enabled forwarding for br0"
	sudo iptables --append FORWARD --in-interface br1 --jump ACCEPT
	sudo iptables --append FORWARD --out-interface br1 --jump ACCEPT
	echo "Enabled forwarding for br1"
}

ping_test() {
    echo "Testing connectivity between namespaces..."
    echo "Pinging ns2 from ns1..."
    sudo ip netns exec ns1 ping -c 1 192.168.2.2 | grep -i ttl || { echo "ns1 to ns2 connectivity failed"; }

    echo "Pinging router-ns from ns1..."
    sudo ip netns exec ns1 ping -c 1 192.168.1.1 | grep -i ttl || { echo "ns1 to router-ns connectivity failed"; }

    echo "Pinging ns1 from ns2..."
    sudo ip netns exec ns2 ping -c 1 192.168.1.2 | grep -i ttl || { echo "ns2 to ns1 connectivity failed"; }

    echo "Pinging router-ns from ns2..."
    sudo ip netns exec ns2 ping -c 1 192.168.2.1 | grep -i ttl || { echo "ns2 to router-ns connectivity failed"; }

    echo "Pinging ns1 from router-ns..."
    sudo ip netns exec router-ns ping -c 1 192.168.1.2 | grep -i ttl || { echo "router-ns to ns1 connectivity failed"; }

    echo "Pinging ns2 from router-ns..."
    sudo ip netns exec router-ns ping -c 1 192.168.2.2 | grep -i ttl || { echo "router-ns to ns2 connectivity failed"; }
}

finish_script() {
	echo
	echo "----Script Finished----"
	exit 0
}

complete_message() {
	echo "Network setup complete!"
	echo
	echo "--- Final Network Configuration ---  "
	echo "   +--------------------------+      "
	echo "   |         router-ns        |      "
	echo "   | 192.168.1.1  192.168.2.1 |      "
	echo "   +-------------+------------+      "
	echo "                 |                   "
	echo "    +------------+----------+        "
	echo "    |                       |        "
	echo "+---+---+               +---+---+    "
	echo "| br0   |               | br1   |    "
	echo "|FORWARD|               |FORWARD|    "
	echo "+---+---+               +---+---+    "
	echo "    |                       |        "
	echo "    |                       |        "
	echo "+---+---------+       +-----+-------+"
	echo "|     ns1     |       |     ns2     |"
	echo "| 192.168.1.2 |       | 192.168.2.2 |"
	echo "+-------------+       +-------------+"
}

cleanup() {
    echo "Cleaning up network setup..."
    sudo ip netns del ns1 &> /dev/null
	sudo ip netns del ns2 &> /dev/null
	sudo ip netns del router-ns &> /dev/null
	echo "Namespaces deleted..."

	sudo ip link del br0 &> /dev/null
	sudo ip link del br1 &> /dev/null
	echo "Bridges deleted..."

	sudo ip link del veth0 &> /dev/null
	sudo ip link del veth1 &> /dev/null
	sudo ip link del veth2 &> /dev/null
	sudo ip link del veth3 &> /dev/null
	sudo ip link del veth4 &> /dev/null
	sudo ip link del veth5 &> /dev/null
	sudo ip link del veth6 &> /dev/null
	sudo ip link del veth7 &> /dev/null
	echo "Virtual interfaces deleted..."
	
	sudo iptables -D FORWARD --in-interface br0 --jump ACCEPT &> /dev/null
	sudo iptables -D FORWARD --out-interface br0 --jump ACCEPT &> /dev/null
	sudo iptables -D FORWARD --in-interface br1 --jump ACCEPT &> /dev/null
	sudo iptables -D FORWARD --out-interface br1 --jump ACCEPT &> /dev/null
	echo "iptables rules deleted..."
	
	finish_script
}

# gracefully handle termination signals
trap cleanup SIGINT SIGTERM

if [[ "$1" == "clean" ]]; then
	cleanup
fi

echo "Creating network namespaces..."
create_namespace ns1
create_namespace ns2
create_namespace router-ns

echo "Creating bridges..."
create_bridge br0
create_bridge br1

echo "Creating veth pairs..."
create_veth_pair veth0 veth1
create_veth_pair veth2 veth3
create_veth_pair veth4 veth5
create_veth_pair veth6 veth7

echo "Connecting veth interfaces to namespaces and bridges..."
set_veth_to_ns veth0 ns1
set_veth_to_bridge veth1 br0
set_veth_to_bridge veth2 br0
set_veth_to_ns veth3 router-ns
set_veth_to_ns veth4 router-ns
set_veth_to_bridge veth5 br1
set_veth_to_bridge veth6 br1
set_veth_to_ns veth7 ns2

echo "Bringing up loopback interfaces..."
sudo ip netns exec ns1 ip link set lo up
sudo ip netns exec ns2 ip link set lo up
sudo ip netns exec router-ns ip link set lo up

echo "Assigning IP addresses..."
setup_ip ns1 192.168.1.2/24 veth0
setup_ip router-ns 192.168.1.1/24 veth3
setup_ip router-ns 192.168.2.1/24 veth4
setup_ip ns2 192.168.2.2/24 veth7

echo "Setting up routing..."
setup_route ns1 192.168.1.1
setup_route ns2 192.168.2.1

echo "Enabling forwarding..."
enable_forwarding

complete_message

echo "Running connectivity tests..."
ping_test

finish_script