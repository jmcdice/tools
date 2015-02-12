#!/bin/sh
#
# Test script to remaster a rocks ISO.
# Joey <joseph.mcdonald@alcatel-lucent.com>

cluster=$1
if [ -z $cluster ]
then
   echo "$0 <cluster_name>"
   exit 255
fi

function prep_workspace() {

   # Copy the contents of the StackIQ ISO to disk
   echo -n "Preparing work space: "
   test -d /mnt/cdrom || mkdir -p /mnt/cdrom/
   test -d /mnt/liveos || mkdir -p /mnt/liveos/

   rm -rf /export/build_iso/x86_64/
   mkdir -p /export/build_iso/x86_64/
   mount -o loop /export/iso/ALU-7.0.1.x86_64.disk1.iso /mnt/cdrom/ &> /dev/null
   echo "Ok"

   echo -n "Copying in original ISO: "
   rsync -a /mnt/cdrom/ /export/build_iso/x86_64/ 
   umount /mnt/cdrom/
   echo "Ok"
}

function make_lightsout() {

   cd /export/build_iso/x86_64/ 
   echo "%pre" >> ks.cfg 

   echo "cat > /tmp/site.attrs << 'EOF'" >> ks.cfg

   cat /root/stackiq/site.attrs.auto >> ks.cfg
   echo "EOF" >> ks.cfg 

   echo "cat > /tmp/rolls.xml << 'EOF'" >> ks.cfg
   cat /root/stackiq/rolls.xml >> ks.cfg
   echo "EOF" >> ks.cfg 
   echo "%end" >> ks.cfg
} 


function make_iso() {

   echo -n "Creating ISO file: "

   output="/export/iso/$cluster-fe-install.iso";
   cmd="mkisofs -o $output \
      -J -r -hide-rr-moved -hide-joliet-trans-tbl -V ALU \
      -b isolinux/isolinux.bin -c isolinux/boot.cat \
      -no-emul-boot -boot-load-size 4 -boot-info-table \
      /export/build_iso/x86_64/"

   cd /export/build_iso/x86_64/
   $cmd 
   sleep 3
   du -sh $output 
}

function check_release() {

   grep -q 'release 7' /etc/redhat-release 
   if [ $? -ne 0 ]; then
      echo "ERROR: You need EL7 to run this."
      exit 255
   fi
}

check_release
echo "Customizing Rocks ISO for: $cluster"
prep_workspace
make_lightsout
make_iso
echo "Finished"
