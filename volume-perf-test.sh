# Create a set of volume groups for ceph and solidfire with QoS enabled.
# Create some volumes, networks and compute instances. 
# Boot it all up and start testing it.
# 
# Joey <joseph.mcdonald@alctel-lucent.com>


function get_centos() {
   echo -n "Checking for CentOS 7 Guest VM: "
   nova image-list | grep -q centos-7 && echo "Ok" && return

   glance image-create --name centos-7 --is-public=true --container-format=bare --disk-format=qcow2 \
         --copy-from http://cloud.centos.org/centos/7/devel/CentOS-7-x86_64-GenericCloud.qcow2

      # Loop untili it's ready.
      while true; do
        nova image-list | grep centos-7 | grep -q ACTIVE
        RET=$?
        if [ $RET -eq 0 ]; then
           echo "Ok"
           break
        fi
        sleep 5
      done
}

function create_volume_type() {

   # Create volume types and the extra specs for those volumes.
   name=$1
   bottom=$2
   top=$3
   burst=$4
   backend=$5

   echo -n "Checking for $name volume type: "

   # If this volume type already exists, get outta here.
   cinder type-list|grep -q $name && echo "Ok" && return

   uuid=$(cinder type-create $name | perl -lane "print \$1 if /\|\s(.*?)\s.*?$name.*?/")
   cinder type-key $uuid set qos:minIOPS=$bottom qos:maxIOPS=$top qos:burstIOPS=$burst volume_backend_name=$backend
   echo "Ok"
}

function start() {

   # Uncomment this is you're already up and running and just want to run the volume tests.
   # volume_tests && exit

   # This is my main start function. Create everything and boot some VM's.
   get_centos
   create_volume_types
   create_volumes
   create_sec_group
   create_networks
   boot_vms
   wait_for_ssh 
   attach_volumes
   partition_disks
   volume_tests
}

function wait_for_ssh() {

   pub1=$(nova list |grep pub-1|perl -lane 'print $1 if /public-net=(.*?)\s/')
   pub2=$(nova list |grep pub-2|perl -lane 'print $1 if /public-net=(.*?)\s/')

   echo -n "Waiting for ssh on $pub1: "
   while ! nc -w 2 -z $pub1 22 &>> /dev/null; do sleep 2; done
   echo "Ok"
   echo -n "Waiting for ssh on $pub2: "
   while ! nc -w 2 -z $pub2 22 &>> /dev/null; do sleep 2; done
   echo "Ok"

}

function wait_for_active() {

   while true; do
      nova list | grep -q BUILD 
      RET=$?
      if [ $RET -ne 0 ]; then
         break
      fi
      sleep 5
   done
}

function create_volume_types() {

   # Create some slow volume types.
   create_volume_type low-iops-sf   800 1000 1500 solidfire
   create_volume_type low-iops-ceph 800 1000 1500 ceph

   # Create some faster volume types.
   create_volume_type high-iops-sf   8000 10000 15000 solidfire
   create_volume_type high-iops-ceph 8000 10000 15000 ceph
}

function create_volumes() {

   echo -n "Creating volumes: "
   # Slower vols
   cinder create --volume-type low-iops-sf   --display-name low-sf 15 &> /dev/null
   cinder create --volume-type low-iops-ceph --display-name low-ceph 15 &> /dev/null

   # Faster vols
   cinder create --volume-type high-iops-sf   --display-name high-sf 15 &> /dev/null
   cinder create --volume-type high-iops-ceph --display-name high-ceph 15 &> /dev/null
   echo "Ok"
}

function attach_volumes() {

   # Attach the volumes we created to our instances. 
   lowsf=$(cinder list|grep low-sf|awk '{print $2}')
   lowceph=$(cinder list|grep low-ceph|awk '{print $2}')

   highsf=$(cinder list|grep high-sf|awk '{print $2}')
   highceph=$(cinder list|grep high-ceph|awk '{print $2}')

   pub1=$(nova list |grep slow-pub-1|awk '{print $2}')
   pub2=$(nova list |grep fast-pub-2|awk '{print $2}')

   echo -n "Attaching volumes to instances: "
   nova volume-attach $pub1 $lowsf /dev/vdb &> /dev/null
   nova volume-attach $pub1 $lowceph /dev/vdc &> /dev/null
   nova volume-attach $pub2 $highsf /dev/vdb &> /dev/null
   nova volume-attach $pub2 $highceph /dev/vdc &> /dev/null
   echo "Ok"
}

