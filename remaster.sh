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

   echo -n "Preparing work space: "
   rm -rf /export/build_iso/x86_64/
   mkdir -p /export/build_iso/x86_64/
   mount -o loop /export/iso/ALU-7.0.1.x86_64.disk1.iso /mnt/cdrom/
   echo "Ok"

   echo -n "Copying in original ISO: "
   rsync -a /mnt/cdrom/ /export/build_iso/x86_64/ 
   echo "Ok"
}

function make_initrd() {

   echo -n "Preparing initrd: "
   cd /export/build_iso/x86_64/
   mkdir initrd
   cd initrd
   xz -dc /mnt/cdrom/isolinux/initrd.img | cpio -id &> /dev/null
   umount /mnt/cdrom/

   # Some working site.attrs
   cp /root/stackiq/site.attrs.auto /export/build_iso/x86_64/initrd/tmp/site.attrs
   cp /root/stackiq/rolls.xml /export/build_iso/x86_64/initrd/tmp/rolls.xml
   
   # Repack
   cd /export/build_iso/x86_64/initrd 
   find . | cpio --quiet -c -o | xz -0 --format=lzma > ../isolinux/initrd.img  
   rm -rf /export/build_iso/x86_64/initrd/
   echo "Ok"
}

function make_iso() {

   echo -n "Creating ISO file: "
   mkdir -p /var/www/html/iso/auto/$cluster/
   output="/export/iso/$cluster-fe-install.iso";
   cmd="mkisofs -V 'ALU' -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 6 -boot-info-table -r -T -f -input-charset utf-8 -m initrd -m alu-fe -o $output ." 

   cd /export/build_iso/x86_64/
   $cmd &> /dev/null 
   du -sh $output 
}

echo "Customizing Rocks ISO for: $cluster"
prep_workspace
make_initrd
make_iso
echo "Finished"
