# Go through /var/log/httpd/access_log and block anyone that 
# posted an invalid request.
# Joey <joseph.mcdonald@alcatel-lucent.com>

function null_route() {

   ip=$1
   date=`date`
   logfile='/root/blocked_hosts.txt'

   count=$(egrep -w $ip /var/log/httpd/access_log | grep '404 -' |wc -l)

   route -n | egrep -w -q $ip
   if [ $? -eq 0 ]; then
      echo "$ip:	($count attempts) already blocked."
   else
      echo "$ip:	($count attempts) adding block."
      echo "# $date" >> $logfile
      echo "/sbin/route add $ip gw 127.0.0.1 lo" >> $logfile
      /sbin/route add $ip gw 127.0.0.1 lo
   fi
}

for ip in `grep '404 -' /var/log/httpd/access_log|awk '{print $1}' | sort | uniq|egrep -v '^135|76.25.50.'`; do
   null_route $ip
done


