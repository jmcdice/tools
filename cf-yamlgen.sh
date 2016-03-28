#!/usr/bin/bash
#
# Generate a CF Manifest - this is a horrible process.
# http://docs.cloudfoundry.org/deploying/openstack/cf-stub.html
# Joey

# This needs to be setup already.
# Bind entries looks like this:
# *.cf.domain.com                     IN      A               1.2.3.4

echo "Generating CF manifest."

# Put all your constants in this file
source env.local

log="/tmp/cfmanifest.log"
echo "" > $log

ip=$(nova list|grep cf-management|perl -lane 'print $1 if (/public=(.*?)\s/)')
login="ssh -i /root/.ssh/cf_id_rsa $ip"

echo -n "Getting Bosh UUID: "
DIRECTOR_UUID=$($login 'bosh status --uuid')
echo "Ok ($DIRECTOR_UUID)"

echo -n "Getting CF Release Version: "
login="ssh -i /root/.ssh/cf_id_rsa $ip"
CF_RELEASE=$($login "bosh releases 2>&1| grep cf|awk '{print \$4}'|sed 's/[^0-9]*//g'")
echo "Ok ($CF_RELEASE)"

# Get a floater for HAPROXY
echo -n "Creating floating IP for HAProxy: "
net=$(ifconfig br1 | perl -lane 'print $1 if /inet (.*?)\s/' | cut -d'.' -f1-3);
HAPROXY="$net.111"
neutron floatingip-create --floating-ip-address $HAPROXY public &>> /dev/null
echo "OK ($HAPROXY)"

# Generate an encryption key
DB_ENCRYPTION_KEY=$(cat /dev/urandom | head -c 16 | base64)

# We need a bunch of random passwords
STAGING_UPLOAD_PASSWORD=$(cat /dev/urandom | head -c 16 | base64)
BULK_API_PASSWORD=$(cat /dev/urandom | head -c 16 | base64)
BLOBSTORE_PASSWORD=$(cat /dev/urandom | head -c 16 | base64)
NATS_PASSWORD=$(cat /dev/urandom | head -c 16 | base64)
ROUTER_PASSWORD=$(cat /dev/urandom | head -c 16 | base64)
CCDB_PASSWORD=$(cat /dev/urandom | head -c 16 | base64)
UAADB_PASSWORD=$(cat /dev/urandom | head -c 16 | base64)
CCDB_PASSWORD=$(cat /dev/urandom | head -c 16 | base64)
UAADB_PASSWORD=$(cat /dev/urandom | head -c 16 | base64)

# Set some values for stuff we know about.
PUBLIC_NET=$(neutron net-list|grep public | awk '{print $2}')
PRIVATE_NET=$(neutron net-list|grep cf-private | awk '{print $2}')
ENVIRONMENT=$(hostname)

# Generate an RSA private key and sign an SSL cert with it.
if [ ! -d 'certs' ]; then
   mkdir certs
fi

