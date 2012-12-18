#!/bin/bash

### BEGIN INFO
# Name: Iptables Configuration Script
# Author: Ah-Lun Tang <tang@ahlun.be>
# Provides: iptables configuration for gateway
# Short-Description: iptables script for gateway
### END INFO

#IPTables Location


IPT="/sbin/iptables"
IPTS="/sbin/iptables-save"
IPTR="/sbin/iptables-restore"

# Internet Interface
INET_IFACE="eth0"
INET_ADDRESS="172.23.100.109"

# Local Interface Information
LOCAL_IFACE="eth2"
LOCAL_IP="192.168.1.1"
LOCAL_NET="192.168.1.0/24"
LOCAL_BCAST="192.168.1.255"

# DMZ Interface Information
DMZ_IFACE="eth1"
DMZ_IP="192.168.2.1"
DMZ_NET="192.168.2.0/24"
DMZ_BCAST="192.168.2.255"

# Virtual Private Network interface
VPN_IFACE="tun0"

# Localhost Interface
LO_IFACE="lo"
LO_IP="127.0.0.1"


dropcurrentconfig() {
    # Flush all rules
    $IPT -F
    $IPT -t nat -F
    $IPT -t mangle -F

    # Erase all non-default chains
    $IPT -X
    $IPT -t nat -X
    $IPT -t mangle -X

    # Reset Default Policies
    droppolicy
}

