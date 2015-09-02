#!/usr/bin/perl
#
# Display information about connected clusters.

use strict;
use Getopt::Long;
use Term::ANSIColor;
use vars qw ( $list @alerts $acid $geoip $cloudos $vmcount $servers );

GetOptions( "list"      => \$list,
            "geoip"     => \$geoip,
            "acid"      => \$acid,
            "vmcount"   => \$vmcount,
            "cloudos"   => \$cloudos,
            "servers"   => \$servers,
            "alerts=s"  => \@alerts );

usage() unless (($list) or (@alerts) or ($vmcount) );

gen_hosts(); # Always update our host list.
get_alerts(@alerts) if (@alerts); 
get_list() if ($list);

sub gen_hosts() {

   my $conf = '/etc/openvpn/vpn_status.log';

   open FH, "> /etc/hosts" or die "Can't open hosts file.\n";
   print FH "127.0.0.1   centos-63 localhost localhost.localdomain localhost4 localhost4.localdomain4\n"
          . "::1         localhost localhost.localdomain localhost6 localhost6.localdomain6\n\n";

   for (`cat $conf`) {
      if (/^(\d.*?),(.*?),(.*?):/) {
         my ($local_ip, $hostname, $remote_ip) = ($1, $2, $3);
         print FH "$local_ip\t$hostname\n";
      }
   }

}

my ($totalvms, $totalpsy);

sub get_list() {

   my $conf = '/etc/openvpn/vpn_status.log';
   my ($count, $total);
   my @config = `cat $conf`;

   for ( @config ) {
      $total++ if (/^(\d.*?),(.*?),(.*?):/);
   }

   for ( @config ) {
      #next if /laptop/;
      if (/^(\d.*?),(.*?),(.*?):/) {
         my ($local_ip, $hostname, $remote_ip) = ($1, $2, $3);

         my $computes = get_computes($local_ip) if ($servers);
         my $country  = get_country($remote_ip) if ( $geoip );
	 my $guestvm  = get_vm_count($local_ip) if ($vmcount);
	 my $cversion = get_cloudos($local_ip)  if ($cloudos);

         $totalvms += $guestvm  if ($vmcount);
         $totalpsy += $computes if ($servers);

         if ($acid) {
            next unless ($hostname =~ /acid/) 
         }

         print "Cluster:\t$hostname\n"
	     . "Overlay:\t$local_ip\n";
             #. "Gateway:\t$remote_ip\n";
	 print "Servers:\t$computes\n" if ($servers);
	 print "GuestVM:\t$guestvm\n"  if ($vmcount);
	 print "CloudOS:\t$cversion\n" if ($cloudos);
	 print "Location:\t$country\n" if ($geoip);
	 print "\n";

         $count++
      }
   }

   if ($count) {
      print "There are a total of $count clusters online.\n";
      print "There are a total of $totalpsy physical systems online.\n" if ($servers);
      print "There are a total of $totalvms VM's running.\n" if ($vmcount);
      print "\n"; 
   } else {
      print "No clusters online.\n"
   }
}

sub usage() {

   die "\n   $0 manaage connected CloudBand clusters.\n\n"
     . "\t--list\t\t\tDisplay connected clusters.\n"
     . "\t--geoip\t\t\tDisplay physical location of the clusters.\n"
     . "\t--servers\t\tDisplay total number of physical systems in a cluster.\n"
     . "\t--vmcount\t\tDisplay total number of guest VM's running in a cluster.\n"
     . "\t--cloudos\t\tDisplay the CloudOS managing a cluster.\n"
     . "\t--alerts [hostname] \tDisplay cirtical Nagios alerts for a cluster.\n\n";

}

sub get_country() {

   my $ip = shift;
   my $url = "http://www.geobytes.com/IpLocator.htm?GetLocation&template=php3.txt&IpAddress=$ip";

   my ($country, $region);
   for (`GET "$url"`) {
      $country = $1 if /.*?iso3.*?content=\"(.*?)\".*?/;
      $region= $1 if /.*?region.*?content=\"(.*?)\".*?/;
   }

   return "$country, $region" if ($country);
   return undef;
}

