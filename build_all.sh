set -x

source /home/stack/temp_images/my_export

function build_images() {

   cd ~/temp_images \
      sudo cd /home/stack/temp_images; \
      rm -rf deploy-ramdisk-ironic.* dib* \
      ironic-python-agent.* overcloud-full.* 
      *.log fedora-user.qcow2

   time openstack overcloud image build --all \
      --builder-extra-args cbis 2>&1 | tee openstack_image_build.log

   sudo cp ironic-python-agent.initramfs ~/images/ironic-python-agent.initramfs
   sudo cp ironic-python-agent.kernel ~/images/ironic-python-agent.kernel
   sudo cp overcloud-full.* ~/images/
}

function upload_images() {
   . ~/stackrc; 
   cd /home/stack/images && openstack overcloud image upload --update-existing
   openstack baremetal configure boot 
}

function nova_boot() {
   imageid=$(glance image-list|grep 'overcloud-full '|awk '{print $2}')
   networkid=$(neutron net-list|grep ctlplane|awk '{print $2}')
   nova_boot="nova boot --image=$imageid --flavor=baremetal --key admin-key --nic net-id=$networkid install-test-01"
   $nova_boot
}

function delete_all_glance_images() {

   glance image-list|grep active | perl -lane 'system "glance image-delete @F[1]"'
}

function stack_delete() {
   heat stack-list | grep -q overcloud
   if [ $? == 0 ]; then
      echo 'y' | heat stack-delete overcloud
      sleep 5
      echo -n "Waiting for stack-delete: "
      for i in {1..30}; do

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
   ironic node-list | perl -lane 'system "ironic node-set-provision-state @F[1] delete"'
   ironic node-list | awk '/False/ { system ("ironic node-delete "$2) }'
}

function start_introspection() {

   # introspection
   openstack baremetal import --json ~/instackenv.json
   openstack baremetal configure boot
   openstack baremetal introspection bulk start
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
start_introspection
upload_images
nova_boot
# overcloud_deploy
