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

   echo "Preparing work space."
   rm -rf /export/build_iso/x86_64/
   mkdir -p /export/build_iso/x86_64/
   mount -o loop /export/rocks-2.4/iso/ALU-7.0.1.x86_64.disk1.iso /mnt/cdrom/
   echo "Copying in original ISO."
   rsync -a /mnt/cdrom/ /export/build_iso/x86_64/ 
   umount /mnt/cdrom/
}

function make_initrd() {

   echo -n "Preparing initrd: "
   cd /export/build_iso/x86_64/
   mkdir initrd
   cd initrd
   xz -dc /mnt/cdrom/isolinux/initrd.img | cpio -id &> /dev/null

   # Greg's site.attrs
   cp /root/stackiq/site.attrs.stackiq /export/build_iso/x86_64/initrd/tmp/site.attrs
   cp /root/stackiq/rolls.xml /export/build_iso/x86_64/initrd/tmp/rolls.xml
   
   cd /export/build_iso/x86_64/initrd && find . | cpio --quiet -c -o | xz --verbose -0 --format=lzma > ../isolinux/initrd.img 
   rm -rf initrd/
}

function make_iso() {

   echo "Creating ISO file"
   mkdir -p /var/www/html/iso/auto/$cluster/
   output="/var/www/html/iso/auto/$cluster/$cluster-fe-install.iso";
   cmd="mkisofs -V 'ALU' -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 6 -boot-info-table -r -T -f -input-charset utf-8 -m initrd -m alu-fe -o $output ." 

   cd /export/build_iso/x86_64 
   $cmd 
}

echo "Customizing Rocks ISO for: $cluster"
prep_workspace
make_initrd
make_iso
echo "Finished"
