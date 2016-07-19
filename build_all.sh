#!/usr/bin/bash
#
# Create the overcloud images with our customizations and deploy the overcloud.
#
# Yoshi <yossi.ovadia@nokia.com>
# Joy!  <joey.mcdonald@nokia.com>

set -x

source /home/stack/temp_images/my_export

function build_images() {

   echo -n "Cleaning up old image files: "
   cd ~/temp_images \
      sudo cd /home/stack/temp_images; \
      rm -rf deploy-ramdisk-ironic.* dib* \
      ironic-python-agent.* overcloud-full.* 
      *.log fedora-user.qcow2
   echo "Ok"

   # Time saver if you need only overcloud-full
   # openstack overcloud image build --type overcloud-full

   time openstack overcloud image build --all \
      --builder-extra-args cbis 2>&1 | tee openstack_image_build.log

   echo -n "Copying images into place: "
   sudo cp ironic-python-agent.initramfs ~/images/ironic-python-agent.initramfs
   sudo cp ironic-python-agent.kernel ~/images/ironic-python-agent.kernel
   sudo cp overcloud-full.* ~/images/
   echo "Ok"
}

function upload_images() {

   echo -n "Uploading images to glance: "
   . ~/stackrc; 
   cd /home/stack/images && openstack overcloud image upload --update-existing
   echo "Ok"
}

function nova_boot() {

   # If you rebuild the ramdisk, Ironic needs to know about it, so just always run it.
   openstack baremetal configure boot
   sleep 3

   imageid=$(glance image-list|grep 'overcloud-full '|awk '{print $2}')
   networkid=$(neutron net-list|grep ctlplane|awk '{print $2}')
   nova_boot="nova boot --image=$imageid --flavor=baremetal --key sun-key --nic net-id=$networkid install-test-01"

   $nova_boot
   sleep 5
   ipmi=$(ironic node-show $(ironic node-list |egrep 'wait|deploy' | awk '{print $2}')|perl -lane 'print $1 if (/ipmi_address.*?u'\''(.*?)'\''/)')
   echo "Deploying on IPMI: $ipmi"
}

function delete_all_glance_images() {

   glance image-list|grep active | perl -lane 'system "glance image-delete @F[1]"'
}

function stack_delete() {

   nova list | grep install-test-01 | perl -lane 'system "nova delete @F[1]"'

   heat stack-list | grep -q overcloud
   if [ $? == 0 ]; then
      echo 'y' | heat stack-delete overcloud
      sleep 5
      echo -n "Waiting for stack-delete: "
      for i in {1..30}; do

         # If we get here, stack-delete again and it should work
         heat stack-list|grep -q "DELETE_FAILED"
         if [ $? == 0 ]; then
            echo 'y' | heat stack-delete overcloud
            sleep 3
         fi

         heat stack-list|grep -q overcloud
         if [ $? == 0 ]; then
            sleep 3
         else
            echo "Ok"
            return
         fi
      done

      # If we get here, it just won't delete.
      echo "Failed to delete overcloud stack. Manual intervention needed."
      exit 255
   fi
}

function delete_ironic_nodes() {

   echo -n "Deleting existing nodes in ironic: "
   ironic node-list | grep False | perl -lane 'system "ironic node-set-provision-state @F[1] deleted &> /dev/null"'
   ironic node-list | awk '/False/ { system ("ironic node-delete "$2) }'
   echo "Ok"
}

function start_introspection() {

   # introspection
   openstack baremetal import --json ~/instackenv.json
   openstack baremetal introspection bulk start

   # Trying to nova boot here returns an error in some cases, not sure why yet.
   sleep 10
   openstack baremetal configure boot
}


function overcloud_deploy() {


   cd ~/templates && openstack overcloud deploy --templates --ntp-server 10.39.255.232 \
         --control-scale 1 --compute-scale 3 --neutron-tunnel-types vxlan \
         --neutron-network-type vxlan -e my_network.yaml
}

stack_delete
delete_all_glance_images
delete_ironic_nodes
build_images
upload_images
start_introspection
nova_boot
# overcloud_deploy
