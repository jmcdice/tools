#!/usr/bin/env python
#
# This script will generate shell code which, when run on a rocks frontend
# will create kickstart profiles for each physical compute node in a cluster.
# It's executed post-install on a frontend.
# Joey <joseph.mcdonald@alcatel-lucent.com>

import re
import sys
import os.path
sys.path.append('/export/apps/common/python/ALU/common/')
from nodeconf import config
from optparse import OptionParser
from cluster_physical import FrontendNetwork
from cluster_physical import FrontendIlo

def get_static_ip(compute, network):

    if network == 'private':
        subnet = '10.1.255.'
    elif network == 'storage':
        subnet = '10.2.0.'
    start = 253

    vmm_regex = re.compile('vm-manager')
    if vmm_regex.match(compute):
        return subnet + str('254')

    rank = compute.split('-')[-1]

    oct = start - int(rank)
    ip = str(subnet) + str(oct)
    return ip

def create_compute_profile(compute, ilo, private_nic, private_ip, private_mac):

    rank = compute.split('-')[-1]
    vmm_regex = re.compile('vm-manager')
    com_regex = re.compile('compute')
    membership = ''

    if vmm_regex.match(compute):
        membership = 'VM\ Management\ Node'
    elif com_regex.match(compute):
        membership = 'Compute'

    fmt = '# Adding rocks profile for %s\n' % compute
    add = '/opt/rocks/bin/rocks add host {compute} cpus=24 rack=0 rank={rank} membership={membership}\n'
    fmt += add.format(compute=compute,rank=rank,membership=membership)
    fmt += "/opt/rocks/bin/rocks set host runaction %s action=os\n" % (compute)
    fmt += "/opt/rocks/bin/rocks set host installaction %s action=install\n" % (compute)
    fmt += "/opt/rocks/bin/rocks add host interface %s %s\n" % (compute, private_nic)
    fmt += "/opt/rocks/bin/rocks set host interface ip %s %s %s\n" % (compute, private_nic, private_ip)
    fmt += "/opt/rocks/bin/rocks set host interface name %s %s %s\n" % (compute, private_nic, compute)
    fmt += "/opt/rocks/bin/rocks set host interface mac %s %s %s\n" % (compute, private_nic, private_mac)
    fmt += "/opt/rocks/bin/rocks set host interface subnet %s %s private\n\n" % (compute, private_nic)
    return fmt


def create_fe_interface(iface_name, network, ip):

    fmt =  '# Adding commands to create %s on %s network: %s \n' % (iface_name, network, ip)
    fmt += 'mac=$(ifconfig %s | grep ether |awk \'{print $2}\')\n' % (iface_name)
    fmt += 'fe=$(rocks list host interface frontend|grep private | awk \'{print $7}\')\n'
    fmt += '/opt/rocks/bin/rocks add host interface frontend iface=%s\n' % (iface_name)
    fmt += '/opt/rocks/bin/rocks set host interface ip frontend iface=%s %s\n' % (iface_name, ip)
    fmt += '/opt/rocks/bin/rocks set host interface name frontend iface=%s $fe\n' % (iface_name)
    fmt += '/opt/rocks/bin/rocks set host interface mac frontend iface=%s $mac\n' % (iface_name)
    fmt += '/opt/rocks/bin/rocks set host interface subnet frontend iface=%s %s\n\n' % (iface_name, network)
    return fmt


# Pull in our option(s)
parser = OptionParser()
parser.add_option( "-c", "--cluster",
		   dest="cluster",
                   help="Read config from specified cluster",
		   metavar="FILE" )
(options, args) = parser.parse_args()

cluster = options.cluster
config_file = '/var/www/html/iso/auto/' + cluster + '/' + cluster + '-config.txt'

# An object containing all my config vars
nc = config( False, config_file )

# These things we know because the user entered them in the UI
hostname    = nc.get_property( 'HOSTNAME' )
ntp         = nc.get_property( 'NTP' )
hardware    = nc.get_property( 'HARDWARE' )
dnsserver   = nc.get_property( 'DNS' )
frontendip  = nc.get_property( 'IP' )
broadcast   = nc.get_property( 'BROADCAST' )
network     = nc.get_property( 'NETWORK' )
gateway     = nc.get_property( 'GATEWAY' )
netmask     = nc.get_property( 'NETMASK' )
cidr        = nc.get_property( 'CIDR' )
timezone    = nc.get_property( 'TIMEZONE' )
rootpw	    = nc.get_property( 'CRYPT' )
acid_ip     = nc.get_property( 'ACID_IP' )
private_nic = nc.get_interface('private')
oob_nic     = nc.get_interface('oob')
storage_nic = nc.get_interface('storage')
public_nic  = nc.get_interface('public')

