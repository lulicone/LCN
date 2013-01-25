#!/bin/bash

#note: External IP might not be necessary. I leave that question as an exercise to the reader :-)
EXTERNAL_INT="eth0"		    # External Internet interface
INTERNAL_INT="eth1"	       	    # Internal nic
EXTERNAL_IP="`ifconfig $EXTERNAL_INT | grep 'inet addr' | awk '{print $2}' | sed -e 's/.*://'`"    # Internet Interface IP address
PPTP_INT="ppp10" # pptp used to connect *to* server using VPN

# logging parametres
LOGLIMIT="2/s"
LOGLIMITBURST="10"

#open ports in server. 
# PKSERVICES opens only (for 7200 secs) after correct ports have been knocked in order
# ssh port 22 is already protected by port knocking and should not be in PKSERVICES
# max 15 ports can be configured at the same time
PKSERVICES="21"
# Ports that should always be open
TCPSERVICES="80,55000:55010"
UDPSERVICES="80,8080,55000:55010"


#---------------------------------------------------------------
# Functions
#---------------------------------------------------------------

function port_forward() {
ip=$1
dest_port=$2
proto=$3

iptables -t nat -A PREROUTING -p $proto -i $EXTERNAL_INT -d $EXTERNAL_IP --dport $dest_port --sport 1024:65535 -j DNAT --to $ip:$dest_port
iptables -A FORWARD -p $proto -i $EXTERNAL_INT -o $INTERNAL_INT -d $ip --dport $dest_port --sport 1024:65535 -m state --state NEW -j ACCEPT

}

#---------------------------------------------------------------
# Flush all current rules
#---------------------------------------------------------------
iptables --flush
iptables --flush -t nat
iptables --flush -t mangle
iptables -X 
 
#---------------------------------------------------------------
# Initialize user-defined chains
# content is added further down
#---------------------------------------------------------------
iptables -N valid-src
iptables -N valid-dst
iptables -N logdrop 
iptables -N ssh_login
iptables -N restr_addr
iptables -N nastypackets
iptables -N check_icmp
iptables -N in-phase2

#---------------------------------------------------------------
# NAT, FORWARD, PORT FORWARD chain
#---------------------------------------------------------------
# sanity check
iptables -A FORWARD -o $EXTERNAL_INT -j valid-dst
iptables -A FORWARD -i $EXTERNAL_INT -j valid-src

# Check for restricted ip addresses
iptables -A FORWARD -j restr_addr

# port forward (function above)
port_forward 192.168.0.150 45631 tcp
port_forward 192.168.0.5 64738 udp

# Give access to Internet for internal machines
iptables -A POSTROUTING -s 192.168.0.0/24 -o $EXTERNAL_INT -j MASQUERADE -t nat

# Give access to new outgoing and rel/est incoming
iptables -A FORWARD -o $EXTERNAL_INT -m state --state NEW,RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $EXTERNAL_INT -m state --state RELATED,ESTABLISHED -j ACCEPT

# Reject the rest. Must be last rule. Before dropping, log it. 
# Note: logs are written to /var/log/messages and tends to fill up log quite quickly
# I disable log row in normal operation and use it only when needed
iptables -A FORWARD -m limit --limit $LOGLIMIT --limit-burst $LOGLIMITBURST -j LOG --log-prefix "NAT:  "
iptables -A FORWARD -j REJECT --reject-with icmp-host-prohibited

#---------------------------------------------------------------
# OUTPUT chain
#---------------------------------------------------------------
# Sanity checks 
iptables -A OUTPUT  -o $EXTERNAL_INT -j valid-dst

# Check for restricted ip addresses. Drop if in list 
iptables -A OUTPUT -j restr_addr

#---------------------------------------------------------------
# INPUT chain
#---------------------------------------------------------------
# Verify valid source addresses for all packets
iptables -A INPUT   -i $EXTERNAL_INT -j valid-src

# Accept everything coming from internal interface (in correct subnet) and localhost
iptables -A INPUT -p all -s 192.168.0.0/24 -i $INTERNAL_INT -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

# get rid of nasty packets (see below for details)
iptables -A INPUT -j nastypackets

# Check for restricted ip addresses. Drop if in list
iptables -A INPUT -j restr_addr

# Accept already established connections, i.e. setup from server
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# Accept ICMP
iptables -A INPUT -p icmp -j check_icmp

# port knocking. To reach ports protected by p.k. one needs to call port 12345, then 54321, then port within 300sec (2h for all but ssh)
# ports are configured above. Note: part of p.k. functionality is placed further down for reasons I cant remember.
iptables -A INPUT -m recent --update --name PHASE1
iptables -A INPUT -p tcp --dport 12345 -m recent --set --name PHASE1
iptables -A INPUT -p tcp --dport 54321 -m recent --rcheck --name PHASE1 -j in-phase2
iptables -A INPUT -p tcp -m multiport --dport $PKSERVICES -m recent --rcheck --seconds 7200 --name PHASE2 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -m recent --rcheck --seconds 300 --name PHASE2 -j ssh_login