function boot_vms() {

   echo -n "Booting instances: "
      nova boot slow-pub-1 --image $(nova image-list|grep centos-7 |awk '{print $2}') \
         --flavor $(nova flavor-list | grep default |  awk '{print $2}') \
         --nic net-id=$(neutron net-list | grep public-net| awk '{print $2}') \
         --security_groups ssh \
         --key_name smoketest \
         --availability-zone nova:compute-0-0.local  &> /dev/null

      nova boot fast-pub-2 --image $(nova image-list|grep centos-7|awk '{print $2}') \
         --flavor $(nova flavor-list | grep default |  awk '{print $2}') \
         --nic net-id=$(neutron net-list | grep public-net| awk '{print $2}') \
         --security_groups ssh \
         --key_name smoketest \
         --availability-zone nova:compute-0-1.local  &> /dev/null

   echo "Ok"
}

function create_sec_group() {

   echo -n "Creating Security Groups and Keys: "

   # Add a security group
   neutron security-group-create ssh &> /dev/null
   neutron security-group-rule-create --direction ingress --ethertype IPv4 \
      --protocol tcp --port-range-min 22 --port-range-max 22 ssh &> /dev/null
   neutron security-group-rule-create --direction ingress --ethertype IPv4 \
      --protocol icmp ssh &> /dev/null

   # Add an ssh key
   ssh-keygen -N '' -f ~/.ssh/smoketest_id_rsa &> /dev/null
   nova keypair-add --pub-key ~/.ssh/smoketest_id_rsa.pub smoketest &> /dev/null

   echo "Ok"
}

function create_networks() {

   echo -n "Creating Guest Networks: "
   # This is a little more complicated but much easier to login to the provider network
   # than a guest network. Doesn't require a router or floating IP's etc.
   # This should be untagged network_type:flat (rather than vlan) 
   # Provider network is RegionOne, yours will be different probably. 
   neutron net-create public-net --provider:network_type flat --provider:physical_network RegionOne &> /dev/null

   # Here, we discover the 'public' network and build a subnet pool (limited as some are in use).
   net=$(ifconfig eth1 | perl -lane 'print $1 if /addr:(.*?)\s/' | cut -d'.' -f1-3);
   start="$net.200"
   end="$net.250"
   gateway=$(route -n | grep "^0\.0\.0\.0 " | awk '{print $2}')
   mask=$(ifconfig eth1|perl -lane 'print $1 if /Mask:(.*?)$/')
   prefix=$(/bin/ipcalc -p $start $mask | awk -F\= '{print $2}')

   neutron subnet-create --name public-subnet --allocation-pool start=$start,end=$end \
      --gateway $gateway public-net $net.0/24 --dns_nameservers list=true 8.8.8.8 &> /dev/null

   echo "Ok"
}

