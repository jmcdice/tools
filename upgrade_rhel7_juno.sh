# Turn me into a RHEL 7 node with Juno.
# Yosi keeps messing up so, time to automate this whole thing.
# Joey <jmcdice@gmail.com>

echo "Upgrading node to RHEL7 and Juno."
echo ""

function stop_ha() {

   echo -n "Stopping HA services: "
   service pacemaker stop &> /dev/null
   service puppetmaster stop &> /dev/null
   service haproxy stop &> /dev/null
   rm -f /etc/cluster/cluster.conf

   ssh vm-manager-0-0 'service pacemaker stop' &> /dev/null
   ssh vm-manager-0-0 'rm -f /etc/cluster/cluster.conf'
   echo "Ok"
}

function reset_ceph() {

   # Wipe out ceph
   echo -n "Wiping out Ceph: "
   echo YES | sh /export/apps/ceph/resetceph.sh &> /dev/null
   echo "Ok"
}

function backup_repo() {
   
   echo -n "Backing up RHEL 6 repo: "
   # Create a backup of the RHEL 6.5 ISO
   dir -1 /export/rolls/ &> /dev/null || mkdir /export/rolls/ 
   cd /export/rolls/
   if [ -e RHEL-6.5-0.x86_64.disk1.iso ]
   then
     echo "Ok"
   else 
      rocks create mirror http://10.1.1.1/install/rolls/RHEL/6.5/redhat/x86_64/RPMS/ rollname=RHEL version=6.5 &> /dev/null
      echo "Ok"
   fi
}

function get_rhel7() {

   echo -n "Checking RHEL 7 roll: "
   # Aquire the RHEL 7 roll.
   if [ -e /export/rolls/rhel-server-7.0-x86_64-dvd.iso ]
   then 
      echo "Ok"
   else
      echo "Downloading"
      iso='http://joey-build.cloud-band.com/iso/rhel-server-7.0-x86_64-dvd.iso'
      wget --progress=bar:force $iso -O /export/rolls/rhel-server-7.0-x86_64-dvd.iso 2>&1 | progressfilt
      echo "Download Complete"
   fi

}

function clean_repo() {

   # Remove the linked in cruft to the repo (which should absolutely be a roll)
   echo -n "Cleaning up repo: "
   cd /export/rocks/contrib/rocks-dist/6.0.2/x86_64/RPMS/
   ls -l | grep \/export\/apps | perl -lane 'system "rm -f @F[8]"'
   echo "Ok"
}

function setup_el7() {

   echo -n "Preparing repo with RHEL 7: "
   # Setup the distro for RHEL7 compute installs.
   rocks disable roll ganglia &> /dev/null
   rocks disable roll alu-fe &> /dev/null
   rocks disable roll puppet &> /dev/null
   rocks disable roll nagios &> /dev/null
   rocks disable roll web-server &> /dev/null
   rocks disable roll openstack-havana-neutron &> /dev/null
   rocks remove roll RHEL &> /dev/null
   rocks disable roll ganglia &> /dev/null
   rocks remove roll ceph-0.80.7-patch &> /dev/null
   cd /export/rolls/
   rocks add roll rhel-server-7.0-x86_64-dvd.iso &> /dev/null
   rocks enable roll RHEL &> /dev/null
   rocks create distro &> /dev/null
   echo "Ok"
}

function pxe_boot_computes() {

   rocks set host boot compute action=install

   for compute in `rocks list host compute | perl -lane 'print $1 if /(compute.*?):/'`
   do
      ip=$(grep $compute /var/cluster/ipmi |awk '{print $2}')
      echo "pxeboot $compute: $ip"
      pxeboot $ip 
   done

   # Sleep for 5 min while we wait..
   sleep 300
}

function pxeboot() {

   /usr/bin/ipmitool -I lanplus -H $1 -U hp -P password chassis bootdev pxe;  sleep 6 &> /dev/null
   /usr/bin/ipmitool -I lanplus -H $1 -U hp -P password chassis power off; sleep 6 &> /dev/null
   /usr/bin/ipmitool -I lanplus -H $1 -U hp -P password chassis power on &> /dev/null
}

function fix_grub_and_reboot() {

   rocks set host boot compute action=os
   echo "" > ~/.ssh/known_hosts

   for compute in `rocks list host compute | perl -lane 'print $1 if /(compute.*?):/'`
   do
      while true; do
      ssh -q -p 2200 $compute 'rpm -q foundation-redhat' | grep -q x86_64

         RET=$?
         if [ $RET -eq 0 ]; then
            sleep 120 # Enough time to fininsh post-install stuff in anaconda
            install_grub $compute
            break
         else 
            sleep 20
         fi
      done
   done 
}

