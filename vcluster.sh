#!/bin/bash
# Deploy a simple app to test that everything is working in OpenStack Havana.
# Joey <joseph.mcdonald@alcatel-lucent.com>

# The number of computes you wish to start. If not entered, defaults to 2.
computes=$2
[[ $computes ]] || computes=6

start() {

   function install_centos() {
      echo "Installing ACID VM template."
      glance image-create --name centos-6.5 --disk-format qcow2 --container-format bare --is-public True --copy-from http://$ACID_SERVER/vcluster/centos-6.5.qcow2
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

   function start_acid() {
      nova boot acid --image $(nova image-list|grep centos-6.5|awk '{print $2}') --flavor $(nova flavor-list | grep default |  awk '{print $2}') \
         --nic net-id=$(neutron net-list | grep public | awk '{print $2}') \
         --security_groups ssh \
         --key_name rocks-ssh
      sleep 1

      #wait_for_ssh
      #create_acid_vols
      #attach_acid_vols
      #format_acid_vols
   }

   function get_vm_ip() {

      local ip=$(nova list|grep $1|perl -lane 'print $1 if (/public=(.*?)\;/)')
      echo $ip

   }

   function create_acid_vols() {
      cinder create --display_name acid_export 50
      cinder create --display_name acid_html 50
   }

   function attach_acid_vols() {
      instance=$(nova list | grep acid | awk '{print $2}')
      export=$(nova volume-list|grep export|awk '{print $2}')
      html=$(nova volume-list|grep html|awk '{print $2}')
   
      echo "Attaching: /export/ to $instance"
      nova volume-attach $instance $export auto
   
      echo "Attaching: /var/www/html/ to $instance"
      nova volume-attach $instance $html auto
   }

   function wait_for_ssh() {
      sleep 5;
      ip=$(get_vm_ip $1)

      cat /root/.ssh/known_hosts|grep -v "^$ip\s" > /tmp/known_hosts
      mv /tmp/known_hosts /root/.ssh/

      echo "Waiting for sshd on: $ip"
      while ! nc -w 2 -z $ip 22; do sleep 3; done 
   }

   function format_acid_vols() {
      ip=$(get_vm_ip acid)
      cssh="ssh -o StrictHostKeyChecking=no -t -l cloud-user -i /root/.ssh/rocks-ssh_id_rsa $ip"
   
      for disk in {vdb,vdc}
         do
            $cssh "sudo dd if=/dev/zero of=/dev/$disk bs=512 count=3"
            $cssh "sudo /sbin/parted -s -- /dev/$disk mklabel gpt"
            $cssh "sudo /sbin/parted -s -- /dev/$disk mkpart primary  0% 100%"
            $cssh "sudo mkfs.ext4 /dev/${disk}1"
         done
   
     $cssh 'sudo mkdir /export/ && sudo mount /dev/vdb1 /export/' 
     $cssh 'sudo mkdir -p /var/www/html && sudo mount /dev/vdc1 /var/www/html/' 
   }

   function create_nets() {
      # Create the 'Public' network and subnet for Rocks and the Computes.
      neutron net-create public --provider:network_type flat --provider:physical_network RegionOne

      # Here, we discover the 'public' network and build a subnet pool (limited as some are in use).
      net=$(ifconfig eth1 | perl -lane 'print $1 if /addr:(.*?)\s/' | cut -d'.' -f1-3);
      start="$net.100"
      end="$net.250"
      gateway=$(netstat -r|grep default|awk '{print $2}')
      mask=$(ifconfig eth1|perl -lane 'print $1 if /Mask:(.*?)$/')
      prefix=$(/bin/ipcalc -p $start $mask | awk -F\= '{print $2}')

      neutron subnet-create --name public-subnet --allocation-pool start=$start,end=$end --gateway $gateway \
         public $net.0/24 --dns_nameservers list=true 8.8.8.8

      # Private network
      neutron net-create private
      neutron subnet-create private 10.1.0.0/16 --name private-subnet --enable_dhcp=False
      # OOB
      neutron net-create oob
      neutron subnet-create oob 172.30.0.0/24 --name oob-subnet --enable_dhcp=False
      # Storage Network
      neutron net-create storage
      neutron subnet-create storage 10.2.0.0/24 --name storage-subnet --enable_dhcp=False

      #neutron router-create snet-router
      #neutron router-interface-add snet-router private-subnet
      #neutron router-interface-add snet-router public-subnet
      #neutron router-interface-add snet-router oob-subnet
      #neutron router-interface-add snet-router storage-subnet

      # Add a security group
      neutron security-group-create ssh
      neutron security-group-rule-create --direction ingress --ethertype IPv4 --protocol tcp --port-range-min 22 --port-range-max 22 ssh
      neutron security-group-rule-create --direction ingress --ethertype IPv4 --protocol icmp ssh
      # Add an ssh key
      ssh-keygen -N '' -f ~/.ssh/rocks-ssh_id_rsa
      nova keypair-add --pub-key ~/.ssh/rocks-ssh_id_rsa.pub rocks-ssh
   }

   function start_rocks_fe() {

      function port_create_rocksfe() {

         neutron port-create --mac-address fa:16:3e:90:97:18 \
	    --fixed-ip subnet_id=$(neutron net-list | grep private | awk '{print $6}'),ip_address=10.1.1.1 private

         neutron port-create --mac-address fa:16:3e:7d:d3:e3 \
	    --fixed-ip subnet_id=$(neutron net-list | grep public | awk '{print $6}'),ip_address=172.100.10.5 public

         neutron port-create --mac-address fa:16:3e:cb:67:cd \
	    --fixed-ip subnet_id=$(neutron net-list | grep oob | awk '{print $6}'),ip_address=172.30.0.1 oob

         neutron port-create --mac-address fa:16:3e:2b:47:e3 \
	    --fixed-ip subnet_id=$(neutron net-list | grep storage | awk '{print $6}'),ip_address=10.2.0.1 storage
      }

      function boot_rocksfe() {

         # Start the rocks-frontend.
         nova boot rocks-virt-dev --image $(nova image-list|grep rocks-virt-dev-1|awk '{print $2}') \
	    --flavor $(nova flavor-list | grep default |  awk '{print $2}') \
            --nic port-id=$(neutron port-list | grep 10.1.1.1 | awk '{print $2}') \
            --nic port-id=$(neutron port-list | grep 172.100.10.5 | awk '{print $2}') \
            --nic port-id=$(neutron port-list | grep 10.2.0.1 | awk '{print $2}') \
            --nic port-id=$(neutron port-list | grep 172.30.0.1 | awk '{print $2}') \
            --security_groups ssh 
      }
   
      function attach_fe_export() {

         # Here we create and attach a volume to be used as /export/ on the frontend holding all the 
	 # install stuff.
         echo "Creating 100G /export/ block device for the fronend."
         nova volume-list | grep -q rocks-fe-vol || nova volume-create --display-name rocks-fe-vol 100

         instance=$(nova list | grep rocks-virt-dev | awk '{print $2}')
         volume=$(nova volume-list|grep rocks-fe-vol |awk '{print $2}')
   
         while true; do
           nova list | grep rocks-virt-dev | grep -q ACTIVE
           RET=$?
           if [ $RET -eq 0 ]; then
              echo "Attaching: root disk ($volume) to $instance"
              nova volume-attach $instance $volume auto
              break
           fi
         done
   
      }


      function install_fe_key() {

         INSTKEY=/root/.ssh/fe_id_rsa
         cat << 'EOF' > $INSTKEY
	 -----BEGIN RSA PRIVATE KEY-----
	 MIIEoQIBAAKCAQEApCOHZpQ+HWnC7CiJeI2Wht4dyu5V6BivpuNYJvfz/X3bf+3a
	 ziGgeTIgVsETLTYp+Hz0wUFOTr335kOSEKJNxNMHZ4eXScX7xeyPOeAmFMLwEcTY
	 IQOTxmyAkkslirI1Zj9bTqgoTLpuGHUvmh7XlNPVHwnVuRKEqgjsyhqp+UIiugeT
	 m1QvbDvh+f/shEhhufB23oM1FQNRIPV12HvxZPwXAGtV/rp8n5ahLRESizWJCKlQ
	 Jz4zmUNO60IGTr+2p4h9FQ5IgFxjwL+ZXtXSRTsSCG5qrlo8Xnwu4ZjZcDMDWzqG
	 EH7gxJhw1wVyWLzuKeYy7+4u66bekXgd5KF/mQIBIwKCAQBwjWQpFTHoSIWpQF5E
	 CVFGia4HftvSWhIMCZuIb4K8c48zJsHsbtRwXOL5qPc08fDk5/hKAOU9TxBjYYi6
	 8vN/pqX92VHML/0aAUxE8XkyztCBNoWS+yOAv24bLDcABSvuV1SNtSLyyPsJdO1w
	 /zS90xXMJABEZHg6FL+gh0/7X3OavR5bA88mXWeo1l0PXd0LKAuk43SotYOqwUUE
	 qVmyF5uCMUB3Igy4eeETlkhgeMGdwE1S/3atGVNLqDvVWSpdudZkxzd6CnGztP+j
	 lhosxm2NEtrAungwrAdGHmp4PRzcuV/yS7gB0fzl8TI/UBuAlgZuYUH8b+hjWjbD
	 2AErAoGBANLb7I2JBbuOpSJvKvJ0aOwyIBOZc3kmMYBLxY63yaWHkWXCOIo9SYCG
	 p2xXtZ6ImSHRqdIv8CKB2O1xIcGoRFpLw7nhEbGov19azQVItDPLGBbzR94H4Arw
	 wtFdCuNqreSMpUWmaBWFTB/m0mhrpCZqjMiMEoExt9bVRDGHklnXAoGBAMdHHI8i
	 6OXFo920nF0EIT3Xi1JJ7rHOHnDRgLfPO1O5su51qvhpCf7hPXdDdZ/LQaIw8bfe
	 RC6wUB1WdZgPWVPoaxU2WhCa+HPqip9HkWL41vCnaw2iv5d8E9Lo9vAWK/9iBunT
	 aF7nT2rLiKCmGUpOfqEC4y1/ISorUFx/dCQPAoGASEtnC/R2/noMu1lQjaRBOwnf
	 HKmj7wXH1Dc8a3I2geVWbAgTYpirfIXwQmc29Iaa5wYOVrFZpW5ZAPOWi4omEFR9
	 ntDS3dN00DxjjMh4TEWh2/ujnJT8W4W/IzXX2PFgMRpHSxR7dRfCVBSf6Ul6G8zC
	 jebhxeUpFnUBcBE5feMCgYEAu+P2WxJJTau3wmh2K9CxoLVI2I7ZvZZ0eQALpf3n
	 etOotPKZ4uaxpywkArvyj1k94hDj5+AxqF0YVizyiA54y3S8vDqPbr4AMscyPmgM
	 vGb2iyGCMW2QEnxNNJKCbVa7xOdlmqLBfg1K4QkLyqs8aqHH2aOi/wLWIHH7T+Xi
	 iGUCgYBKsbMUyQOk/v+6GNPsy93erGU2KuIMxvCBTlLvh2bIHOMF+OscnyYvpWe8
	 2rBZDrwWyIWvocwjUlGhIGnjEuvs9oOZHWrjcEZ0XlMTBdl05p5EvHnCPtoV+NAx
	 QXJb7Nu1yhywMqvqlrxavGoR/yu4JCy1V9TSEjhbyuOucoWV2Q==
	 -----END RSA PRIVATE KEY-----
EOF

         perl -pi -e 's/^\s+//' /root/.ssh/fe_id_rsa
         chmod 600 $INSTKEY
      }

      function format_fe_export() {

         # We want a 100G /export/ on a seperte volume in case we need it later.
	 # Prefer that we keep this here rather than regularly alter the qcow2.
         ip=$(get_vm_ip rocks-virt-dev)
         cssh="ssh -o StrictHostKeyChecking=no -i /root/.ssh/fe_id_rsa $ip"

         $cssh "dd if=/dev/zero of=/dev/vdb bs=512 count=3"
         $cssh "/sbin/parted -s -- /dev/vdb mklabel gpt"
         $cssh "/sbin/parted -s -- /dev/vdb mkpart primary  0% 100%"
         $cssh "mkfs.ext4 /dev/vdb1"
         $cssh 'umount /export/ && mount /dev/vdb1 /export/'
	 $cssh 'cat /etc/fstab | grep -v 7f45d8fb-b0c9-4ebc-85f9-8c4070ef0695 > /tmp/fstab'
         $cssh 'echo "/dev/vdb1                                 /state/partition1       ext4     defaults        1 2" >> /tmp/fstab'
	 $cssh 'mv /tmp/fstab /etc/ && mount -a'
      }

      function copy_apps() {

         ip=$(get_vm_ip rocks-virt-dev)
         ls -d /export/ &> /dev/null || mkdir /export/
         mount -t nfs 10.1.1.1:/export/ /export/
         rsync -e 'ssh -o StrictHostKeyChecking=no -i /root/.ssh/fe_id_rsa' -aP /export/apps/ $ip:/export/apps/
         rsync -e 'ssh -o StrictHostKeyChecking=no -i /root/.ssh/fe_id_rsa' -aP /export/kvm/ $ip:/export/kvm/
         rsync -e 'ssh -o StrictHostKeyChecking=no -i /root/.ssh/fe_id_rsa' -aP /export/initialize_cluster.pl $ip:/export/
         rsync -e 'ssh -o StrictHostKeyChecking=no -i /root/.ssh/fe_id_rsa' -aP /export/ci/ $ip:/export/ci/
         umount /export/
      }

      port_create_rocksfe
      boot_rocksfe
      wait_for_ssh rocks-virt-dev 
      install_fe_key
      attach_fe_export
      copy_apps
   }

   function create_computes() {

      ip=$(get_vm_ip rocks-virt-dev)
      cssh="ssh -o StrictHostKeyChecking=no -i /root/.ssh/fe_id_rsa $ip"

      cfg='/tmp/computes.txt'
      rm -f $cfg

      for compute in $(seq 1 ${computes})
      do
	 mac="fa:$(openssl rand -hex 5 | sed 's/\(..\)/\1:/g; s/.$//')"
         echo "$compute $mac" >> $cfg
      done

      scp -i /root/.ssh/fe_id_rsa $cfg $ip:/export/ci/tools/
      $cssh 'perl /export/ci/tools/insert_ethers.pl /export/ci/tools/computes.txt'

   }

   function boot_computes() {

      ip=$(get_vm_ip rocks-virt-dev)
      cssh="ssh -o StrictHostKeyChecking=no -i /root/.ssh/fe_id_rsa $ip"

      ipc='/tmp/iface.txt'
      $cssh 'rocks list host interface compute|grep ^compute' &> $ipc

       while read line
       do
          compute=$(echo $line | awk '{print $1}')
          mac=$(echo $line | awk '{print $4}')
          ip=$(echo $line | awk '{print $5}')

          neutron port-create --mac-address $mac --fixed-ip subnet_id=$(neutron net-list | grep private | awk '{print $6}'),ip_address=$ip private

          # --nic net-id=$(neutron net-list | grep public | awk '{print $2}') \
          nova boot ${compute%?} \
            --flavor $(nova flavor-list | grep default |  awk '{print $2}') \
            --block-device source=image,id=$(nova image-list|grep centos|awk '{print $2}'),dest=volume,size=50,shutdown=preserve,bootindex=0 \
            --nic port-id=$(neutron port-list | grep $ip | awk '{print $2}') \
            --security_groups ssh

       done < $ipc
       rm $ipc
   }

   function install_fe_software() {

      ip=$(get_vm_ip rocks-virt-dev)
      cssh="ssh -o StrictHostKeyChecking=no -i /root/.ssh/fe_id_rsa $ip"
      $cssh 'perl /export/initialize_cluster.pl --install-software --ci'

   }

   create_nets
   start_rocks_fe
   install_fe_software
   create_computes
   boot_computes
   #start_acid
   
}

stop() {

   function purge_port() {
       for port in `neutron port-list -c id | egrep -v '\-\-|id' | awk '{print $2}'`
       do
           neutron port-delete ${port} &> /dev/null
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
      for volume in `nova volume-list | grep None | awk '{print $2}'`
         do
            nova volume-delete ${volume}
	    echo "Deleted volume: ${volume}"
         done
   }


   function purge_instances() {
      for inst in `nova list | grep ACTIVE| awk '{print $2}'`
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
   purge_volumes

   # Delete keys
   nova keypair-delete rocks-ssh
   rm -rf ~/.ssh/rocks-ssh*
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
