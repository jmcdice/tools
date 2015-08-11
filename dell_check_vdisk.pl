#!/usr/bin/perl
#
# Setup the virtual disks/raid controller on a Dell R730 for 
# node deployment.
#
# Joey <joseph.mcdonald@alcatel-lucent.com>

my $cluster = 'dell-30.tlv1.cloud-band.com';
my $drac = '/opt/dell/srvadmin/bin/idracadm7';
my $need_sleep = '';

my $user = `head -1 /var/www/html/iso/auto/$cluster/ilo_creds.txt`;
my $pass = `tail -1 /var/www/html/iso/auto/$cluster/ilo_creds.txt`;
chomp ($user, $pass);

sub delete_vdisks() {

   print "Wiping virtual disk configuration from $cluster.\n";

   for my $ip (`cat /var/www/html/iso/auto/$cluster/ilos.txt`) {
   
      $ip =~ tr/A-Za-z0-9\.//cd;
      chomp $ip;
   
      my @disks = `$drac -r $ip -u $user -p $pass raid get vdisks -o -p DeviceDescription,Size,MediaType`;
      print "Checking: $ip\n";
   
      # Delete virtual disks
      if ( grep( /No virtual disks/, @disks) ) {
        print "$ip: No virtual disks.\n\n";
        next;
      }
      $need_sleep++;
   
      for (@disks) {
          if (/^(Disk.Vir.*?)\s.*?$/) {
             my $vi = $1;
             print "Deleting: $vi\n";
             my @del = `$drac -r $ip -u $user -p $pass raid deletevd:$vi`;
          }
      }
   
      # This section commits the changes and power-cycles the system(s).
      print "Resetting controller config.\n";
      my @reset = `$drac -r $ip -u hp -p password raid resetconfig:RAID.Integrated.1-1`;
      print "Creating a jobqueue.\n";
      my @jobqueue = `$drac -r $ip -u hp -p password jobqueue create RAID.Integrated.1-1`;
      print "Rebooting: $ip\n\n";
      my @reset = `$drac -r $ip -u hp -p password serveraction powercycle`;
   }
   
   sleep 200 if ($need_sleep);
   print "Done.\n";
}

sub identify_virtual_disks() {

   print "Identifying virtual disk configuration for $cluster.\n";

   for my $ip (`cat /var/www/html/iso/auto/$cluster/ilos.txt`) {

      $ip =~ tr/A-Za-z0-9\.//cd;
      chomp $ip;

      my @disks = `$drac -r $ip -u $user -p $pass raid get vdisks -o -p DeviceDescription,Size,MediaType`;
      print "Checking: $ip\n";

      for (@disks) {
          print "$1 "  if (/(Virtual Disk .*?)\son/);
          print "$1 "  if (/Size.*?=\s(.*?GB)\s/);
          print "$1\n" if (/MediaType.*?=\s(.*?)$/);
      }
      print "\n";
  }
}


sub identify_pdisks() {

   for my $ip (`cat /var/www/html/iso/auto/$cluster/ilos.txt`) {

      $ip =~ tr/A-Za-z0-9\.//cd;
      chomp $ip;

      print "Checking: $ip\n";
      my @disks = `$drac -r $ip -u $user -p $pass raid get pdisks -o -p DeviceDescription,Size,MediaType`;
      for (@disks) {
         print "Disk: $1 " if (/(Disk .*?) in Back.*?/);
         print "$1 " if (/= (.*?)\sGB/);
         print "$1\n"  if (/MediaType.*?=\s(.*?)\s.*?$/);
      }
      print "\n";
   }
}

sub create_virtual_disks() {

   print "Creating Virtual Disks.\n";
   for my $ip (`cat /var/www/html/iso/auto/$cluster/ilos.txt`) {

      $ip =~ tr/A-Za-z0-9\.//cd;
      chomp $ip;


      # First pair of SSD's
      my $pair1 = "$drac -r $ip -u $user -p $pass " 
      . "raid createvd:RAID.Integrated.1-1 -rl r1 -wp wb -rp nra -ss 64k -pdkey:"
      . "Disk.Bay.0:Enclosure.Internal.0-1:RAID.Integrated.1-1,"
      . "Disk.Bay.1:Enclosure.Internal.0-1:RAID.Integrated.1-1";

      # Second pair of SSD's
      my $pair2 = "$drac -r $ip -u $user -p $pass " 
      . "raid createvd:RAID.Integrated.1-1 -rl r1 -wp wb -rp nra -ss 64k -pdkey:"
      . "Disk.Bay.2:Enclosure.Internal.0-1:RAID.Integrated.1-1,"
      . "Disk.Bay.3:Enclosure.Internal.0-1:RAID.Integrated.1-1";

      print "Creating RAID 1 (0,1)\n";
      my $raid1_1 = `$pair1`;
      print "Creating RAID 1 (2,3)\n";
      my $raid1_2 = `$pair2`;

      # Add sata's get raid-0
      for (4 .. 9) {
         my $raid0 = "$drac -r $ip -u $user -p $pass "
         . "raid createvd:RAID.Integrated.1-1 -rl r0 -pdkey:"
         . "Disk.Bay.$_:Enclosure.Internal.0-1:RAID.Integrated.1-1";

         print "Creating RAID 0 ($_)\n";
         my $create0 = `$raid0`;
      }

      for (0 .. 9) {
         my $init = "$drac -r $ip -u $user -p $pass "
         . "raid init:Disk.Virtual.$_:RAID.Integrated.1-1";
         my @go = `$init`; 
      }

      print "Creating job queue.\n";
      my $jobqueue = `$drac -r $ip -u $user -p $pass jobqueue create RAID.Integrated.1-1`;

      my $vdisks = "$drac -r $ip -u $user -p $pass "
         . "raid get vdisks -o -p DeviceDescription,Size,MediaType";
         #system "$vdisks";

      print "Rebooting: $ip\n\n";
      my $reboot = `$drac -r $ip -u $user -p $pass serveraction powercycle`;
   }
   sleep 300;
}

delete_vdisks();
#identify_pdisks();
create_virtual_disks();
identify_virtual_disks();