# open ports on server. Ports are configured above
iptables -A INPUT -p tcp -i $EXTERNAL_INT -m multiport --sport 1024:65535 -m multiport --dport $TCPSERVICES  -m state --state NEW -j ACCEPT
iptables -A INPUT -p udp -i $EXTERNAL_INT -m multiport --sport 1024:65535 -m multiport --dport $UDPSERVICES  -m state --state NEW -j ACCEPT

# ftp. This has not been tested as I no longer use ftp 
# iptables -A INPUT -p tcp --sport 20 -m state --state ESTABLISHED,RELATED -j ACCEPT
# iptables -A OUTPUT -p tcp --dport 20 -m state --state ESTABLISHED -j ACCEPT
# iptables -A INPUT -p tcp --sport 1024: --dport 1024:  -m state --state ESTABLISHED -j ACCEPT
# iptables -A OUTPUT -p tcp --sport 1024: --dport 1024:  -m state --state ESTABLISHED,RELATED -j ACCEPT

# DROP the rest. Must be last rule. 
# First log. Note again about logging filling up the logs...
iptables -A INPUT -m limit --limit $LOGLIMIT --limit-burst $LOGLIMITBURST -j LOG --log-prefix "INPUT: "
iptables -A INPUT -j DROP



#**************************************************************
#USER DEFINED RULES FROM NOW ON
#**************************************************************

#---------------------------------------------------------------
# Restricted addresses. Make sure to use -s or -d depending on what to restrict
#---------------------------------------------------------------
# Chinese hacker
iptables -A restr_addr -s 211.148.164.133 -j DROP
iptables -A restr_addr -s 220.227.15.141 -j DROP
iptables -A restr_addr -s 219.143.125.205 -j DROP


#---------------------------------------------------------------
# logdrop chain: Logs and drops
#---------------------------------------------------------------
iptables -A logdrop -m limit --limit $LOGLIMIT --limit-burst $LOGLIMITBURST -j LOG --log-prefix "logdrop: "
iptables -A logdrop -j DROP

#---------------------------------------------------------------
# ssh_login chain: Silently drop more than 3 login attemps within
# 60 seconds for 60 seconds. Accept otherwise 
#---------------------------------------------------------------
iptables -A ssh_login -m recent --set --name SSH
iptables -A ssh_login -m recent --update --seconds 60 --hitcount 4 --name SSH -j DROP
iptables -A ssh_login -p tcp -i $EXTERNAL_INT --dport 22 --sport 1024:65535 -m state --state NEW -j ACCEPT

#---------------------------------------------------------------
#
# Source and Destination Address Sanity Checks
#
# Drop packets from networks covered in RFC 1918 (private nets)
# Drop packets from external interface IP
#
#---------------------------------------------------------------
 
iptables -A valid-src -s 10.0.0.0/8     -j DROP
iptables -A valid-src -s 172.16.0.0/12  -j DROP
iptables -A valid-src -s 192.168.0.0/16 -j DROP
iptables -A valid-src -s 224.0.0.0/4    -j DROP
iptables -A valid-src -s 240.0.0.0/5    -j DROP
iptables -A valid-src -s 127.0.0.0/8    -j DROP
iptables -A valid-src -s 0.0.0.0/8       -j DROP
iptables -A valid-src -d 255.255.255.255 -j DROP
iptables -A valid-src -s 169.254.0.0/16  -j DROP
iptables -A valid-src -s $EXTERNAL_IP    -j DROP
iptables -A valid-dst -d 224.0.0.0/4    -j DROP


#---------------------------------------------------------------
# Drop those nasty packets! These are all TCP flag 
# coMbinations that should never, ever occur in the
# wild. All of these are illegal combinations that 
# are used to attack a box in various ways, so we 
# just drop them.
#---------------------------------------------------------------
iptables -A nastypackets -p tcp --tcp-flags ALL FIN,URG,PSH -j DROP
iptables -A nastypackets -p tcp --tcp-flags ALL ALL -j DROP
iptables -A nastypackets -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP
iptables -A nastypackets -p tcp --tcp-flags ALL NONE -j DROP
iptables -A nastypackets -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
iptables -A nastypackets -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP

#---------------------------------------------------------------
# take care of ICMP
#---------------------------------------------------------------
# Drop icmp, but only after letting certain types through, e.g. ping
iptables -A check_icmp -p icmp --icmp-type 0 -j ACCEPT
iptables -A check_icmp -p icmp --icmp-type 3 -j ACCEPT
iptables -A check_icmp -p icmp --icmp-type 11 -j ACCEPT
iptables -A check_icmp -p icmp --icmp-type 8 -m limit --limit 1/second -j ACCEPT
iptables -A check_icmp -p icmp -j DROP


#---------------------------------------------------------------
# Port knocking
#---------------------------------------------------------------

iptables -A in-phase2 -m recent --name PHASE1 --remove
iptables -A in-phase2 -m recent --name PHASE2 --set
iptables -A in-phase2 -j LOG --log-prefix "INTO PHASE2: "

echo "Done. check your config with e.g. iptables -L -n -v"
echo "Dont forget to save your configuration: service iptables save 
echo "(if on Red Hat like OS. If you are using some other junk, you are on your own :-)"
