#!/bin/bash

### BEGIN INFO
# Name: Iptables Configuration Script
# Author: Ah-Lun Tang <tang@ahlun.be>
# Provides: iptables configuration
### END INFO

#IPTables Location


IPT="/sbin/iptables"
IPTS="/sbin/iptables-save"
IPTR="/sbin/iptables-restore"

# External Router
EXT_INET_IFACE="eth0"
EXT_INET_IP=`ifconfig $EXT_INET_IFACE | grep 'inet addr' | awk '{print $2}' | sed -e 's/.*://'`
EXT_INET_NET="192.168.16.0/24"
EXT_INET_BCAST=`ifconfig $EXT_INET_IFACE | grep 'inet addr' | awk '{print $3}' | sed -e 's/.*://'`

EXT_DMZ_IFACE="eth1"
EXT_DMZ_ADDRESS="192.168.70.254"

# Internal Router
INT_DMZ_IFACE="eth0"
INT_DMZ_IP="192.168.70.250"

INT_LAN_IFACE="eth1"
INT_LAN_IP="10.0.0.254"
INT_LAN_NET="10.0.0.0/24"
INT_LAN_BCAST="10.0.0.255"


# DMZ AND BASTION_HOST
DMZ_NET="192.168.70.0/24"
DMZ_BCAST="192.168.70.255"
DMZ_BASTIONHOST="192.168.70.1"
DMZ_IFACE_EXT="eth1"
DMZ_IFACE_INT="eth0"




# Localhost Interface
LO_IFACE="lo"
LO_IP="127.0.0.1"

#
#
#
# INTERNET             External Router            Bastion Host             Internal Router             Client
#  ------              -------------              ------------              -------------              -------
# |      |------------| eth0 | eth1 |------------|   bridge   |------------| eth0 | eth1 |------------|       |
#  ------              -------------              ------------              -------------              -------
#
# 
dropcurrentconfig() {
    # Flush all rules
    $IPT -F
    $IPT -t nat -F
    $IPT -t mangle -F

    # Erase all non-default chains
    $IPT -X
    $IPT -t nat -X
    $IPT -t mangle -X

}

acceptpolicy(){
    # Reset Default Accept Policies
    $IPT -P INPUT ACCEPT
    $IPT -P FORWARD ACCEPT
    $IPT -P OUTPUT ACCEPT
    $IPT -t nat -P PREROUTING ACCEPT
    $IPT -t nat -P POSTROUTING ACCEPT
    $IPT -t nat -P OUTPUT ACCEPT
    $IPT -t mangle -P OUTPUT ACCEPT
}

droppolicy(){
    # Reset Default Drop Policies
    $IPT -P INPUT DROP
    $IPT -P FORWARD DROP
    $IPT -P OUTPUT DROP
    $IPT -t nat -P PREROUTING DROP
    $IPT -t nat -P POSTROUTING DROP
    $IPT -t nat -P OUTPUT DROP
    $IPT -t mangle -P OUTPUT DROP
}

logging(){
    # drop all traffic from/to unknown/invalid connections
    $IPT -A INPUT -m state --state INVALID -j LOG --log-prefix "Invalid input packet: "
    $IPT -A INPUT -m state --state INVALID -j DROP

    $IPT -A FORWARD -m state --state INVALID -j LOG --log-prefix "Invalid forward packet: "
    $IPT -A FORWARD -m state --state INVALID -j DROP

    $IPT -A OUTPUT -m state --state INVALID -j LOG --log-prefix "Invalid output packet: "
    $IPT -A OUTPUT -m state --state INVALID -j DROP
}


