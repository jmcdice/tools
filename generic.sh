#!/bin/bash
# 

start() {
   function install_cirros() {

      # This requires internet access.
      echo "Installing cirros VM template."
      glance image-create --name cirros --is-public=true --container-format=bare --disk-format=qcow2 \
         --copy-from http://cdn.download.cirros-cloud.net/0.3.1/cirros-0.3.1-x86_64-disk.img

      # Loop untili it's ready.
      while true; do
        nova image-list | grep cirros | grep ACTIVE
        RET=$?
        if [ $RET -eq 0 ]; then
           break
        fi
        sleep 5
      done
   }

   # See if we have our template. Install it if we don't.
   nova image-list | grep -q cirros || install_cirros

   # Here, we discover the 'public' network and build a subnet pool (limited as some are in use).
   net=$(ifconfig eth1 | perl -lane 'print $1 if /addr:(.*?)\s/' | cut -d'.' -f1-3);
   start="$net.100"
   end="$net.250"
   gateway=$(netstat -r|grep default|awk '{print $2}')
   mask=$(ifconfig eth1|perl -lane 'print $1 if /Mask:(.*?)$/')
   prefix=$(/bin/ipcalc -p $start $mask | awk -F\= '{print $2}')

   # Create our pool of floaters and subnets
   neutron net-create public-net --provider:network_type flat --provider:physical_network RegionOne --router:external=True
   #neutron net-create public-net --router:external=True
   neutron subnet-create --name public-subnet --allocation-pool start=$start,end=$end --gateway $gateway public-net $net.0/24 --dns_nameservers list=true 8.8.8.8
   neutron net-create management
   neutron subnet-create --name management-subnet management 172.40.0.0/24 --dns_nameservers list=true 8.8.8.7 8.8.8.8
   neutron net-create switchfabric
   neutron subnet-create --name switchfabric-subnet --no-gateway --enable_dhcp=false switchfabric 0.0.0.0/24
   neutron net-create s11
   neutron subnet-create --name s11-subnet s11 20.20.7.0/24
   neutron net-create s5
   neutron subnet-create --name s5-subnet s5 20.20.5.0/24
   neutron router-create noderouter
   neutron router-interface-add noderouter management-subnet
   neutron router-gateway-set noderouter public-net

   # Add a security group
   neutron security-group-create ssh
   neutron security-group-rule-create --direction ingress --ethertype IPv4 --protocol tcp --port-range-min 22 --port-range-max 22 ssh
   neutron security-group-rule-create --direction ingress --ethertype IPv4 --protocol icmp ssh

   # Add an ssh key
   ssh-keygen -N '' -f ~/.ssh/epc_id_rsa
   nova keypair-add --pub-key ~/.ssh/epc_id_rsa.pub epc-key

   # Management VM
   nova boot --image $(nova image-list | grep cirros | awk '{print $2}') --flavor default \
   --nic net-id=$(neutron net-list | grep public | awk '{print $2}')  \
   --nic net-id=$(neutron net-list | grep management | awk '{print $2}')  \
   --key_name epc-key --security_groups ssh epc-management

   # LTE CPM VM
   neutron port-create --fixed-ip subnet_id=$(neutron net-list | grep management | awk '{print $6}'),ip_address=172.40.0.35 management
   nova boot --image $(nova image-list | grep cirros | awk '{print $2}') --flavor default \
     --nic port-id=$(neutron port-list | grep 172.40.0.35 | awk '{print $2}') \
     --nic net-id=$(neutron net-list | grep switchfabric | awk '{print $2}')  \
     epc-cpm-1

   # LTE IOM VM
   neutron port-create --fixed-ip subnet_id=$(neutron net-list | grep management | awk '{print $6}'),ip_address=172.40.0.40 management
   neutron port-create --mac-address 00:28:02:02:00:01 --fixed-ip subnet_id=$(neutron net-list | grep s11 | awk '{print $6}'),ip_address=20.20.7.1 s11
   neutron port-create --mac-address 00:28:02:02:00:02 --fixed-ip subnet_id=$(neutron net-list | grep s5 | awk '{print $6}'),ip_address=20.20.5.1 s5

   nova boot --image $(nova image-list | grep cirros | awk '{print $2}') --flavor default \
      --nic port-id=$(neutron port-list | grep 172.40.0.40 | awk '{print $2}') \
      --nic net-id=$(neutron net-list | grep switchfabric | awk '{print $2}')  \
      --nic port-id=$(neutron port-list | grep 20.20.7.1  | awk '{print $2}') \
      --nic port-id=$(neutron port-list | grep 20.20.5.1  | awk '{print $2}') \
      epc-iom-1

   # SIM-MME
   neutron port-create --fixed-ip subnet_id=$(neutron net-list | grep s11 | awk '{print $6}'),ip_address=20.20.7.203 s11
   nova boot --image $(nova image-list | grep cirros | awk '{print $2}') --flavor default \
      --nic net-id=$(neutron net-list | grep management | awk '{print $2}')  \
      --nic port-id=$(neutron port-list | grep 20.20.7.203| awk '{print $2}') \
      --key_name epc-key --security_groups ssh sim-mme

   # SIM-PGW
   neutron port-create --fixed-ip subnet_id=$(neutron net-list | grep s5 | awk '{print $6}'),ip_address=20.20.5.203 s5
   nova boot --image $(nova image-list | grep cirros | awk '{print $2}') --flavor default \
      --nic net-id=$(neutron net-list | grep management | awk '{print $2}')  \
      --nic port-id=$(neutron port-list | grep 20.20.5.203| awk '{print $2}') \
      --key_name epc-key --security_groups ssh sim-pgw

   ifconfig eth1 | perl -lane 'print "\n\n\tPlease check: https://$1/dashboard/project/network_topology/\n" if (/inet addr:(.*?)\s/)'

   sleep 20
   nova list
}

