#
# This script will launch a VM on each compute node in a cluster.
# It will then ping each interface within each VM to determine if
# the deployment is happy.
#
# Joey <joseph.mcdonald@alcatel-lucent.com

function secgroup() {
   neutron security-group-create ssh &> /dev/null
   neutron security-group-rule-create --direction ingress --ethertype IPv4 --protocol tcp --port-range-min 22 --port-range-max 22 ssh &> /dev/null
   neutron security-group-rule-create --direction ingress --ethertype IPv4 --protocol icmp ssh &> /dev/null
}

function boot_vm() {
   compute=$1
   echo "Starting a VM on: $compute"

   nova boot smoketest-$compute \
     --image $(nova image-list|grep cirros_4nics |awk '{print $2}') \
     --flavor $(nova flavor-list | grep default |  awk '{print $2}') \
     --nic net-id=$(neutron net-list | grep net0 | awk '{print $2}') \
     --nic net-id=$(neutron net-list | grep net1 | awk '{print $2}') \
     --nic net-id=$(neutron net-list | grep net2 | awk '{print $2}') \
     --nic net-id=$(neutron net-list | grep net3 | awk '{print $2}') \
     --security_groups ssh \
     --availability-zone nova:${compute} &> /dev/null
}

function start_vms() {

   for compute in `ssh os-controller "nova-manage service list|grep ^nova-compute|sort --version-sort -f|awk '{print \\$2}'"`
   do
      boot_vm $compute
   done
}

function check_vms() {

   for vm in `nova list | grep smoketest|awk '{print $2}'`
   do
      name=$(nova show $vm|grep smoketest|awk '{print $4}')
      echo "Checking: $name"
      for var in `nova show $vm|grep network|awk '{print $2 "-" $5}'`
      do
         NET=${var%-*}; IP=${var##*-}
         ns=$(neutron net-list|grep $NET|awk '{print $2}')
         ip netns exec qdhcp-$ns ping -c 3 $IP &> /dev/null
         if [ $? -ne 0 ]; then
            echo "Failed: $IP"
         else
            echo "Success: $IP"
         fi
      done
   done
}

function stop_vms() {

   for vm in `nova list| grep smoketest|awk '{print $2}'`
   do
      nova delete $vm
   done
}

stop_vms
start_vms
sleep 30
check_vms
stop_vms


