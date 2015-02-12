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

function make_squashfs() {

   # Extract the file system in squashfs.img to disk
   echo -n "Preparing squashfs filesystem: "
   cd /export/build_iso/x86_64/
   rpm -q squashfs-tools &> /dev/null || yum -y install squashfs-tools
   cd /export/build_iso/x86_64/
   mount LiveOS/squashfs.img /mnt/cdrom/ -o loop -t squashfs
   mkdir squashfs
   rsync -a /mnt/cdrom/ squashfs/
   umount /mnt/cdrom/
   rm LiveOS/squashfs.img

   mkdir rootfs
   mount squashfs/LiveOS/rootfs.img rootfs/ -o loop

   # Some working site.attrs
   cp /root/stackiq/site.attrs.auto rootfs/tmp/site.attrs
   cp /root/stackiq/rolls.xml rootfs/tmp/rolls.xml

   umount /export/build_iso/x86_64/rootfs/

   # Rebundle file system into squashfs.img
   mksquashfs /export/build_iso/x86_64/squashfs/LiveOS /export/build_iso/x86_64/LiveOS/squashfs.img -keep-as-directory 

   rm -rf rootfs squashfs
   umount /mnt/cdrom/
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
make_squashfs
make_iso
echo "Finished"
