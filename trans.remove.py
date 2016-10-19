#!/usr/bin/python
#
# Delete finsihed torrents from Transmission

import subprocess
import re

trans = subprocess.Popen('/usr/bin/transmission-remote -l', shell=True, stdout=subprocess.PIPE)

for line in trans.stdout:
   if "100%" in line:
      id = re.findall('\s+(.*?)\s.*?', line)[0]
      name = re.findall('\s+(.*?)\s.*?', line)[8]
      print "Deleting:", name
      subprocess.Popen(['/usr/bin/transmission-remote', '-t', id, '-r'])