stop() {

   function purge_port() {
       for port in `neutron port-list -c id | egrep -v '\-\-|id' | awk '{print $2}'`
       do
           neutron port-delete ${port}
       done
   }

   function purge_router() {
       for router in `neutron router-list -c id | egrep -v '\-\-|id' | awk '{print $2}'`
       do
           for subnet in `neutron router-port-list ${router} -c fixed_ips -f csv | egrep -o '[0-9a-z\-]{36}'`
           do
               neutron router-interface-delete ${router} ${subnet} &> /dev/null
           done
           neutron router-gateway-clear ${router}
           neutron router-delete ${router}
       done
   }

   function purge_subnet() {
       for subnet in `neutron subnet-list -c id | egrep -v '\-\-|id' | awk '{print $2}'`
       do
           neutron subnet-delete ${subnet}
       done
   }

   function purge_net() {
       for net in `neutron net-list -c id | egrep -v '\-\-|id' | awk '{print $2}'`
       do
           neutron net-delete ${net}
       done
   }

   function purge_secgroup() {
       for secgroup in `nova secgroup-list|grep ssh|awk '{print $2}'`
       do
           neutron security-group-delete ${secgroup}
       done
   }

   function purge_floaters() {
      for floater in `neutron floatingip-list -c id | egrep -v '\-\-|id' | egrep -o '[0-9a-z\-]{36}'`
         do
            neutron floatingip-delete ${floater}
         done
   }

   function purge_instances() {
      for inst in `nova list | egrep -o '[0-9a-z\-]{36}' | egrep -v '\-\-|id'`
         do
            echo "Deleting Instance: ${inst}"
            nova delete ${inst}
         done
   }

   # Stop Instances
   purge_instances
   purge_floaters
   purge_router
   purge_port
   purge_subnet
   purge_net
   purge_secgroup

   # Delete keys
   nova keypair-delete epc-key
   rm -rf ~/.ssh/epc*
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    *)
        echo $"Usage: $0 {start|stop}"
        RETVAL=3
esac


