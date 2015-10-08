#!/usr/bin/sh
# Run me from a rocks frontend.
# Joey <joseph.mcdonald@alcatel-lucent.com>

source /root/keystonerc_admin

function create_sec_group() {

   echo -n "Creating a security group: "
   # Create the smssh group
   neutron security-group-create smssh &> /dev/null
   neutron security-group-rule-create --direction ingress --ethertype IPv4 --protocol tcp --port-range-min 22 --port-range-max 22 smssh &> /dev/null
   neutron security-group-rule-create --direction ingress --ethertype IPv4 --protocol icmp smssh &> /dev/null
   neutron security-group-list | grep -q smssh
   check_exit_code
}

function create_networks() {

   echo -n "Creating test network: "
   neutron net-create smnet1 --provider:network_type vlan --provider:physical_network RegionOne --provider:segmentation_id 600 &> /dev/null
   neutron subnet-create smnet1 10.10.10.0/24 --name subnet1 &> /dev/null

   neutron net-list | grep -q smnet1
   check_exit_code
}

function setup_pinning() {

   # Adjust this for your needs (pre-existing zones, etc)
   # To discover your numa zones, login to a compute and run:
   # yum -y install numactl && numactl -s
   nova aggregate-create aggregate0 zone0
   nova aggregate-add-host aggregate0 compute-0-0.local

   # Adjust the flavor creation for your VNF.
   # nova flavor-create m1_1.small.cpu.pin <id> <memory> <disk size> <cpu count>
   nova flavor-create m1_1.small.cpu.pin 11 10240 30 4
   nova flavor-key m1_1.small.cpu.pin set cpu:cpuset=2,3,4,5
   nova flavor-key m1_1.small.cpu.pin set "aggregate_instance_extra_specs:pinned"="true"
}

function boot_vm() {

   nova boot smoketest-zone0 \
     --image $(nova image-list|grep redhat7-v |awk '{print $2}') \
     --flavor $(nova flavor-list | grep m1_1.small.cpu.pin |  awk '{print $2}') \
     --nic net-id=$(neutron net-list | grep -i smnet1 | awk '{print $2}') \
     --security_groups smssh \
     --availability-zone zone0
}

function check_exit_code() {

   if [ $? -ne 0 ]; then
      echo "Failed"
      echo "Running clean up"
      clean_up
      exit 255
   fi
   echo "Success"
}

function clean_up() {

   for uuid in `nova list |grep smoketest |awk '{print $2}'`
   do 
      nova delete $uuid
   done

   sleep 5

   for port in `neutron port-list|grep smsriovport|awk '{print $2}'`
   do 
      neutron port-delete $port
   done

   for net in `neutron net-list|grep smnet|awk '{print $2}'`
   do
      neutron net-delete $net
   done

   for uuid in `nova secgroup-list | grep smssh|awk '{print $2}'`
   do
      nova secgroup-delete $uuid &> /dev/null
   done
}

# You'll have to clean up the nova flavors manually (didn't want to step on existing flavors).
#clean_up
setup_pinning
create_sec_group
create_networks
boot_vm

