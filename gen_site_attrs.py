#!/usr/bin/env python
#
# Generate a site.attrs file for rocks 7
# Joey <joseph.mcdonald@alcatel-lucent.com>

import sys
import os.path
sys.path.append('/export/apps/common/python/ALU/common/')
from nodeconf import config
from optparse import OptionParser
from cluster_physical import FrontendNetwork
from cluster_physical import FrontendIlo

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
hostname   = nc.get_property( 'HOSTNAME' )
ntp        = nc.get_property( 'NTP' )
hardware   = nc.get_property( 'HARDWARE' )
dnsserver  = nc.get_property( 'DNS' )
frontendip = nc.get_property( 'IP' )
broadcast  = nc.get_property( 'BROADCAST' )
network    = nc.get_property( 'NETWORK' )
gateway    = nc.get_property( 'GATEWAY' )
netmask    = nc.get_property( 'NETMASK' )
cidr       = nc.get_property( 'CIDR' )
timezone   = nc.get_property( 'TIMEZONE' )
rootpw	   = nc.get_property( 'CRYPT' )
acid_ip    = nc.get_property( 'ACID_IP' )
private_nic = nc.get_interface('private')
public_nic  = nc.get_interface('public')

# These things we'll have to pull dynamically
ilo_info = FrontendIlo(hostname)
username = ilo_info.username()
password = ilo_info.password()
ip = ilo_info.ip()

object = FrontendNetwork(ip, username, password)
private_mac = object.get_private_mac()
public_mac  = object.get_public_mac(hardware)

print "url --url file:///mnt/cdrom"
print "lang en_US"
print "keyboard us"
print "install"
print "%pre"
print "cat > /tmp/site.attrs << 'EOF'"

print "HttpConf:/etc/httpd/conf"
print "HttpConfigDirExt:/etc/httpd/conf.d"
print "HttpRoot:/var/www/html"
print "Info_CertificateCountry:US"
print "Info_CertificateLocality:Boulder"
print "Info_CertificateOrganization:Alcatel Lucent"
print "Info_CertificateState:Colorado"
print "Info_ClusterContact:node-team-dev@alcatel-lucent.com"
print "Info_ClusterLatlong:N32.87 W117.22"
print "Info_ClusterName:" + hostname
print "Info_ClusterURL:http://" + hostname + "/"
print "Kickstart_DistroDir:/export/rocks"
print "Kickstart_Keyboard:us"
print "Kickstart_Lang:en_US"
print "Kickstart_Langsupport:en_US"
print "Kickstart_PrivateAddress:10.1.1.1"
print "Kickstart_PrivateBroadcast:10.1.255.255"
print "Kickstart_PrivateDNSDomain:local"
print "Kickstart_PrivateDNSServers:10.1.1.1"
print "Kickstart_PrivateDjangoRootPassword:" + rootpw
print "Kickstart_PrivateEthernet:" + private_mac
print "Kickstart_PrivateGateway:10.1.1.1"
print "Kickstart_PrivateHostname:" + hostname.split('.', 1)[0]
print "Kickstart_PrivateInterface:" + private_nic
print "Kickstart_PrivateKickstartCGI:sbin/kickstart.cgi"
print "Kickstart_PrivateKickstartHost:10.1.1.1"
print "Kickstart_PrivateMD5RootPassword:" + rootpw
print "Kickstart_PrivateNTPHost:10.1.1.1"
print "Kickstart_PrivateNetmask:255.255.0.0"
print "Kickstart_PrivateNetmaskCIDR:16"
print "Kickstart_PrivateNetwork:10.1.0.0"
print "Kickstart_PrivatePortableRootPassword:" + rootpw
print "Kickstart_PrivateRootPassword:" + rootpw
print "Kickstart_PrivateSHARootPassword:" + rootpw
print "Kickstart_PrivateSyslogHost:10.1.1.1"
print "Kickstart_PublicAddress:" + frontendip
print "Kickstart_PublicBroadcast:" + broadcast
print "Kickstart_PublicDNSDomain:" + hostname.split('.')[-2] + '.' + hostname.split('.')[-1]
print "Kickstart_PublicDNSServers:" + dnsserver
print "Kickstart_PublicEthernet:PUBLIC_MAC"
print "Kickstart_PublicGateway:" + gateway
print "Kickstart_PublicHostname:" + hostname
print "Kickstart_PublicInterface:" + public_nic
print "Kickstart_PublicKickstartHost:" + frontendip
print "Kickstart_PublicNTPHost:" + ntp
print "Kickstart_PublicNetmask:" + netmask
print "Kickstart_PublicNetmaskCIDR:" + cidr
print "Kickstart_PublicNetwork:" + network
print "Kickstart_Timezone:" + timezone
print "RootDir:/root"
print "nukedisks:True"
print "EOF"

# Install the rolls file.
print "cat > /tmp/rolls.xml << 'EOF'"
print "<rolls>"
print "<roll arch=\"x86_64\" diskid=\"\" name=\"cluster-core\" url=\"http://" + acid_ip + "/install/rolls/\" version=\"7.0\" />"
print "<roll arch=\"x86_64\" diskid=\"\" name=\"RHEL\" url=\"http://" + acid_ip + "/install/rolls/\" version=\"7.0\" />"
print "<roll arch=\"x86_64\" diskid=\"\" name=\"alu-fe\" url=\"http://" + acid_ip + "/install/rolls/\" version=\"7.0\" />"
print "</rolls>"
print "EOF"

# Execute our node-init script
print "cd /tmp/; wget http://" + acid_ip + "/iso/auto/" + cluster + "/node-init.txt"
print "sh node-init.txt"
print "%end"

# This is the node-init script which is executed while the system is imaging.
init_file = '/var/www/html/iso/auto/' + cluster + '/node-init.txt'

a = "mac=$(ifconfig {public_nic}|grep ether|awk '{{print $2}}' | tr '[:upper:]' '[:lower:]')\n"
b = "sed -i \"s/PUBLIC_MAC/$mac/g\" /tmp/site.attrs\n"

init = open(init_file, 'w')
init.write(a.format(public_nic=public_nic))
init.write(b)
init.close()
