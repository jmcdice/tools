#!/usr/bin/perl
#
# Look in OVS and see if we have any orphaned ports.
# Defined as, ports configured in OVS by neutron, that no longer exist in neutron.
# Run me from a rocks frontend.
# Joey <jmcdice@gmail.com>
# 

use strict;

my %aports; # Active ports in Neutron

for ( get_neutron_ports() ) {
   $aports{$_}++
}

for my $dport ( get_deployed_ports() ) {

   if ( $aports{$dport} ) {
      print "$dport: Ok\n";
   } else {
      print "$dport: Fail!\n"
   }
}

sub get_deployed_ports() {

   my @ports;
   for ( `rocks run host compute 'ovs-vsctl show|grep Port | grep qvo'` ) {
      push @ports, $1 if (/(qvo.*?)\"/);
   }
   return @ports;
}

sub get_neutron_ports() {

   my @neutron_ports = `ssh os-controller 'neutron port-list'`;
   my @ovs_ports;

   for (@neutron_ports) {
      my $qvo = $1 if /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/;
      next unless $qvo; 
   
      # If this port is bound to os-network, then it's the DHCP interface and we should ignore it.
      my $dhcp_if;
      for ( `ssh os-controller 'neutron port-show $qvo'` ) {
         $dhcp_if++ if /os-network.local/
      }
      next if ( $dhcp_if );
   
      # neutron L3 agent creates ports in OVS, like this:
      # c0a830ee-f132-4ca4-ac18-b3f8c8219211 = 'qvoc0a830ee-f1'
      my $port = "qvo" . substr( $qvo, 0, 11 );
   
      # Return a list of ports we need to investigate.
      push @ovs_ports, $port;
   }
   return @ovs_ports;
}