droppolicy(){
    # Reset Default  Drop Policies
    $IPT -P INPUT DROP
    $IPT -P FORWARD DROP
    $IPT -P OUTPUT DROP
    $IPT -t nat -P PREROUTING DROP
    $IPT -t nat -P POSTROUTING DROP
    $IPT -t nat -P OUTPUT DROP
    $IPT -t mangle -P OUTPUT DROP
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

initfirewall(){
    # drop all traffic from/to unknown/invalid connections
    $IPT -A INPUT -m state --state INVALID -j LOG --log-prefix "Invalid input packet: "
    $IPT -A INPUT -m state --state INVALID -j DROP

    $IPT -A FORWARD -m state --state INVALID -j LOG --log-prefix "Invalid forward packet: "
    $IPT -A FORWARD -m state --state INVALID -j DROP

    $IPT -A OUTPUT -m state --state INVALID -j LOG --log-prefix "Invalid output packet: "
    $IPT -A OUTPUT -m state --state INVALID -j DROP
}

initnat(){
    echo 1 > /proc/sys/net/ipv4/ip_forward # Enable routing
    #$IPT -A INPUT -i $INET_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT # accept traffic from the Internet
    $IPT -t nat -A POSTROUTING -o $INET_IFACE -j MASQUERADE # use masquerading
}

initlan(){
    $IPT -A FORWARD -i $INET_IFACE -o $LOCAL_IFACE -j ACCEPT # forward from Internet to LAN
    $IPT -A FORWARD -i $LOCAL_IFACE -o $INET_IFACE -j ACCEPT # forward from LAN to Internet

    $IPT -A INPUT -i $LOCAL_IFACE -j ACCEPT # accept input traffic from LAN
}

initDMZ() {
    $IPT -A FORWARD -i $LOCAL_IFACE -o $DMZ_IFACE -j ACCEPT # forward from LAN to DMZ
    $IPT -A FORWARD -i $DMZ_IFACE -o $LOCAL_IFACE -j ACCEPT # forward from DMZ to LAN
    $IPT -A FORWARD -i $INET_IFACE -o $DMZ_IFACE -j ACCEPT # forward from Internet to DMZ
    $IPT -A FORWARD -i $DMZ_IFACE -o $INET_IFACE -j ACCEPT # forward from DMZ to Internet

    $IPT -A INPUT -i $DMZ_IFACE -j ACCEPT # accept input traffic from DMZ
}


initvpn(){

    # forward between vpn and other interfaces
    $IPT -A FORWARD -i $VPN_IFACE -o $INET_IFACE -j ACCEPT
    $IPT -A FORWARD -i $VPN_IFACE -o $LOCAL_IFACE -j ACCEPT
    $IPT -A FORWARD -i $INET_IFACE -o $VPN_IFACE -j ACCEPT
    $IPT -A FORWARD -i $LOCAL_IFACE -o $VPN_IFACE -j ACCEPT
    $IPT -A FORWARD -i $DMZ_IFACE -o $VPN_IFACE -j ACCEPT
    $IPT -A FORWARD -i $VPN_IFACE -o $DMZ_IFACE -j ACCEPT 

    # accept VPN traffic
    $IPT -A INPUT -i $VPN_IFACE -j ACCEPT
    $IPT -A OUTPUT -o $VPN_IFACE -j ACCEPT

    # Open ports
    $IPT -A INPUT -p tcp -d $INET_ADDRESS --dport 1194 -j ACCEPT
    $IPT -A INPUT -p udp -d $INET_ADDRESS --dport 1194 -j ACCEPT
}

#########
# CUSTOM TRAFFIC

initcustomtraffic(){
    dnstransfers
    sshtraffic
    httptraffic
    ftptraffic
    mailtraffic
    icmptraffic
}

dnstransfers() {
    $IPT -A INPUT -p tcp --dport 53 -j ACCEPT # zone transfers
    $IPT -A INPUT -p udp --dport 53 -j ACCEPT # dns queries

    # Destination NAT
    $IPT -t nat -A PREROUTING -p udp -i $INET_IFACE -d $INET_ADDRESS --dport 53 -j DNAT --to-destination $DMZ_IP:53
    $IPT -t nat -A PREROUTING -p tcp -i $INET_IFACE -d $INET_ADDRESS --dport 53 -j DNAT --to-destination $DMZ_IP:53
}

sshtraffic() {
    $IPT -A INPUT -p tcp --dport 22 -j LOG --log-prefix "Logging Secure Shell: "
    $IPT -A INPUT -p tcp --dport 22 -j ACCEPT

    # Destination NAT
    $IPT -t nat -A PREROUTING -p tcp -i $INET_IFACE -d $INET_ADDRESS --dport 22 -j DNAT --to-destination $DMZ_IP:22
}

httptraffic() {
    #Destination NAT http & https traffic
    $IPT -t nat -A PREROUTING -p tcp -i $INET_IFACE -d $INET_ADDRESS -m multiport --dport 80,443 -j DNAT --to-destination $DMZ_IP
}

ftptraffic(){
    $IPT -t nat -A PREROUTING -p tcp -i $INET_IFACE -d $INET_ADDRESS --dport 21 -j DNAT --to-destination $DMZ_IP:21

    #Passive connection
    $IPT -t nat -A PREROUTING -p tcp -i $INET_IFACE -d $INET_ADDRESS --destination-port 62000:64000 -j ACCEPT
}

mailtraffic() {
    $IPT -t nat -A PREROUTING -p tcp -i $INET_IFACE -d $INET_ADDRESS --dport 25 -j DNAT --to-destination $LOCAL_IP:25
    $IPT -t nat -A PREROUTING -p tcp -i $INET_IFACE -d $INET_ADDRESS --dport 143 -j DNAT --to-destination $LOCAL_IP:143
}

icmptraffic(){
    $IPT -A OUTPUT -p icmp -m state --state NEW,ESTABLISHED,RELATED -j LOG --log-prefix "Logging ICMP output: "
    $IPT -A OUTPUT -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT

    $IPT -A INPUT -p icmp -m state --state NEW,ESTABLISHED,RELATED -j LOG --log-prefix "Logging ICMP input: "
    $IPT -A INPUT -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
}

# END CUSTOM TRAFFIC
#########

case $1 in
    start)
        echo "Setting up fullfeatured gateway ... "
        echo " features: nat, dnat, lan, dmz, vpn, custom "
        echo ""
        dropcurrentconfig && echo " -> IPTable configuration flushed."
        droppolicy && echo " -> IPTable default drop policy."
        initfirewall && echo " -> IPTables initialized."
        initnat && echo " -> Network address translation configured."
        initlan && echo " -> Local LAN ( $LOCAL_NET ) configured."
        initDMZ && echo " -> DMZ network ( $DMZ_NET ) configured."
        initvpn && echo " -> Virtual private networking configured."
        initcustomtraffic && echo " -> Custom traffic initialized."
    ;;
    startlite)
        echo "Setting up gateway ... "
        echo " features: nat, dnat, lan, custom "
        echo ""
        dropcurrentconfig && echo " -> IPTable configuration flushed."
        droppolicy && echo " -> IPTable default drop policy."
        initfirewall && echo " -> IPTables initialized."
        initnat && echo " -> Network address translation configured."
        initlan && echo " -> Local LAN ( $LOCAL_NET ) configured."
        initcustomtraffic && echo " -> Custom traffic initialized."
    ;;
    startdmz)
        echo "Setting up gateway ... "
        echo " features: nat, dnat, lan, dmz, custom "
        echo ""
        dropcurrentconfig && echo " -> IPTable configuration flushed."
        droppolicy && echo " -> IPTable default drop policy."
        initfirewall && echo " -> IPTables initialized."
        initnat && echo " -> Network address translation configured."
        initlan && echo " -> Local LAN ( $LOCAL_NET ) configured."
        initDMZ && echo " -> DMZ network ( $DMZ_NET ) configured."
        initcustomtraffic && echo " -> Custom traffic initialized."
    ;;
    startvpn)
        echo "Setting up gateway ... "
        echo " features: nat, dnat, lan, vpn, custom "
        echo ""
        dropcurrentconfig && echo " -> IPTable configuration flushed."
        droppolicy && echo " -> IPTable default drop policy."
        initfirewall && echo " -> IPTables initialized."
        initnat && echo " -> Network address translation configured."
        initlan && echo " -> Local LAN ( $LOCAL_NET ) configured."
        initDMZ && echo " -> DMZ network ( $DMZ_NET ) configured."
        initcustomtraffic && echo " -> Custom traffic initialized."
    ;;
    stop)
        echo "Drop current gateway configuration..."
        echo ""
        dropcurrentconfig && echo " -> IPTable configuration flushed."
    ;;
    restart)
        $0 stop
        $0 start
    ;;
    *)
        echo "usage: $0 start|startlite|startdmz|startvpn|stop|restart"
        echo ""
        echo " -> start: nat, dnat, lan, dmz, vpn, custom"
        echo " -> startlite: nat, dnat, lan, custom"
        echo " -> startdmz: nat, dnat, lan, dmz, custom"
        echo " -> startvpn: nat, dnat, lan, vpn, custom"
        exit 1
    ;;
esac

exit 0