# Delete all previous keys
rm -f certs/*


function cert_gen() {

   app=$1
   echo "Creating a cert for: $app"
   co=US; st=Colorado; loc=Boulder; org=CF; orgu=IT; comname=$DOMAIN; email=nobody@cf.com
   openssl genrsa -out certs/pk_$app.pem 2048 &>> $log
   openssl req -new -key certs/pk_$app.pem -out certs/csr_$app.pem \
       -subj "/C=$co/ST=$st/L=$loc/O=$org/OU=$orgu/CN=$comname/emailAddress=$email" &>> $log
   openssl x509 -req -days 2048 -in certs/csr_$app.pem -signkey certs/pk_$app.pem -out certs/cert_$app.pem &>> $log
}

cert_gen blobstore
BLOBSTORE_TLS_CERT=$(cat certs/cert_blobstore.pem|perl -lane '$_ =~ s/^\s+//; print "          $_"')
BLOBSTORE_PRIVATE_KEY=$(cat certs/pk_blobstore.pem|perl -lane '$_ =~ s/^\s+//; print "          $_"')

cert_gen haproxy
HAPROXY_TLS_CERT=$(cat certs/cert_haproxy.pem|perl -lane '$_ =~ s/^\s+//; print "          $_"')
HAPROXY_PRIVATE_KEY=$(cat certs/pk_haproxy.pem|perl -lane '$_ =~ s/^\s+//; print "          $_"')

echo -n "Writing yaml: "
cat << EOF > cf-stub.yaml
<%
director_uuid           = '$DIRECTOR_UUID'
environment             = '$ENVIRONMENT'
floating_ip             = '$HAPROXY'
root_domain             = '$DOMAIN'
public_net_id           = '$PUBLIC_NET'
private_net_id          = '$PRIVATE_NET'
deployment_name         = 'cf'
cf_release              = '$CF_RELEASE'
protocol                = 'http'
common_password         = 'c1oudc0w'
db_enc_key              = '$DB_ENCRYPTION_KEY'
staging_upload_password = '$STAGING_UPLOAD_PASSWORD'
bulk_api_password       = '$BULK_API_PASSWORD'
blobstore_password      = '$BLOBSTORE_PASSWORD'
nats_password           = '$NATS_PASSWORD'
router_password         = '$ROUTER_PASSWORD'
ccdb_password           = '$CCDB_PASSWORD'
uaadb_password          = '$UAADB_PASSWORD'
ccdb_password           = '$CCDB_PASSWORD'
uaadb_password          = '$UAADB_PASSWORD'

%>
---
director_uuid: <%= director_uuid %>

meta:
  environment: <%= environment %>

  floating_static_ips:
  - <%= floating_ip %>

networks:
  - name: public
    type: vip
    cloud_properties:
      net_id: <%= public_net_id %>
      security_groups: []
  - name: cf-private
    type: manual
    subnets:
    - range: 10.10.10.0/24
      gateway: 10.10.1.1
      reserved:
      - 10.10.10.2 - 10.10.10.100
      - 10.10.10.200 - 10.10.10.254
      dns:
      - 8.8.8.8
      static:
      - 10.10.10.125 - 10.10.10.175
      cloud_properties:
        net_id: <%= private_net_id %>
        security_groups: ["cf"]
  - name: cf2
    type: manual
    subnets: (( networks.cf1.subnets )) # cf2 unused by default with the OpenStack template
                                        # but the general upstream templates require this
                                        # to be a semi-valid value, so just copy cf1

properties:
  domain: <%= root_domain %>
  system_domain: <%= root_domain %>
  system_domain_organization: cf-root-domain
  app_domains: <%= root_domain %>
   - <%= root_domain %>

  ssl:
    skip_cert_verify: true

  cc:
    staging_upload_user: staging_upload_user
    staging_upload_password: <%= staging_upload_password %>
    bulk_api_password: <%= bulk_api_password %>
    db_encryption_key: <%= db_enc_key %>
    uaa_skip_ssl_validation: true

  blobstore:
    admin_users:
      - username: blobstore-username
        password: <%= blobstore_password %>
    secure_link:
      secret: blobstore-secret
    tls:
      port: 443
      cert: BLOBSTORE_TLS_CERT
      private_key: BLOBSTORE_PRIVATE_KEY

  consul:
    encrypt_keys:
      - CONSUL_ENCRYPT_KEY
    ca_cert: CONSUL_CA_CERT
    server_cert: CONSUL_SERVER_CERT
    server_key: CONSUL_SERVER_KEY
    agent_cert: CONSUL_AGENT_CERT
    agent_key: CONSUL_AGENT_KEY
  dea_next:
    disk_mb: 2048
    memory_mb: 1024
  loggregator_endpoint:
    shared_secret: LOGGREGATOR_ENDPOINT_SHARED_SECRET
  login:
    protocol: http
  nats:
    user: NATS_USER
    password: NATS_PASSWORD
  router:
    status:
      user: ROUTER_USER
      password: ROUTER_PASSWORD
  uaa:
    admin:
      client_secret: ADMIN_SECRET
    cc:
      client_secret: CC_CLIENT_SECRET
    clients:
      cc_routing:
        secret: CC_ROUTING_SECRET
      cloud_controller_username_lookup:
        secret: CLOUD_CONTROLLER_USERNAME_LOOKUP_SECRET
      doppler:
        secret: DOPPLER_SECRET
      gorouter:
        secret: GOROUTER_SECRET
      tcp_emitter:
        secret: TCP-EMITTER-SECRET
      tcp_router:
        secret: TCP-ROUTER-SECRET
      login:
        secret: LOGIN_CLIENT_SECRET
      notifications:
        secret: NOTIFICATIONS_CLIENT_SECRET
    jwt:
      verification_key: JWT_VERIFICATION_KEY
      signing_key: JWT_SIGNING_KEY
    scim:
      users:
        - admin|ADMIN_PASSWORD|scim.write,scim.read,openid,cloud_controller.admin,doppler.firehose

  ccdb:
    roles:
    - name: ccadmin
      password: CCDB_PASSWORD
  uaadb:
    roles:
    - name: uaaadmin
      password: UAADB_PASSWORD
  databases:
    roles:
    - name: ccadmin
      password: CCDB_PASSWORD
    - name: uaaadmin
      password: UAADB_PASSWORD

jobs:
  - name: ha_proxy_z1
    networks:
      - name: cf1
        default:
        - dns
        - gateway
    properties:
      ha_proxy:
        ssl_pem: |
          -----BEGIN RSA PRIVATE KEY-----
          RSA_PRIVATE_KEY
          -----END RSA PRIVATE KEY-----
          -----BEGIN CERTIFICATE-----
          SSL_CERTIFICATE_SIGNED_BY_PRIVATE_KEY
          -----END CERTIFICATE-----
  - name: api_z1
    templates:
      - name: go-buildpack
        release: cf
      - name: binary-buildpack
        release: cf
      - name: nodejs-buildpack
        release: cf
      - name: ruby-buildpack
        release: cf
      - name: php-buildpack
        release: cf
      - name: python-buildpack
        release: cf
      - name: staticfile-buildpack
        release: cf
      - name: cloud_controller_ng
        release: cf
      - name: cloud_controller_clock
        release: cf
      - name: cloud_controller_worker
        release: cf
      - name: metron_agent
        release: cf
      - name: statsd-injector
        release: cf
      - name: route_registrar
        release: cf

  - name: api_worker_z1
    instances: 0
  - name: clock_global
    instances: 0

EOF
sleep 1;
echo "Ok"
