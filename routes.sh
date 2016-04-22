#!/bin/bash
#
# Add routes for my Nokia VPN
# Add to ~/.bashrc
# alias vpn_routes='bash ~/tools/routes.sh'
#
# Joey <joey.mcdonald@nokia.com>

function get_gw_ip {
   vpn=$(ip route|grep ppp0|head -1|awk '{print $3}')
   echo $vpn
}

function add_routes() {

   vpn=$1

   # Right when tunnel gets setup, we can end up with something funky as
   # our gw. Correct that here.
   if [[ $vpn =~ *ppp* ]]; then
       vpn=$(get_vpn_ip)
   fi

   echo "Using: $vpn as our gateway."
   for route in \
       135.248.18.0/24 172.29.38.0/24 135.248.16.0/24 135.5.27.0/24 \
       135.121.112.0/24 135.121.78.53/32 135.121.37.0/24 135.227.255.0/24 \
       135.1.221.0/24 135.3.129.0/24 135.112.143.0/24 172.29.55.0/24 \
       172.29.36.0/24 135.227.137.0/24 135.104.72.0/24 135.5.27.85/32 \
       135.112.20.0/24 135.1.59.0/24 172.29.50.0/24 135.1.244.0/24 \
       135.111.123.0/24 135.104.67.0/24 10.5.122.0/24; do 

    echo "Adding: $route"
      sudo ip route add $route via $vpn
    done
}

if [ -z "$vpn" ]; then
    echo "Waiting for the VPN to arrive.."

    for i in {1..30}; do
        vpn=$(get_gw_ip)
        if [ -z "$vpn" ]; then
            sleep 3;
        else
            break
        fi
    done
    if [ -z "$vpn" ]; then
       echo "Tunnel never came up. Exiting."
       exit 255
    fi

   # The tunnel is up.
   add_routes $vpn
fi