# These things we'll have to pull dynamically
ilo_info = FrontendIlo(hostname)
username = ilo_info.username()
password = ilo_info.password()
ip = ilo_info.ip()

# The file we're going to pull and execute.
rocks_shell = '/var/www/html/iso/auto/' + cluster + '/rocks-compute-profile-1.txt'

# Open the file for writing
init = open(rocks_shell, 'w')

init.write('# Setup sshd\n')
init.write('perl -pi -e "s/GSSAPIAuthentication yes/GSSAPIAuthentication no/" /etc/ssh/sshd_config\n')
init.write('perl -pi -e "s/#UseDNS yes/UseDNS no/" /etc/ssh/sshd_config\n')
init.write('/bin/systemctl restart sshd.service\n\n')

init.write('# Create VMM appliance profile\n')
init.write('/opt/rocks/bin/rocks add appliance vm-manager graph=default membership="VM Management Node" node=compute\n')
init.write('/opt/rocks/bin/rocks set appliance attr vm-manager attr=managed value=yes\n\n')

init.write('# Adding Network: storage\n')
init.write('/opt/rocks/bin/rocks add network storage subnet=10.2.0.0 netmask=255.255.255.0\n')
init.write('/opt/rocks/bin/rocks set network mtu storage 9000\n')
init.write('/opt/rocks/bin/rocks set network servedns storage true\n\n')

init.write('# Adding Network: oob\n')
init.write('/opt/rocks/bin/rocks add network oob subnet=172.30.0.0 netmask=255.255.255.0\n')
init.write('/opt/rocks/bin/rocks set network servedns oob true\n\n')

init.write('# OVS Cluster: public MTU 9k\n')
init.write('/opt/rocks/bin/rocks set network mtu public 9000\n\n')

# Create OOB/Storage ifaces
init.write(create_fe_interface(storage_nic, 'storage', '10.2.0.1'))
init.write(create_fe_interface(oob_nic, 'oob', '172.20.0.1'))

n = FrontendIlo(cluster)
ilos = n.get_cluster_ilos()

result = {}
result['frontend'] = ilos.pop(0)
result['vm-manager-0-0'] = ilos.pop(0)

# Build my dic of ilo/host
for index,ip in enumerate(ilos):
    result['compute-0-' + str(index)] = ip

result.pop('frontend')
count = 254

for compute, ilo in result.iteritems():
    # compute, ilo, private_nic, private_ip, private_mac
    private_ip = get_static_ip(compute, 'private')
    object = FrontendNetwork(ilo, username, password)
    private_mac = object.get_private_mac()
    print "Generating profile for: %s (%s, %s, %s, %s)" % (compute, ilo, private_nic, private_ip, private_mac)
    init.write(create_compute_profile(compute, ilo, private_nic, private_ip, private_mac))
    count -= 1

# Look for custom hw config here.


init.write('# Apply the rules and restart services\n')
init.write('/opt/rocks/bin/rocks set host boot vm-manager compute action=install\n')
init.write('/opt/rocks/bin/rocks set host boot frontend action=os\n')
init.write('/opt/rocks/bin/rocks sync host config localhost\n')
init.write('/opt/rocks/bin/rocks sync host network localhost\n')

init.write('/bin/systemctl restart  dhcpd.service\n')
init.write('/bin/systemctl restart  xinetd.service\n')
init.write('/bin/systemctl restart  named.service\n')
init.close()

# Computes should image now and when they're done, this next half of rocks stuff can be run.
rocks_shell = '/var/www/html/iso/auto/' + cluster + '/rocks-compute-profile-2.txt'
# Open the file for writing
init = open(rocks_shell, 'w')

# Set the public interface
vmm_public_net = 'rocks set host interface subnet compute vm-manager iface={public_nic} subnet=public\n\n'
init.write('# Adding public interface to network for VMM/compute.\n')
init.write(vmm_public_net.format(public_nic=public_nic))

# Set the VMM storage interface
vmm_storage_net = 'rocks set host interface subnet compute vm-manager iface={storage_nic} subnet=storage\n\n'
init.write('# Adding storage interface to network for VMM/compute.\n')
init.write(vmm_storage_net.format(storage_nic=storage_nic))

# Create a storage IP for VMM and compute nodes
for compute, ilo in result.iteritems():
    storage_ip = get_static_ip(compute, 'storage')
    init.write('# Adding Storage IP and bridge config for: %s\n' % (compute))
    init.write('/opt/rocks/bin/rocks set host interface ip %s iface=%s %s\n' % (compute, storage_nic, storage_ip))
    init.write('/opt/rocks/bin/rocks set host interface name %s iface=%s %s\n' % (compute, storage_nic, compute))
    init.write('/opt/rocks/bin/rocks add host bridge %s iface=%s name=br3 network=storage\n\n' % (compute, storage_nic))

