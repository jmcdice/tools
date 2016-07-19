
cat << EOF >> /tmp/rc.local
/usr/sbin/iscsiadm -m fw
if [ \$? == 0 ]; then
   bash /etc/iscsi_check.sh
fi
EOF