external_router() {
    echo 1 > /proc/sys/net/ipv4/ip_forward # Enable routing

    # Allow internet to access http server in dmz
    $IPT -I FORWARD -i $EXT_INET_IFACE -d $DMZ_NET -p tcp --dport http -j ACCEPT
    $IPT -I FORWARD -s $DMZ_NET -o $EXT_INET_IFACE -p tcp --sport http -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    # Allow internet to access dns server in dmz
    $IPT -I FORWARD -i $EXT_INET_IFACE -d $DMZ_NET -p udp --dport dns -j ACCEPT
    $IPT -I FORWARD -s $DMZ_NET -o $EXT_INET_IFACE -p udp --sport dns -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    # Allow internet to access smtp server in dmz
    $IPT -I FORWARD -i $EXT_INET_IFACE -d $DMZ_NET -p tcp --dport 25 -j ACCEPT
    $IPT -I FORWARD -s $DMZ_NET -o $EXT_INET_IFACE -p tcp --sport 25 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    # Allow bastion host to access ssh server from internet
    $IPT -I FORWARD -s $DMZ_BASTIONHOST -o $EXT_INET_IFACE -p tcp --dport 22 -j ACCEPT
    $IPT -I FORWARD -s $DMZ_BASTIONHOST -o $EXT_INET_IFACE -p tcp --dport 22 -j LOG --log-prefix "Secure Shell: "
    $IPT -I FORWARD -i $EXT_INET_IFACE -d $DMZ_BASTIONHOST -p tcp --sport 22 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    
    # Allow bastion host to access http server from internet
    $IPT -I FORWARD -s $DMZ_BASTIONHOST -o $EXT_INET_IFACE -p tcp --dport http -j ACCEPT
    $IPT -I FORWARD -i $EXT_INET_IFACE -d $DMZ_BASTIONHOST -p tcp --sport http -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    
    # Allow bastion host to access dns server from internet
    $IPT -I FORWARD -s $DMZ_BASTIONHOST -o $EXT_INET_IFACE -p udp --dport dns -j ACCEPT
    $IPT -I FORWARD -i $EXT_INET_IFACE -d $DMZ_BASTIONHOST -p udp --sport dns -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    # Allow bastion host to access mail server from internet
    $IPT -I FORWARD -s $DMZ_BASTIONHOST -o $EXT_INET_IFACE -p tcp --dport 25 -j ACCEPT
    $IPT -I FORWARD -i $EXT_INET_IFACE -d $DMZ_BASTIONHOST -p tcp --sport 25 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
}

internal_router(){
    echo 1 > /proc/sys/net/ipv4/ip_forward # Enable routing

    # use masquerading
    $IPT -t nat -A POSTROUTING -o $INT_DMZ_IFACE -s $INT_LAN_NET -d 0/0 -j MASQUERADE

    # Prior to masquerading, the packets are routed via the filter table's FORWARD chain.
    # Allow http(s),mail and ssh traffic to DMZ
    $IPT -I FORWARD -t filter -o $INT_DMZ_IFACE  -p tcp -m multiport --dports 80,443,25,22 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
    $IPT -I FORWARD -t filter -i $INT_DMZ_IFACE  -p tcp -m multiport --sports 80,443,25,22 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # Allow dns traffic to DMZ
    $IPT -I FORWARD -t filter -o $INT_DMZ_IFACE  -p udp --dport 53 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
    $IPT -I FORWARD -t filter -i $INT_DMZ_IFACE  -p udp --dport 53 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Allow ping to DMZ
    $IPT -I FORWARD -t filter -d $DMZ_NET -p icmp icmp-type echo-request -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
    $IPT -I FORWARD -t filter -s $DMZ_NET -i $INT_DMZ_IFACE  -p icmp icmp-type echo-reply -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT


    # http(s), mail and ssh to bastion host
    #$IPT -t nat -I PREROUTING -p tcp -i $DMZ_BASTIONHOST -d $INT_LAN_NET -m multiport --dports 80,443,25,22 -j DNAT --to-destination $INT_LAN_NET


    #$IPT -t nat -I PREROUTING -p udp -i $DMZ_BASTIONHOST -d $INT_LAN_NET  --dport 53 -j DNAT --to-destination $INT_LAN_NET

    # ping to dmz
    #$IPT -t nat -I PREROUTING -p tcp -i $DMZ_NET -d $INT_LAN_NET -m multiport --dports 80,443,25,22 -j DNAT --to-destination $INT_LAN_NET

}

init_bridge(){
    ifconfig $DMZ_IFACE_EXT 0.0.0.0 up
    ifconfig $DMZ_IFACE_INT 0.0.0.0 up
    brctl addbr br0
    brctl stp br0 on # prevent switching loops
    brctl addif br0 $DMZ_IFACE_EXT
    brctl addif br0 $DMZ_IFACE_INT
    ifconfig br0 $DMZ_BASTIONHOST up
}

case $1 in
    external)
        echo "Setting up iptables for external router ... "
        dropcurrentconfig   &&  echo " -> IPTable configuration flushed."
        droppolicy          &&  echo " -> IPTable default drop policy."
        external_router     &&  echo " -> Setting up external router."
    ;;
    internal)
        echo "Setting up iptables for internal router ... "
        dropcurrentconfig   &&  echo " -> IPTable configuration flushed."
        droppolicy          &&  echo " -> IPTable default drop policy."
        internal_router     &&  echo " -> Setting up internal router."
    ;;
    bastion)
        echo "Setting up bridge for bastion host ... "
        init_bridge         &&  echo " -> Setting up internal router."
    ;;
    flush)
        echo "Drop current configuration..."
        dropcurrentconfig   &&  echo " -> IPTable configuration flushed."
    ;;
    restart)
        $0 flush
    ;;
    *)
        echo "usage: $0 external|internal|bastion|flush"
        exit 1
    ;;
esac

exit 0