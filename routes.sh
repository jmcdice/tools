#!/bin/bash
#
# Add routes for my ALU VPN
# Joey <joey.mcdonald@nokia.com>

function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

function get_gw_ip {
   vpn=$(ip route|grep ppp0|head -1|awk '{print $3}')
   echo $vpn
}

function add_routes() {

   vpn=$1

   echo "Using: $vpn as our gateway."

   for route in \
       135.248.18.0/24 172.29.38.0/24 135.248.16.0/24 135.5.27.0/24 \
       135.121.112.0/24 135.121.78.53/32 135.121.37.0/24 135.227.255.0/24 \
       135.1.221.0/24 135.3.129.0/24 135.112.143.0/24 172.29.55.0/24 \
       172.29.36.0/24 135.227.137.0/24 135.104.72.0/24 135.5.27.85/32 \
       135.112.20.0/24 135.1.59.0/24 172.29.50.0/24 135.1.244.0/24 \
       135.111.123.0/24 135.104.67.0/24 135.227.133.0/24 10.5.122.0/24 \
       10.22.90.0/24 138.120.9.0/24 10.135.40.0/24 135.111.192.0/24; do 

    echo -n "Adding $route via $vpn: "
      sudo ip route add $route via $vpn &> /dev/null
      if [ $? != 0 ]; then
          echo "Success"
      else
          echo "Failure"
     fi
    done
}

if [ -z "$vpn" ]; then
    echo "Waiting for the VPN to arrive.."

    for i in {1..30}; do
        vpn=$(get_gw_ip)
        if valid_ip $vpn; then
           break
        fi
    done
    if [ -z "$vpn" ]; then
       echo "Tunnel never came up. Exiting."
       exit 255
    fi
   add_routes $vpn
fi