sub get_computes() {

   my $ip = shift;
   my $url = "http://$ip/ganglia/";

   my @computes;
   for (`GET "$url"`) {
      push @computes, "$1\n" if (/(compute.*?local)/);
      push @computes, "$1\n" if (/(vm-manager.*?local)/);
      push @computes, "$1\n" if (/(Ganglia:: (.*?) Cluster Report.*?)/);

   }

   my @uniq = sort(uniq(@computes));
   return scalar(@uniq);

}

sub get_vm_count() {

   my $local_ip = shift;
   my $url = "http://$local_ip/nagios/cgi-bin//status.cgi?host=all";

   for (`GET -C nagiosadmin:nagiosadmin "$url"`) {
      #return $1 if (/OK: (.*?) VM&#39;s/)
      return $1 if (/OK.*?\s(.*?)\sVM.*?total/)
   }

   return 'undef'

}

sub uniq {
    return keys %{{ map { $_ => 1 } @_ }};
}

sub get_cloudos() {

   my $local_ip = shift;
   my $url      = "http://$local_ip/nagios/cgi-bin//status.cgi?host=all";
   for (`GET -C nagiosadmin:nagiosadmin "$url"`) {

      return 'CloudStack'      if /cloudstack/i;
      return 'OpenStack+Nuage' if /nuage/i;
      return 'OpenStack+OVS'   if /os-network/i;
   }

   return 'undef';

}

sub get_alerts() {

   my @clusters = @_;
   for my $cluster (@clusters) {
      my $local_ip = get_cluster_ip($cluster);
      my (@rows, $count);

      die "\nNo such cluster: $cluster\n\n" unless ($local_ip);

      my $len = length $cluster;
      $len = $len + 3;
      my $col = "$len.$len" . 's';
      my $valid_response;
   
      # Build a hash, which has a dangling array of services at the end.. $name->'CRITICAL'-> ($service, $service, $service)
      #print qq|GET -C nagiosadmin:nagiosadmin "http://$local_ip/nagios/cgi-bin//status.cgi?host=all&servicestatustypes=28"\n|;
      for (`GET -C nagiosadmin:nagiosadmin "http://$local_ip/nagios/cgi-bin//status.cgi?host=all&servicestatustypes=28"`) {
         $valid_response++ if /Produced by Nagios/; # Make sure we get something from Nagios.
         if (/statusBGCRITICAL.*?host=(.*?)&service=(.*?)\'.*?/) {
           print colored( sprintf("%-$col", "$cluster"), 'blue' );
           print colored( sprintf("%-20.20s", " $1"), 'green' );
           print colored( sprintf("%-20.20s", " $2"), 'red' ), "\n";
           $count++
         }
      }

      unless ( $valid_response ) {
         print "WARN: I didn't get a valid response from Nagios for $cluster.\n\n"; 
      } else {
         print colored( sprintf("%-$col", "$cluster"), 'blue' ) . ": No Alerts\n" unless ($count);
         print "\n";
      }
   }
}

sub get_alerts_old() {

   # Didn't like the output on this very much.

   my $cluster = shift;
   my $local_ip = get_cluster_ip($cluster);
   my %hosts;

   # Build a hash, which has a dangling array of services at the end.. $name->'CRITICAL'-> ($service, $service, $service)
   for (`GET -C nagiosadmin:nagiosadmin "http://$local_ip/nagios/cgi-bin//status.cgi?host=all&servicestatustypes=28"`) {
      push @{ $hosts{$1}{'CRITICAL'} }, $2 if (/statusBGCRITICAL.*?host=(.*?)&service=(.*?)\'.*?/);
   }

   print "\n";

   my $count;
   while ( my ($host, $ref) = each %hosts ) {
      print "$host: \n";
      for my $alert ( @{$ref->{'CRITICAL'}} ) {
         print "   Service: $alert\n";
      }
      print "\n";
      $count++
   }
   print "Nothing to see here. $cluster has no critical alerts.\n\n" if ($count == 0 );
}

sub get_cluster_ip() {

   # Given a hostname, return the overlay IP.
   my $cluster = shift;
   my $conf = '/etc/openvpn/vpn_status.log';

   for (`cat $conf`) {
      if (/^(\d.*?),(.*?),(.*?):/) {
         my ($local_ip, $hostname, $remote_ip) = ($1, $2, $3);
         return $local_ip if ($cluster eq $hostname);
      }
   }
}