# Create the VMM bridges
vmm_private_br = '/opt/rocks/bin/rocks add host bridge vm-manager iface={private_nic} name=br0 network=private\n'
vmm_public_br  = '/opt/rocks/bin/rocks add host bridge vm-manager iface={public_nic} name=br1 network=public\n\n'

init.write('# Adding interface bridges for VMM.\n')
init.write(vmm_private_br.format(private_nic=private_nic))
init.write(vmm_public_br.format(public_nic=public_nic))

# Create the frontend network bridges
fe_private_br ='/opt/rocks/bin/rocks add host bridge frontend iface={private_nic} name=br0 network=private\n'
fe_public_br  ='/opt/rocks/bin/rocks add host bridge frontend iface={public_nic} name=br1 network=public\n'
fe_storage_br ='/opt/rocks/bin/rocks add host bridge frontend iface={storage_nic} name=br3 network=storage\n\n'

init.write('# Adding interface bridges for frontend.\n')
init.write(fe_private_br.format(private_nic=private_nic))
init.write(fe_public_br.format(public_nic=public_nic))
init.write(fe_storage_br.format(storage_nic=storage_nic))

# Add some basic firewall rules
fw_private_if = "/opt/rocks/bin/rocks add appliance firewall compute action=ACCEPT chain=INPUT network=all protocol=all service=all flags='-i {private_nic}'\n"
fw_storage_if = "/opt/rocks/bin/rocks add appliance firewall compute action=ACCEPT chain=INPUT network=all protocol=all service=all flags='-i {storage_nic}'\n"

init.write('# Basic Firewall Rules.\n')
init.write("/opt/rocks/bin/rocks add appliance firewall vm-manager compute frontend action=ACCEPT chain=INPUT network=all protocol=all service=all flags='-i br0'\n")
init.write("/opt/rocks/bin/rocks add appliance firewall vm-manager compute frontend action=ACCEPT chain=INPUT network=all protocol=all service=all flags='-i br3'\n")
init.write(fw_private_if.format(private_nic=private_nic))
init.write(fw_storage_if.format(storage_nic=storage_nic))
init.write('/opt/rocks/bin/rocks add firewall chain=FORWARD action=ACCEPT network=all service=all protocol=all\n')
init.write('/opt/rocks/bin/rocks add host firewall frontend compute vm-manager chain=INPUT action=ACCEPT network=storage service=all protocol=all\n')
init.write('/opt/rocks/bin/rocks add host firewall frontend compute vm-manager chain=INPUT action=ACCEPT network=private service=all protocol=all\n')
init.write('/opt/rocks/bin/rocks add host firewall frontend compute vm-manager chain=INPUT action=ACCEPT network=oob service=all protocol=all\n\n')
# Test this first..
#init.write("/opt/rocks/bin/rocks add host firewall frontend compute vm-manager chain=INPUT action=REJECT network=storage service=all protocol=all flags='-d 10.2.0.0/24 -i br0'")

init.write('# Apply the rules and restart services\n')
init.write('/opt/rocks/bin/rocks set host boot vm-manager compute action=install\n')
init.write('/opt/rocks/bin/rocks set host boot frontend action=os\n')

init.write('/opt/rocks/bin/rocks sync host config localhost\n')
init.write('/opt/rocks/bin/rocks sync host network localhost restart=no\n')
init.write("perl -pi -e 's/NAME/DEVICE/' /etc/sysconfig/network-scripts/ifcfg-*\n\n")
init.write('/bin/systemctl restart network.service\n')
init.write('sleep 5\n')
init.write('/bin/systemctl restart iptables.service\n')
init.write('/bin/systemctl restart dhcpd.service\n')
init.write('/bin/systemctl restart xinetd.service\n')
init.write('/bin/systemctl restart named.service\n\n')

init.write('/opt/rocks/bin/rocks sync host config\n')
init.write('/opt/rocks/bin/rocks sync host network vm-manager compute restart=no\n')
init.write('sleep 3\n')
init.write('/opt/rocks/bin/rocks run host compute vm-manager "perl -pi -e \'s/NAME/DEVICE/\' /etc/sysconfig/network-scripts/ifcfg-*"\n')
init.write('sleep 3\n')
init.write('/opt/rocks/bin/rocks run host compute vm-manager \'/bin/systemctl restart network.service\'\n\n')

init.close()
