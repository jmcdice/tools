# Create a set of volume groups for ceph and solidfire with QoS enabled.
# Create some volumes, networks and compute instances. 
# Boot it all up and start testing it.
# 
# Joey <jmcdice@gmail.com>

args=$*

function get_backends() {
   # Support multiple backend deployment testing specified on the cmdline
   # If I don't have any specified on the cmdline, assume ceph.
   # Bash argument handling leaves something to be desired.

   local backends=$(echo $args | perl -lane "@b = split /,/, \$1 if /backend=(.*?)$/; for(@b) { print $_ }")
   if [ -z "$backends" ]; then
      backends='ceph'
   fi

   echo $backends
}


function get_centos() {
   echo -n "Checking for CentOS 7 Guest VM: "

   # Jump out of we already have it.
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

   # Create volume types and the extra specs (QoS) for those volumes.
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

   slowvm=$(nova list |grep slowvm|perl -lane 'print $1 if /public-net=(.*?)\s/')
   fastvm=$(nova list |grep fastvm|perl -lane 'print $1 if /public-net=(.*?)\s/')

   echo -n "Waiting for ssh on $slowvm: "
   while ! nc -w 2 -z $slowvm 22 &>> /dev/null; do sleep 2; done
   echo "Ok"
   echo -n "Waiting for ssh on $fastvm: "
   while ! nc -w 2 -z $fastvm 22 &>> /dev/null; do sleep 2; done
   echo "Ok"

   # Now that ssh is up, wait for cloud-init to pull the keys from nova.
   sleep 5
}

function create_volume_types() {

   backends=$(get_backends)

   for i in $backends; do
      create_volume_type low-iops-$i 800 1000 1500 $i
      create_volume_type high-iops-$i 8000 10000 15000 $i
   done
}

function create_volumes() {

   echo -n "Creating volumes: "
   backends=$(get_backends)

   # Create a random number of volumes per test run.
   count=$(( ( RANDOM % 10 )  + 1 ))

   for x in $(seq $count); do
      for i in $backends; do
         cinder create --volume-type low-iops-$i  --display-name low-$i-$x  15 &> /dev/null
         cinder create --volume-type high-iops-$i --display-name high-$i-$x 15 &> /dev/null
      done
   done

   echo "Ok"
}

function attach_volumes() {

   slowvm=$(nova list |grep slowvm|awk '{print $2}')
   fastvm=$(nova list |grep fastvm|awk '{print $2}')
   backends=$(get_backends)

   echo -n "Attaching volumes to instances: "

   for i in $backends; do
      for id in `cinder list|grep low-$i|awk '{print $2}'`
         do 
         nova volume-attach $slowvm $id &> /dev/null
      done
      for id in `cinder list|grep high-$i|awk '{print $2}'`
         do 
         nova volume-attach $fastvm $id &> /dev/null
      done
   done

   # Allow the volumes to attach in the Guest OS
   sleep 6
   echo "Ok"
}

function boot_vms() {

   echo -n "Booting instances: "
      nova boot slowvm  --image $(nova image-list|grep centos-7 |awk '{print $2}') \
         --flavor $(nova flavor-list | grep default |  awk '{print $2}') \
         --nic net-id=$(neutron net-list | grep public-net| awk '{print $2}') \
         --security_groups ssh \
         --key_name smoketest \
         --availability-zone nova:compute-0-0.local  &> /dev/null

      nova boot fastvm --image $(nova image-list|grep centos-7|awk '{print $2}') \
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
   ssh-keygen -N '' -f ~/.ssh/smoketest_id_rsa  &> /dev/null
   nova keypair-add --pub-key ~/.ssh/smoketest_id_rsa.pub smoketest 

   echo "Ok"
}

