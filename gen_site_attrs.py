#!/usr/bin/env python
#
# Generate a site.attrs file for rocks 7
# Joey <joseph.mcdonald@alcatel-lucent.com>

import sys
sys.path.append('/export/apps/common/python/ALU/common/')
from nodeconf import config
from optparse import OptionParser

# Pull in our option(s)
parser = OptionParser()
parser.add_option( "-f", "--file", 
		   dest="filename",
                   help="Read config from specified file", 
		   metavar="FILE" )
(options, args) = parser.parse_args()
config_file = options.filename

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

# These things we'll have to pull dynamically

print "HttpConf:/etc/httpd/conf"
print "HttpConfigDirExt:/etc/httpd/conf.d"
print "HttpRoot:/var/www/html"
print "Info_CertificateCountry:US"
print "Info_CertificateLocality:Boulder"
print "Info_CertificateOrganization:Alcatel Lucent"
print "Info_CertificateState:Colorado"
print "Info_ClusterContact:node-team@alcatel-lucent.com"
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
print "Kickstart_PrivateEthernet:00:9c:02:99:2e:cc"
print "Kickstart_PrivateGateway:10.1.1.1"
print "Kickstart_PrivateInterface:eno1"
print "Kickstart_PrivateKickstartCGI:sbin/kickstart.cgi"
print "Kickstart_PrivateKickstartHost:10.1.1.1"
print "Kickstart_PrivateHostname:" + hostname
print "Kickstart_PrivateMD5RootPassword:" + rootpw
print "Kickstart_PrivateNTPHost:10.1.1.1"
print "Kickstart_PrivateNetmask:255.255.0.0"
print "Kickstart_PrivateNetmaskCIDR:16"
print "Kickstart_PrivateNetwork:10.1.0.0"
print "Kickstart_PrivateSyslogHost:10.1.1.1"
print "Kickstart_PrivatePortableRootPassword:" + rootpw
print "Kickstart_PrivateRootPassword:" + rootpw
print "Kickstart_PrivateSHARootPassword:" + rootpw
print "Kickstart_PublicAddress:" + frontendip
print "Kickstart_PublicBroadcast:" + broadcast
print "Kickstart_PublicDNSDomain:" 
print "Kickstart_PublicDNSServers:" + dnsserver
print "Kickstart_PublicInterface:eno3"
print "Kickstart_PublicEthernet:00:9c:02:99:2e:cd"
print "Kickstart_PublicGateway:" + gateway
print "Kickstart_PublicHostname:" + hostname
print "Kickstart_PublicInterface:" 
print "Kickstart_PublicKickstartHost:" + frontendip
print "Kickstart_PublicNTPHost:" + ntp
print "Kickstart_PublicNetmask:" + netmask
print "Kickstart_PublicNetmaskCIDR:" + cidr
print "Kickstart_PublicNetwork:" + network
print "Kickstart_Timezone:" + timezone
print "RootDir:/root"
print "nukedisks:True"
