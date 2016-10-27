
source /home/stack/stackrc || die "Can't get creds, captain."
PUBIP=$(ifconfig eth1|grep inet|head -1|awk '{print $2}')
HWTYPE=$(grep hw_model_type: templates/user_config.yaml|awk '{print $2}')
COMPUTES=$(nova list|grep Running | wc -l)
HOSTNAME=$(hostname)
STACKSHOW='/tmp/overcloud_stack_show'
heat stack-show overcloud > /tmp/overcloud_stack_show

CBIS_VERSION=$(tail -1 /usr/share/cbis/cbis-version)
STACKSTART=$(grep creation_time $STACKSHOW | awk '{print $4}')
START_TIME=$(date -u -d "$STARTSTACK" +"%s")
END_TIME=$(date +"%s")
DIFF=$(($END_TIME - $START_TIME))
MIN=$(($DIFF / 60))

GWIP=$(dig +short myip.opendns.com @resolver1.opendns.com)
GEOIP=$(curl -4 --silent freegeoip.net/csv/$GWIP | awk -F, '{print $3","$5}')
COUNTRY=$(echo $GEOIP | cut -d \, -f 1)
CITY=$(echo $GEOIP | cut -d \, -f 2)

heat stack-list|grep overcloud|grep -q CREATE_COMPLETE
if [ $? != 0 ]; then
   STATUS='Failed'
else
   STATUS='Success'
fi

echo -n 'payload={"channel": "#setups", "username": "acidbot", "text": ' > /tmp/slack.txt
echo -n "\"$PUBIP\n" >> /tmp/slack.txt
echo -n "CBIS install completed in $MIN minutes on $HWTYPE ($COMPUTES computes)\n" >> /tmp/slack.txt
echo -n "CBIS $CBIS_VERSION\n" >> /tmp/slack.txt
echo -n "Deploy Status: $STATUS\n" >> /tmp/slack.txt

if [ ! -z "$COUNTRY" ]; then
     echo -n "Cluster Location: $CITY $COUNTRY\n" >> /tmp/slack.txt
fi
icon='beer'
echo -n "\", \"icon_emoji\": \":$icon:\"}" >> /tmp/slack.txt
#curl -X POST --data "@/tmp/slack.txt" https://hooks.slack.com/services/somesecreetstuffhere
