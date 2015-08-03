#!/usr/bin/sh
# Check a bunch of common openstack stuff in one place, post-install and tell the installer
# how it all looks.

# Pull in admin credentials
source /root/keystonerc_admin

is_sriov='false'

function verify_creds() {

   # Test to check for admin creds.
   echo -n "Verifying admin credentials: "
   env | grep -q OS_AUTH_URL
   check_exit_code
}

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

   echo -n "Creating test networks: "
   neutron net-create smnet1 &> /dev/null
   neutron subnet-create smnet1 10.10.10.0/24 --name subnet1 &> /dev/null
   neutron net-create smnet2 &> /dev/null
   neutron subnet-create smnet2 20.10.10.0/24 --name subnet2 &> /dev/null
   neutron net-create smnet3 &> /dev/null
   neutron subnet-create smnet3 30.10.10.0/24 --name subnet3 &> /dev/null

   neutron net-list | grep -q smnet1
   check_exit_code
}

function boot_vm() {
   zone=$1

   nova boot smoketest-$zone \
     --image $(nova image-list|grep redhat7-v |awk '{print $2}') \
     --flavor $(nova flavor-list | grep default |  awk '{print $2}') \
     --nic net-id=$(neutron net-list | grep smnet1 | awk '{print $2}') \
     --nic net-id=$(neutron net-list | grep smnet2 | awk '{print $2}') \
     --nic net-id=$(neutron net-list | grep smnet3 | awk '{print $2}') \
     --security_groups smssh \
     --availability-zone $zone  &>> /tmp/nova_boot.log
}

function boot_vm_sriov() {
   zone=$1

   # create ports for sriov
   neutron port-create $(neutron net-list | grep smnet1 | awk '{print $2}') \
     --name smsriovport1-$zone \
     --binding:vnic-type direct &>> /tmp/nuetron_port.log
   neutron port-create $(neutron net-list | grep smnet2 | awk '{print $2}') \
     --name smsriovport2-$zone \
     --binding:vnic-type direct &>> /tmp/nuetron_port.log
   neutron port-create $(neutron net-list | grep smnet3 | awk '{print $2}') \
     --name smsriovport3-$zone \
     --binding:vnic-type direct &>> /tmp/nuetron_port.log

   # create vm
   nova boot smoketest-$zone \
     --image $(nova image-list|grep redhat6-5-v |awk '{print $2}') \
     --flavor $(nova flavor-list | grep default |  awk '{print $2}') \
     --nic port-id=$(neutron port-list | grep smsriovport1-$zone | awk '{print $2}') \
     --nic port-id=$(neutron port-list | grep smsriovport2-$zone | awk '{print $2}') \
     --nic port-id=$(neutron port-list | grep smsriovport3-$zone | awk '{print $2}') \
     --security_groups smssh \
     --availability-zone $zone  &>> /tmp/nova_boot.log

   is_sriov='true'
}

function start_vms() {

   # delete log
   rm -f /tmp/nova_boot.log

   nova aggregate-list | grep -q aggregate
   # when there are no aggregates run on the first compute
   if [ $? -ne 0 ]; then
        arr=$(curl --silent http://10.1.1.1/ganglia/|perl -lane "print \$1 if /(compute-0.*?local)/"|sort | uniq|head -1)
        for i in $arr; do total=$((total+ 1)); done
        echo -n "Starting $total VM's: "
        for compute in $arr
        do
            echo "Starting VM on compute: $compute"
            boot_vm nova:$compute
        done
   else
        # getting all the host aggregates from nova
        agg_arr=$(nova aggregate-list | grep aggregate | awk '{print $4}')
        for agg in $agg_arr
        do
            # get the zone name from the host aggregate
            zone=$(nova aggregate-list | grep $agg | awk '{print $6}')
            # look for host aggregate with no SRIOV
            nova aggregate-details $agg | grep $agg | grep -q SRIOV
            if [ $? -ne 0 ]; then
               echo "Starting VM on zone: $zone"
               boot_vm $zone
            else
               echo "Starting VM with SRIOV on zone: $zone"
               boot_vm_sriov $zone
            fi
        done
   fi

   echo "Success"
}

function wait_for_running() {

   echo -n "Waiting for VM 'Running' status: "
   sleep 5

   # If we don't get this far, boot failure occured.
   nova list | grep -q smoketest
   if [ $? -ne 0 ]; then
      echo "Failed to boot VM."
      clean_up
      exit 255
   fi

   for i in {1..30}; do
      count=$(nova list | grep smoketest | grep -v Running | wc -l)
      if [ $count -gt 0 ]; then
         sleep 5
      else
         echo "Success"
         nova list|grep smoketest| awk -F\| '{print $3 $7}'
         # for sriov we are using the redhat 6-5 template and it takes time till it start (~1.5 minutes)
         if $is_sriov == 'true'; then echo "Waiting for SRIOV VM to start"; sleep 90; fi
         return
      fi
   done
   echo "Failed."
   clean_up
   exit 255
}

function check_vms() {

   for vm in `nova list | grep smoketest|awk '{print $2}'`
   do
      name=$(nova show $vm|grep smoketest|grep compute|awk '{print $4}')
      echo "Checking: $name"
      for var in `nova show $vm|grep network|awk '{print $2 "-" $5}'`
      do
         NET=${var%-*}; IP=${var##*-}
         ns=$(neutron net-list|grep $NET|awk '{print $2}')
         osn=$(neutron dhcp-agent-list-hosting-net $NET|grep os-network|head -1|awk '{print $4}')
         echo "Network $NET, namespace $ns on $osn"
         # DEV-27169 not checking for connectivity
         ssh $osn "ip netns exec qdhcp-$ns ping -c 3 $IP &> /dev/null"
         if [ $? -ne 0 ]; then
            echo "Failed ($NET): $IP"
         else
            echo "Success ($NET): $IP"
         fi
      done
   done
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

function check_exit_code() {

   if [ $? -ne 0 ]; then
      echo "Failed"
      echo "Running clean up"
      clean_up
      exit 255
   fi
   echo "Success"
}

clean_up
verify_creds
create_sec_group
create_networks
start_vms
wait_for_running
sleep 30 # Wait for iface dhcp
check_vms
clean_up
