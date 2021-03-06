#/bin/sh
# Run automated, builds.
# Joey <joseph.mcdonald@alcatel-lucent.com>
#
# Run two builds a day from cron, CBnode-3.0 and dev
# 00 12 * * * /bin/sh /root/update.sh CBnode-3.0
# 00 00 * * * /bin/sh /root/update.sh dev

version=dev

if [ -z "$version" ]; then
   echo "Need a version to build."
   exit
fi

cluster='node-2.bldr.cloud-band.com'
fe='192.168.242.10'
gw='192.168.242.1'
fe_ilo='192.168.240.6'
acid='192.168.240.201'

function clean_up() {
   rm -rf /var/www/html/iso/$cluster/
   rm -rf /export/build_iso/x86_64/isolinux/isolinux.cfg
}

function create_iso() {

   # Create the ISO
   /export/ci/iso/hands_off_remaster.pl --public_hostname 'node-2.bldr.cloud-band.com' \
      --public_ip '192.168.242.10' --public_netmask '255.255.255.0' --public_vip '192.168.242.5' \
      --public_vip_radosgw '192.168.242.9' --public_vmm_ip '192.168.242.20' --public_vmm2_ip '192.168.242.21' \
      --public_gw '192.168.242.1' --public_6gw 'fd75:4e2a:8f01:aff5::1' --public_ip6subnet 'fd75:4e2a:8f01:aff5::/64' \
      --public_ntp '192.168.240.201' --public_dns '8.8.8.8' --timezone 'UTC' --rootpw ''password1'' --count '1' \
      --ip4mode '1' --ip6mode '1' --cloudplatform 'openstack-ovs' --ilo_username 'hp' --ilo_password 'password' \
      --ilo_rocks_ip '192.168.240.6' --pub_nagios 'true' --c7knics '' --mojo '1' --nagiosemail 'nobody@cloud-band.com' \
      --nagiosemailsmtp 'smtp.cloud-band.com' --num_of_vmm '2' --public_compute0 '192.168.242.25' --public_net_mtu '1500' \
      --public_net_tunnel_hdr '0' --public_bond '0' --public_bond_mon 'miimon=100' --pristo_bond '0' \
      --pristo_bond_mon 'miimon=100' --sriov '0' --num_of_sriov_vfs '0' --cbdeploy 1 --cbfe_ip  192.168.242.12

   echo $cluster > /var/www/html/iso/run/ci-build.txt
}

function install_license() {
   # Install the license file
   cp /root/stackiq-license/stackiq-license-node-2.bldr.cloud-band.com-6.6-1.x86_64.rpm /var/www/html/iso/auto/$cluster/
}

function start_build() {
   # Start the build
   cd /export/ci/tools/
   rm -f /var/www/html/iso/run/ci-build.txt
   /bin/sh /export/ci/tools/run_build_hands_off.sh node-2.bldr.cloud-band.com verbose &
}

function add_ipmi() {

   echo "192.168.240.6" >  /tmp/$cluster-ilos.txt
   echo "192.168.240.7" >> /tmp/$cluster-ilos.txt
   echo "192.168.240.8" >> /tmp/$cluster-ilos.txt
   echo "192.168.240.9" >> /tmp/$cluster-ilos.txt
}

function powerdown() {
   # Powerdown all the hosts in a cluster.
   for ip in $(cat /var/www/html/iso/auto/$cluster/ilos.txt| tr -dc '[0-9][:punct:],\n'); do
      until ipmitool -I lanplus -U hp -P password -H $ip chassis power off; do sleep 5; done
   done
}

function checkout() {

  branch=$1
  cd /export/
  rm -rf apps build_iso ci install iso rocks-*
  cd /root/

  REPOBRANCH=$branch CBNVERSION=rocks-3.0 GITREPOURL=ssh://git@stash:7999/cnode/cloudnode.git ./acid-bootstrap.sh
  cp -f /root/post-install-smoketest.sh /export/rocks-3.0/apps/unittest/tests/post-install-smoketest.sh
}

function kill_bill(){ 

  # Kill any existing build.
  perl /export/rocks-3.0/ci/tools/kill_bill.pl &> /dev/null
  rm -f /var/www/html/iso/build.log
  rm -f /var/www/html/iso/run/ci-build.txt
}

#kill_bill
#checkout $version
clean_up
add_ipmi
powerdown 
create_iso
start_build
