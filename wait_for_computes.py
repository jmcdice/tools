#!/usr/bin/python
import os
import sys
import subprocess
import utils
def main():
    WaitForOnlineCompute()

def WaitForOnlineCompute():
    compList = []
    #compute = subprocess.Popen('salt-run manage.up | grep compute', shell=True, stdout=subprocess.PIPE)
    arr = utils.system("rocks list host | grep compute | awk '{print $1}'")[0].split('\n')
    for line in arr:
        compList.append(line.replace(':',''))
    # now we have a list of salt available compute. let's return first one that response to ssh
    compList = compList[0:-1]
    num = len(compList)
    while True:
        if len(compList)==0:
            return
        for compute in compList:
            retcode = subprocess.Popen('/usr/bin/ssh -q -o ConnectTimeout=1 '+ compute +' /bin/true', shell=True, stdout=subprocess.PIPE)
            retcode.communicate()
            #print "testing compute "+compute+" exit code = "+str(retcode.returncode)
            if retcode.returncode != 0:
                print 'compute %s not online' % compute
                print 'Remains ['+str(len(compList))+'/'+str(num)+']'
            else :
                compList.remove(compute)
if __name__ == "__main__":
    main()