function install_grub() {

   compute=$1

   echo -n "Updating Grub2 config $compute: "

   rpms='/state/partition1/rocks/rolls/RHEL/7.0/redhat/x86_64/RPMS'
   rsync -aP -e 'ssh -p 2200' $rpms/grub2*.rpm $compute:/mnt/sysimage/ &> /dev/null
   rsync -aP -e 'ssh -p 2200' $rpms/os-prober-1.58-5.el7.x86_64.rpm $compute:/mnt/sysimage/ &> /dev/null

   cat <<EOF> /root/grub
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="\$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="rd.lvm.lv=rhel/root crashkernel=auto  rd.lvm.lv=rhel/swap vconsole.font=latarcyrheb-sun16 vconsole.keymap=us rhgb quiet"
GRUB_DISABLE_RECOVERY="true"
EOF
   scp -q -P 2200 /root/grub $compute:/mnt/sysimage/etc/default/

   # The rpmdb is left in an unusable state, rebuild it from scratch.
   cat <<EOF> /root/update_grub.sh
rm -rf /var/lib/rpm/__db.00*
rpm --rebuilddb
rpm -Uvh /*.rpm && rm -f /*.rpm
/sbin/grub2-install --force /dev/sda
/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
EOF

   cat <<EOF> /root/device.map
# this device map was generated by joey
(hd0)      /dev/sda
(hd1)      /dev/sdb
EOF

   scp -q -P 2200 /root/device.map $compute:/mnt/sysimage/boot/grub2
   scp -q -P 2200 /root/update_grub.sh $compute:/mnt/sysimage/root/
   ssh -p 2200 $compute 'chroot /mnt/sysimage/ sh /root/update_grub.sh' &> /dev/null
   ssh -p 2200 $compute 'mkdir -p /mnt/sysimage/root/.ssh/' &> /dev/null
   scp -q -P 2200 /root/.ssh/authorized_keys $compute:/mnt/sysimage/root/.ssh/
   ssh -p 2200 $compute 'reboot' &> /dev/null

   echo "Ok"

}

function wait_for_boot() {

   computes=$1
   echo -n "Waiting for $computes to reboot: "
   while true; do
      rocks run host $computes date &> /dev/null
      RET=$?
      if [ $RET -eq 0 ]; then
         echo "Ok"
         break
      fi
      sleep 5
   done
}

function progressfilt() {
    local flag=false c count cr=$'\r' nl=$'\n'
    while IFS='' read -d '' -rn 1 c
    do
        if $flag
        then
            printf '%c' "$c"
        else
            if [[ $c != $cr && $c != $nl ]]
            then
                count=0
            else
                ((count++))
                if ((count > 1))
                then
                    flag=true
                fi
            fi
        fi
    done
}

function sync_juno_and_friends() {

   echo -n "Checking for the Juno roll: "
   # Aquire the RHEL 7 roll.
   if [ -e /export/rolls/juno_bundle.tgz ]
   then
      echo "Ok"
   else
      echo "Downloading"
      tgz='http://joey-build.cloud-band.com/el7/juno_bundle.tgz'
      wget --progress=bar:force $tgz -O /export/rolls/juno_bundle.tgz 2>&1 | progressfilt
      echo "Download Complete"

      cd /export/rolls/
      tar -zxf juno_bundle.tgz
      mv /export/rolls/juno/ /var/www/html/
      chown -R apache:apache /var/www/html/juno/
   fi
}

function create_juno_repo() {

   echo -n "Creating a Juno/RHEL 7 repo: "
   cd /var/www/html/juno/
   createrepo . &> /dev/null

   cat <<EOF> /tmp/mega.repo
[EL7-Juno]
name=Juno Repo
baseurl=http://10.1.1.1/juno/
assumeyes=1
gpgcheck=0
EOF

   rocks list host compute |perl -lane 'system "scp -q /tmp/mega.repo $1:/etc/yum.repos.d/" if /^(.*?):/'

   echo "Ok"
}

function mount_apps_share() {

   echo -n "Mounting NFS share: "
   rocks run host compute 'mkdir -p /share/apps/ && mount 10.1.1.1:/state/partition1/apps/ /share/apps/'
   echo "Ok"
}

function install_python_ceph_puppet() {

   echo "Installing Python, Ceph and Puppet: "
   rocks run host compute command='perl -pi -e "s/gpgcheck=1/gpgcheck=0/" /etc/yum.conf'
   rocks run host compute 'yum -y install python-IPy.noarch python-paramiko.noarch python-crypto python-netifaces netcf-libs ethtool' &> /dev/null
   rocks run host compute 'yum clean all' &> /dev/null
   rocks run host compute 'yum -y install ceph puppet' &> /dev/null
   sed -i 's/timeout=30//' /share/apps/ceph/ceph_ng/deploy_osds.py

   echo "Ok"
}

function pingcheck() {

   ip=$1
   ping -c 2 $ip &> /dev/null
   if [ $? -ne 0 ]; then
      echo ""
      echo "FATAL unable to ping: $ip."
      exit 255
   fi
}

function create_interface_config() {


   dev=$1 ip=$2 nm=$3 mtu=$4 host=$5

   mac=$(ssh $host "grep HWADDR /etc/sysconfig/network-scripts/ifcfg-$dev" | awk -F\" '{ print $2 }')

   cat <<EOF>/tmp/ifcfg-$dev
DEVICE="$dev"
BOOTPROTO="static"
HWADDR="$mac"
IPADDR="$ip"
NETMASK="$nm"
NM_CONTROLLED="yes"
ONBOOT="yes"
TYPE="Ethernet"
MTU="$mtu"
EOF

   scp -q /tmp/ifcfg-$dev $host:/etc/sysconfig/network-scripts/
   rm /tmp/ifcfg-$dev
   ssh $host "ifconfig $dev $ip netmask $nm"
   ssh $host "ifconfig $dev mtu $mtu"
}

function add_public_storage_ips() {

   echo -n "Setting public and storage IP's: "
   lan=$(ifconfig br1|perl -lane 'print $1 if /addr:(.*?)\s.*?Mask.*?/' |cut -d'.' -f1-3)
   pub=$(rocks list host interface compute-0-0|grep public|awk '{print $2}')

   # This is some badass bash foo right here.
   str=$(dmidecode|grep Product|awk -F: '{print $2}'|head -1| \
         perl -lane 'system qq|grep "@F" /export/apps/common/perl/ALU/common/ACID.pm|'| \
         grep storage|perl -lane 'print $1 if /(eth\d)/')

   nm=$(ifconfig br1|perl -lane 'print $1 if /Mask:(.*?)$/')

   count='50'

   for compute in `rocks list host compute | perl -lane 'print $1 if /(compute.*?):/'`
   do
      # Reload interface drivers, otherwise ping doesn't always work.
      pdriver=$(ssh $compute "ethtool -i $pub"|grep driver|awk '{print $2}')
      sdriver=$(ssh $compute "ethtool -i $str"|grep driver|awk '{print $2}')
      end=$(host $compute|awk -F. '{print $NF}')

      ssh $compute "nohup rmmod $pdriver; modprobe $pdriver; systemctl restart network.service"
      sleep 15

      create_interface_config $pub $lan.$count $nm 1500 $compute
      create_interface_config $str 10.2.0.$end $nm 9000 $compute

      sleep 5
      pingcheck 10.2.0.$end

   count=$[count + 1]
   done

   echo "Ok"
}

function create_storage_cluster() {

   echo -n "Creating Storage Cluster: "
   cd /export/
   grep ceph_ng initialize_cluster.pl|head -2 > /tmp/setup_ceph.pl
   echo "check_ceph_setup();" >> /tmp/setup_ceph.pl
   cat initialize_cluster.pl | perl -lane 'if ( /^sub check_ceph/ ... /^\}/) { print }' >> /tmp/setup_ceph.pl
   perl -pi -e 's/&>> \$mainlogfile//' /tmp/setup_ceph.pl
   cat /tmp/setup_ceph.pl | grep -v html > /export/setup_ceph.pl

   perl /export/setup_ceph.pl &> /dev/null
   python /export/apps/ceph/ceph_pool_deploy.py mgmt &> /dev/null

   echo "Ok"
}

function mount_ceph_fuse() {

   echo -n "Mounting ceph-fuse: "
   rocks run host compute 'yum -y install ceph-fuse' &> /dev/null
   rocks run host compute command='ceph-fuse --admin-socket=/var/run/ceph/fuse.asok /cloudfs -o rw' &> /dev/null
   echo "Ok"
}

function reset_rocks_repo() {

   echo -n "Restoring RHEL 6.5 Repo: "
   rocks remove roll RHEL &> /dev/null
   rocks add roll /export/rolls/RHEL-6.5-0.x86_64.disk1.iso &> /dev/null
   rocks enable roll RHEL &> /dev/null
   rocks enable roll web-server &> /dev/null
   rocks enable roll ganglia &> /dev/null
   rocks enable roll alu-fe &> /dev/null
   rocks enable roll puppet &> /dev/null
   rocks enable roll nagios &> /dev/null
   rocks create distro &> /dev/null
   echo "Ok"
}

function start_management_vms() {

   echo "Installing Management VMs"
   echo ""
   service puppetmaster stop &> /dev/null
   service pacemaker stop &> /dev/null
   ssh vm-manager-0-0 'service pacemaker stop' &> /dev/null
   perl /export/ci/tools/insert_vms.pl /export/kvm/templates/defaultTemplate/management_vms.csv &> /dev/null

   def='http://joey-build.cloud-band.com/iso/defaultTemplate-v23.qcow2'
   exp='/export/kvm/templates/defaultTemplate/defaultTemplate-v23.qcow2'

   if [ ! -e $exp ]; then
      echo "Downloading RHEL 7 Service Template"
      wget --progress=bar:force $def -O $exp 2>&1 | progressfilt
   fi

   perl -pi -e 's/defaultTemplate-v22.qcow2/defaultTemplate-v23.qcow2/' /export/apps/initialize_cluster/enable_kvm_vms.pl
   modprobe kvm; modprobe kvm_intel
   ssh vm-manager-0-0 'modprobe kvm; modprobe kvm_intel'
   perl /export/apps/initialize_cluster/add_libvirt_sec.pl --client client.libvirt --pool mgmt &> /dev/null

   cd /export/apps/qemu/ && dir -1 | perl -lane 'system "rpm -e --nodeps $1" if (/(.*?)-\d.*?/)' &> /dev/null
   rpm -e qemu-img-rhev qemu-kvm-rhev &> /dev/null
   rpm -Uvh /export/apps/qemu/*.rpm &> /dev/null
   service libvirtd restart &> /dev/null

   ssh vm-manager-0-0 "cd /share/apps/qemu/ && dir -1 | perl -lane 'system qq|rpm -e --nodeps \$1| if (/(.*?)-\d.*?/)'" &> /dev/null
   ssh vm-manager-0-0 'rpm -e qemu-img-rhev qemu-kvm-rhev' &> /dev/null
   ssh vm-manager-0-0 'rpm -Uvh /share/apps/qemu/*.rpm' &> /dev/null
   ssh vm-manager-0-0 'service libvirtd restart' &> /dev/null

   perl /export/apps/initialize_cluster/enable_kvm_vms.pl &> /dev/null

   # push the ssh keys
   pw=$(grep SERVICE_VM_TEMPLATE_PASSWORD /export/apps/cluster-config.txt|awk '{print $2}')

   for host in `rocks list host alu-vm|perl -lane 'print $1 if /^(.*?):/'`
   do
      perl /export/apps/CloudBand/set_pw.pl --passwd $pw --ip $host
   done

   echo "Ok"
}

function prepare_aluvms() {

   echo -n "Setting up ALU VM's: "

   # Set VM's hostname
   rocks list host alu-vm|perl -lane 'system "ssh $1 hostname $1" if /^(.*?):/'
   rocks list host alu-vm |perl -lane 'system qq|ssh $1 "echo HOSTNAME=$1 >> /etc/network"| if /^(.*?):/'

   rocks run host alu-vm 'systemctl stop cloud-init'
   rocks run host alu-vm command='rm -f /etc/yum.repos.d/*.repo'
   rocks run host alu-vm command='sed -i "s/gpgcheck=1/gpgcheck=0/" /etc/yum.conf'
   rocks run host alu-vm compute 'rm -f /etc/yum.repos.d/*'
   rocks list host alu-vm compute | perl -lane 'system "scp -q /tmp/mega.repo $1:/etc/yum.repos.d/" if /^(.*?):/'
   rocks run host alu-vm command='yum -y install patch puppet' &> /dev/null
   rocks run host compute alu-vm 'systemctl stop NetworkManager.service' &> /dev/null
   rocks run host compute alu-vm 'systemctl disable NetworkManager.service' &> /dev/null
   echo "Ok"
}

function set_aluvm_ntp() {

   echo -n "Configuring NTPd on ALUVM's: "
   rocks run host alu-vm compute 'echo nameserver 10.1.1.1 > /etc/resolv.conf' 
   rocks run host alu-vm compute 'yum clean all' 
   rocks run host alu-vm compute 'yum -y install ntp' 
   rocks run host alu-vm compute 'echo server 10.1.1.1 > /etc/ntp.conf' 
   rocks run host alu-vm compute 'timedatectl set-timezone UTC' 
   rocks run host alu-vm compute 'ntpdate 10.1.1.1' 
   rocks run host alu-vm compute 'systemctl enable ntpd' 
   rocks run host alu-vm compute 'systemctl start ntpd.service' 
   rocks list host alu-vm|perl -lane 'system "rsync -a /root/.ssh/ $1:/root/.ssh/" if /(.*?):/'
   rocks run host alu-vm 'yum -y install perl' &> /dev/null
   rocks run host alu-vm command="perl -pi -e 's/SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux"
   rocks run host alu-vm 'reboot'

   wait_for_boot alu-vm
   echo "Ok"
}

function set_aluvm_defroute() {

   echo "Updating Defroute for ALUVMs: "
   rocks run host alu-vm command='grep DEFROUTE /etc/sysconfig/network-scripts/ifcfg-eth0 || echo DEFROUTE=no >> /etc/sysconfig/network-scripts/ifcfg-eth0'
   echo "Ok"
}

function set_aluvm_ip() {

   lan=$(ifconfig br1|perl -lane 'print $1 if /addr:(.*?)\s.*?Mask.*?/' |cut -d'.' -f1-3)
   nm=$(ifconfig br1|perl -lane 'print $1 if /Mask:(.*?)$/')

   create_interface_config eth3 10.2.0.51 255.255.255.0 1500 os-mysql1
   create_interface_config eth1 $lan.15 $nm 1500 os-glance
   create_interface_config eth3 10.2.0.48 255.255.255.0 1500 os-glance
   create_interface_config eth1 $lan.11 $nm 1500 os-controller
   create_interface_config eth3 10.2.0.47 255.255.255.0 1500 os-controller
   create_interface_config eth2 $lan.16 $nm 1500 os-network
   create_interface_config eth3 10.2.0.43 255.255.255.0 1500 os-network
   create_interface_config eth1 $lan.14 $nm 1500 os-cinder
   create_interface_config eth3 10.2.0.44 255.255.255.0 1500 os-cinder
   create_interface_config eth3 10.2.0.52 255.255.255.0 1500 os-cinder

   gw=$(netstat -rn|grep ^0.0.0.0|awk '{print $2}')

   ssh os-glance "route delete default; route add default gw $gw"
   ssh os-controller "route delete default; route add default gw $gw"
   ssh os-network "route delete default; route add default gw $gw"
   ssh os-cinder "route delete default; route add default gw $gw"
}

function start_packstack() {

   echo "Starting Packstack: "
   perl -pi -e 's/10.1.20.151/10.1.20.51/g' /tmp/packstack-os-controller-icehouse.ga.txt
   perl -pi -e 's/10.1.20.150/10.1.20.51/g' /tmp/packstack-os-controller-icehouse.ga.txt
   perl -pi -e 's/MYSQL/MARIADB/g' /tmp/packstack-os-controller-icehouse.ga.txt
   perl -pi -e 's/CONFIG_MARIADB_INSTALL=n/CONFIG_MARIADB_INSTALL=y/g' /tmp/packstack-os-controller-icehouse.ga.txt

   python /export/apps/openstack/cinder/rbd_cinder_cfg.py -d

   rocks run host alu-vm compute 'systemctl stop ntpd.service'
   scp /tmp/packstack-os-controller-icehouse.ga.txt os-controller:
   ssh os-controller 'yum -y install openstack-packstack'
   rocks run host alu-vm compute 'yum clean all'
   ssh os-controller 'packstack --answer-file packstack-os-controller-icehouse.ga.txt'

   echo "Ok"

}

stop_ha
reset_ceph
backup_repo
get_rhel7
clean_repo
setup_el7
pxe_boot_computes
fix_grub_and_reboot
wait_for_boot compute
sync_juno_and_friends
create_juno_repo
mount_apps_share
install_python_ceph_puppet
add_public_storage_ips
create_storage_cluster
mount_ceph_fuse
reset_rocks_repo
start_management_vms
prepare_aluvms
set_aluvm_ntp
set_aluvm_defroute
set_aluvm_ip
start_packstack