function partition_disks() {

   pub1=$(nova list |grep pub-1|perl -lane 'print $1 if /public-net=(.*?)\s/')
   pub2=$(nova list |grep pub-2|perl -lane 'print $1 if /public-net=(.*?)\s/')
   login='ssh -q -t -oStrictHostKeyChecking=no -l centos -i /root/.ssh/smoketest_id_rsa'

   # partition disks
   echo -n "Partitioning volumes: "
   $login $pub1 'echo -e "o\nn\np\n1\n\n\nw" | sudo /usr/sbin/fdisk /dev/vdb' &> /dev/null
   $login $pub1 'echo -e "o\nn\np\n1\n\n\nw" | sudo /usr/sbin/fdisk /dev/vdc' &> /dev/null
   $login $pub2 'echo -e "o\nn\np\n1\n\n\nw" | sudo /usr/sbin/fdisk /dev/vdb' &> /dev/null
   $login $pub2 'echo -e "o\nn\np\n1\n\n\nw" | sudo /usr/sbin/fdisk /dev/vdc' &> /dev/null
   echo "Ok"

   # format disks
   echo -n "Formatting volumes: "
   $login $pub1 'sudo /usr/sbin/mkfs.ext4 /dev/vdb1' &> /dev/null
   $login $pub1 'sudo /usr/sbin/mkfs.ext4 /dev/vdc1' &> /dev/null
   $login $pub2 'sudo /usr/sbin/mkfs.ext4 /dev/vdb1' &> /dev/null
   $login $pub2 'sudo /usr/sbin/mkfs.ext4 /dev/vdc1' &> /dev/null
   echo "Ok"

   # mount disks
   echo -n "Mounting volumes: "
   $login $pub1 'sudo mkdir /slowsf/   && sudo mount /dev/vdb1 /slowsf/' &> /dev/null
   $login $pub1 'sudo mkdir /slowceph/ && sudo mount /dev/vdc1 /slowceph/' &> /dev/null
   $login $pub2 'sudo mkdir /fastsf/   && sudo mount /dev/vdb1 /fastsf/' &> /dev/null
   $login $pub2 'sudo mkdir /fastceph/ && sudo mount /dev/vdc1 /fastceph/' &> /dev/null
   echo "Ok"
}

function volume_tests() {

   pub1=$(nova list |grep pub-1|perl -lane 'print $1 if /public-net=(.*?)\s/')
   pub2=$(nova list |grep pub-2|perl -lane 'print $1 if /public-net=(.*?)\s/')
   login='ssh -q -t -oStrictHostKeyChecking=no -l centos -i /root/.ssh/smoketest_id_rsa'

   echo ""

   echo "Testing slow solidfire: "
   $login $pub1 'sudo dd if=/dev/zero of=/slowsf/dd.img bs=1M count=512 oflag=direct' | grep MB
   echo ""

   echo "Testing slow ceph: "
   $login $pub1 'sudo dd if=/dev/zero of=/slowceph/dd.img bs=1M count=512 oflag=direct' | grep MB
   echo ""

   echo "Testing fast solidfire: "
   $login $pub2 'sudo dd if=/dev/zero of=/fastsf/dd.img bs=1M count=512 oflag=direct' | grep MB
   echo ""

   echo "Testing fast ceph: "
   $login $pub2 'sudo dd if=/dev/zero of=/fastceph/dd.img bs=1M count=512 oflag=direct' | grep MB
   echo ""
}

function stop() {

   # This blows away absolutely everything, make sure nothing else is running here.
   echo 'stopping'
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

   function purge_volumes() {
      for vol in `cinder list | egrep -o '[0-9a-z\-]{36}' | egrep -v '\-\-|id'`
         do
            echo "Deleting Volume: ${vol}"
            cinder delete ${vol}
         done
   }
   function purge_volume_types() {
      for type in `cinder type-list | egrep -o '[0-9a-z\-]{36}' | egrep -v '\-\-|id'`
         do 
            echo "Deleting volume type: ${type}"
            cinder type-delete ${type}
         done
   }


   function purge_instances() {
      for inst in `nova list | egrep -o '[0-9a-z\-]{36}' | egrep -v '\-\-|id'`
         do
            echo "Deleting Instance: ${inst}"
            nova delete ${inst}
         done
   }

   function purge_known_hosts() {

      # Delete existing guest host profiles so they don't interfere with the next
      # round of testing.
      pub1=$(nova list |grep pub-1|perl -lane 'print $1 if /public-net=(.*?)\s/')
      pub2=$(nova list |grep pub-2|perl -lane 'print $1 if /public-net=(.*?)\s/')

      cat /root/.ssh/known_hosts | egrep -v "$pub1|$pub2" > /tmp/known_hosts
      mv /tmp/known_hosts /root/.ssh/

   }

   # Stop Instances
   purge_known_hosts
   purge_instances
   purge_floaters
   purge_router
   sleep 5
   purge_port
   purge_subnet
   purge_net
   purge_secgroup
   purge_volumes
   sleep 10
   purge_volume_types

   # Delete keys
   nova keypair-delete smoketest
   rm -rf ~/.ssh/smoketest*
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


