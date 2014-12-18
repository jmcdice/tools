#!/usr/bin/perl
# Neutron port report. 
# Tell me how many ports there are in neutron that aren't associated with a VM.
# Joey <jmcdice@gmail.com>

use strict;
my @ports = `neutron port-list -c id -c fixed_ips`;
my (@ips, @mess, @orphans, %totals, $port_total);

for my $ip (`neutron port-list -c fixed_ips|grep subnet | awk '{print \$5}'`) {
   chomp $ip;
   $ip =~ s/\"|\}//g;
   push @mess, $ip;
   $port_total++
}

@ips = uniq(@mess);
my @nova = `nova list --all-tenants`;

for my $ip (@ips) {
   for (@nova) {
      if (/\b$ip\b/) {
         $totals{$ip}++
      }
   }
}

for my $ip (@ips) {
   unless ( $totals{$ip} ) {
      for (@ports) {
         push @orphans, $_ if /\b$ip\b/
      }
   }
}

my $count = scalar @orphans;
print "There are $count orphaned neutron ports from a total of $port_total ports.\n";

sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}


