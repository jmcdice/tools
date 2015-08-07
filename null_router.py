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

# Create a thread for each connection, so we can have more than one a time.
def clientthread(conn, addr):

    # Never block these IP's, they're my friends.
    friends = re.compile("^127.0.0.1$|"
			 "^194.90.7.244$")

    if friends.match(addr[0]):
        logging.info("Connection from: " + addr[0] +". He's ok.")
        conn.close()
    else:
        logging.info('Attempted connection from: ' + addr[0] + ':' + str(addr[1]))
	null_route="/sbin/route add " + addr[0] + " gw 127.0.0.1 lo"
        conn.close()

        logging.info("Executing: " + null_route)
	p = subprocess.Popen(null_route, shell=True)

        conn.close()

def signal_handler(signal, frame):
        logging.info('Siginit caught, shutting down.')
        sys.exit(0)

 
HOST = '' # Internet facing interface.
PORT = 22 # Anyone coming in on port 22, lifetime ban.
 
signal.signal(signal.SIGINT, signal_handler)          # Log ctrl+c's 
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

# Start logging
logging.basicConfig(filename='/root/null_router.log', 
		    level=logging.DEBUG,
		    format='%(asctime)s %(message)s',
		    datefmt='%m/%d/%Y %I:%M:%S %p')


logging.info('Starting up.') 
logging.info('Socket created') 
 
#Bind socket to local host and port
try:
    s.bind((HOST, PORT))
except socket.error as msg:
    logging.warning (' Bind failed. Error Code : ' + str(msg[0]) + ' Message ' + msg[1])
    sys.exit()
     
logging.info('Socket bind complete.')
 
s.listen(10)
logging.info('Socket now listening.')

# Someone/thing connected..
while 1:
    conn, addr = s.accept()
    start_new_thread(clientthread ,(conn,addr))

s.close()