function create_networks() {

   echo -n "Creating Guest Networks: "
   # This is a little more complicated but much easier to login to a provider network
   # than a guest network. Doesn't require a router or floating IP's etc.
   # This should be untagged network_type:flat (rather than vlan) 
   # Provider network is RegionOne, yours will be different, probably. 
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

   slowvm=$(nova list |grep slowvm|perl -lane 'print $1 if /public-net=(.*?)\s/')
   fastvm=$(nova list |grep fastvm|perl -lane 'print $1 if /public-net=(.*?)\s/')
   login='ssh -q -t -oStrictHostKeyChecking=no -l centos -i /root/.ssh/smoketest_id_rsa'
   backends=$(get_backends)
   echo -n "Partitioning and formatting volumes: "

   for i in $backends; do
      for disk in `$login $slowvm "sudo fdisk -l|grep ^Disk|grep sect | awk '{print \\$2}' | sed 's/:\$//' | tr -d '\015' | grep -v vda"`
      do
         disk="${disk%?}"  # Funny char at the end of $disk
         drive=$(echo $disk | sed 's/\/dev\///')
         fmt="echo -e 'o\nn\np\n1\n\n\nw'"
         fdisk="sudo /usr/sbin/fdisk $disk"
         $login $slowvm "$fmt | $fdisk"  &> /dev/null
         one="1"
         disk=$disk$one
         $login $slowvm "sudo /usr/sbin/mkfs.xfs $disk" &> /dev/null
         $login $slowvm "sudo mkdir /slow-$i-$drive/ ; sleep 5; sudo mount $disk /slow-$i-$drive/"
      done

      for disk in `$login $fastvm "sudo fdisk -l|grep ^Disk|grep sect | awk '{print \\$2}' | sed 's/:\$//' | tr -d '\015' | grep -v vda"`
      do
         disk="${disk%?}"  # Funny char at the end of $disk
         drive=$(echo $disk | sed 's/\/dev\///')
         fmt="echo -e 'o\nn\np\n1\n\n\nw'"
         fdisk="sudo /usr/sbin/fdisk $disk"
         $login $fastvm "$fmt | $fdisk" &> /dev/null
         one="1"
         disk=$disk$one
         $login $fastvm "sudo /usr/sbin/mkfs.xfs $disk"  &> /dev/null
         $login $fastvm "sudo mkdir /fast-$i-$drive/ ; sleep 5; sudo mount $disk /fast-$i-$drive/"
      done

      echo "Ok"
   done
}

function volume_tests() {

   slowvm=$(nova list |grep slowvm|perl -lane 'print $1 if /public-net=(.*?)\s/')
   fastvm=$(nova list |grep fastvm|perl -lane 'print $1 if /public-net=(.*?)\s/')
   login='ssh -q -t -oStrictHostKeyChecking=no -l centos -i /root/.ssh/smoketest_id_rsa'

   echo "Running Volume Tests"
   backends=$(get_backends)

   for i in $backends; do 

      for dir in `$login $fastvm "df -h|grep fast|awk '{print \\$NF}'"`
      do
         dir="${dir%?}"
         echo -n "Testing fast $i ($dir): "
         $login $fastvm "sudo dd if=/dev/zero of=$dir/dd.img bs=1M count=512 oflag=direct" | \
         grep MB | awk '{ print $8, $9 }'
      done

      for dir in `$login $slowvm "df -h|grep slow|awk '{print \\$NF}'"`
      do
         dir="${dir%?}"
         echo -n "Testing slow $i ($dir): "
         $login $slowvm "sudo dd if=/dev/zero of=$dir/dd.img bs=1M count=512 oflag=direct" | \
         grep MB | awk '{ print $8, $9 }'
      done

   done

}

function stop() {

   # !! Warning !!
   # This blows away absolutely everything in your cluster when run as admin! Don't 
   # run this unless you know exactly what you're doing.
   echo 'Stopping Everything.'
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

      # Delete existing guest host keys so they don't interfere with the next
      # round of testing.
      for ip in `nova list|perl -lane 'print $1 if /public-net=(.*?)\s/'`; do
         ssh-keygen -f '/root/.ssh/known_hosts' -R $ip &> /dev/null
      done
      rm -f /root/.ssh/known_hosts.old
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
    volume-test)
        volume_tests 
        exit
        ;;
    *)
        echo ""
        echo $"Usage: $0 {start|stop|volume-test|<backend=ceph,solidfire>}"
        echo ""
        echo "Examples: "
        echo "   ./volume-perf-test.sh start backend=solidfire,ceph"
        echo "   ./volume-perf-test.sh volume-test backend=solidfire,ceph"
        echo ""
        RETVAL=3
esac
