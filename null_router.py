#!/usr/bin/env python
# Listen on a port, if I recieve a connection attempt. Null route the IP.
# Run me like this: nohup python null_router.py &
#
# Joey <jmcdice@gmail.com>
 
import re
import sys
import socket
import signal
import logging
import subprocess
from thread import *

def default_route():
    cmd = "ip route show 0.0.0.0/0|awk '{print $3}'"
    route = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    gw = route.communicate()[0]
    return gw.rstrip('\n')

# Create a thread for each connection, so we can have more than one a time.
def clientthread(conn, addr):

    gw = str(default_route) 

    # White list these IP's
    whitelist = re.compile("^127.0.0.1$|"     # Localhost
			   "^" + gw + "$|"    # Default GW
			   "^194.90.7.244$")  # Your friends

    if whitelist.match(addr[0]):
        logging.info("Connection from: " + addr[0] +". He's ok.")
        conn.close()
    else:
        logging.info('Attempted connection from: ' + addr[0] + ':' + str(addr[1]))
        conn.close()
	null_route="/sbin/route add " + addr[0] + " gw 127.0.0.1 lo"
        logging.info("Executing: " + null_route)
	p = subprocess.Popen(null_route, shell=True)

def signal_handler(signal, frame):
        logging.info('Siginit caught, shutting down.')
        sys.exit(0)

HOST = '' # Internet facing IP address.
PORT = 22 # Anyone coming in on port 22, lifetime ban.

# Start logging
logging.basicConfig(filename='/var/log/null_router.log', 
		    level=logging.DEBUG,
		    format='%(asctime)s %(message)s',
		    datefmt='%m/%d/%Y %I:%M:%S %p')

logging.info('Starting up.') 
logging.info('Socket created') 

# Log ctrl+c's 
signal.signal(signal.SIGINT, signal_handler)          

# Bind socket to local host and port
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
 
try:
    s.bind((HOST, PORT))
except socket.error as msg:
    logging.warning (' Bind failed. Error Code : ' + str(msg[0]) + ' Message ' + msg[1])
    sys.exit()
     
logging.info('Socket bind complete.')
 
s.listen(10)
logging.info('Socket now listening.')

# Wait for a connection
while 1:
    conn, addr = s.accept()
    start_new_thread(clientthread ,(conn,addr))

s.close()

