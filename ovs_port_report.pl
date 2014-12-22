#!/usr/bin/perl
#
# Look in OVS and see if we have any orphaned ports.
# Orphans are ports configured in OVS by neutron, that no longer exist in neutron.
# Run me from a rocks frontend.
# Joey <jmcdice@gmail.com>

use strict;
use Getopt::Long;
use vars qw( $debug );

GetOptions( "debug" => \$debug );
my %aports; # Active ports in Neutron
my $fail;

for ( get_neutron_ports() ) { $aports{$_}++ }

for my $dport ( get_deployed_ports() ) {
   if ( $aports{$dport} ) {
      print "$dport: Ok\n" if ($debug);
   } else {
      print "CRIT: $dport\n";
      $fail++
   }
}

exit 2 if ( $fail ); # We detected a non-valid port.
exit 0; # All is well

sub get_deployed_ports() {
   my @ports;
   for ( `rocks run host compute 'ovs-vsctl show|grep Port | grep qvo'` ) {
      push @ports, $1 if (/(qvo.*?)\"/);
   }
   return @ports;
}

sub get_neutron_ports() {

   # Make a list of ports which exist in Neutron.
   my ($user, $pass, $host, $db);
   my @ovs_ports;

   # Take the mysql creds dynamically. Cool.
   for ( `ssh os-network 'grep mysql /etc/neutron/neutron.conf|grep ^connection'` ) {
      ($user, $pass, $host, $db) = ($1, $2, $3, $4) if (/mysql:\/\/(.*?):(.*?)\@(.*?)\/(.*?)$/);
   }

   my $cmd = "mysql -u $user -p$pass -h $host $db";
   my $query = "select id from ports where device_owner not like 'network:dhcp'";

   for (`$cmd -e "$query"`) {
      next unless /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/;
      my $port = "qvo" . substr( $_, 0, 11 );
      push @ovs_ports, $port;
   }
   return @ovs_ports;
}

