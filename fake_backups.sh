# Create a set of fake backups to test 
# DEV-30288
# Joey <joey.mcdonald@nokia.com>

hostname=$(hostname -s)
faketar="$hostname.tar.enc"

## Create a fake backup archive. 
if [ ! -f "$faketar" ]; then
   echo "Creating fake backup file."
   fallocate -l 20M /tmp/$faketar
fi

# Populate directories and set a date on the files
# to some time offset in the past 20 days.
for i in {1..20}; do
   fakedate=$(date +"%Y.%m.%d.%H.%M.%S" --date="$i days ago")
   dir="/cloudfs/backups/$hostname/$fakedate/"
   mkdir -p $dir
   cp /tmp/$faketar $dir/   
   touch -d "$i days ago" $dir/$faketar
   touch -d "$i days ago" $dir
done

rm /tmp/$faketar
