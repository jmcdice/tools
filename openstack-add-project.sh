#!/bin/sh

if [ $# -eq 0 ]
then
    echo " Usage: `basename $0` Project#"
    exit 2
fi

source /root/keystonerc_admin

#variables
    
id=$1
tenant=Tenant 
project=Project
user=user
ks_dir=/root/keystonerc

###begin
mk_pw(){
#if ! [ -f /usr/bin/pwmake ]
#then 
#       echo " WARN: /usr/bin/pwmake not found. Pls install libpwquality"
#       exit 1
#fi
#password=`pwmake 4`
#password=`date +%s | sha256sum | base64 | head -c 8 ; echo`
####making things simpler while i test this
password=password
}

create_project(){
keystone tenant-create --name=$project$id --description $tenant$id
}

create_admin_user(){
#keystone user-create --name=$user$id --pass=$password --email=admin@localhost --tenant $project$id
keystone user-create --name=$user$id --pass=$password --email=admin@localhost 

echo " INFO: admin user ($user$id) for $project$id has password $password"
echo "------- check if password $password has special characters that might break things eg. ; *"
}

assign_role_to_user(){
#keystone user-role-add --user $user$id --role admin$id --tenant $project$id
keystone user-role-add --user $user$id --role Member --tenant $project$id
}

create_networks(){
source $ks_dir/keystonerc_$user$id

neutron router-create router$id
neutron net-create PrivateNet_$id
CIDR=`neutron subnet-list | awk '{print $6}'| grep ^10. | cut -d/ -f1`
if [ "$CIDR" == "" ]
then
    echo "WARN: CIDR 10.x.x.x not found. Is this a new install?"
    CIDR=10.0.0.0
fi
CIDR2=`echo $CIDR| cut -d. -f2`
CIDR3=`echo $CIDR| cut -d. -f3`
if [ $CIDR3 -eq 255 ]
then
    if [ $CIDR2 -eq     255 ]
    then
        echo " FAIL: You are out of networks!"
        exit 3
    else
        CIDR2=`expr $CIDR2 + 1`
    fi
else
    CIDR3=`expr $CIDR3 + 1`
fi

CIDR=10.$CIDR2.$CIDR3.0

neutron subnet-create --name PrivateSubnet_$id PrivateNet_$id $CIDR/24
neutron router-interface-add router$id PrivateSubnet_$id

source /root/keystonerc_admin
#neutron router-gateway-set router$id PublicLAN ##why? this is already done in openstack-outside.sh
}

keystonerc(){
echo " INFO: Writing $ks_dir/keystonerc_$user$id"
mkdir -p $ks_dir
cat >> $ks_dir/keystonerc_$user$id << EOF
export OS_USERNAME=$user$id
export OS_TENANT_NAME=$project$id
export OS_PASSWORD=$password
export OS_AUTH_URL=http://192.168.0.33:35357/v2.0/
export PS1='[\u@\h \W(\033[1;32mkeystone_$user$id\033[0m)]\$ '
EOF
}

write_security_rules(){
echo use neutron secgroup to add ssh and ping rules
source $ks_dir/keystonerc_$user$id
nova keypair-add key$id > $ks_dir/key$id.pem
nova secgroup-create SecGrp$id "Security Group $id"
nova secgroup-add-rule SecGrp$id tcp 22 22 0.0.0.0/0
}

###main
mk_pw
create_admin_user
create_project
assign_role_to_user
keystonerc
create_networks
write_security_rules
