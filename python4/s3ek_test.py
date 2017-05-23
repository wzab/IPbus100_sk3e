import uhal
import sys
import pickle
import time
import struct
#class mytime:
#   def __init__(self):
#     return
#   def sleep(self,delay):
#     bus_delay(delay/1e-9)
#time=mytime()
N_OF_SLOTS = 5
#Below we set active links
# 1 - link is working
# 0 - we simulate, that the link is broken
LINK_BREAK = 0b00010

manager = uhal.ConnectionManager("file://s3ek_conn.xml")
hw = manager.getDevice("dummy.udp.0")
#Configure objects used for IPbus communication
class ipbus(object):
  def __init__(self,hw,node):
    self.hw = hw
    self.node = hw.getNode(node)
    pass
  def write(self,val):
    self.node.write(val)
    self.hw.dispatch()
  def read(self):
    v=self.node.read()
    self.hw.dispatch()
    return v
  def readBlock(self,nwords):
    v=self.node.readBlock(nwords)
    self.hw.dispatch()
    return v

#Configure objects used for IPbus communication
#from cbus import *
#hw=cbus_read_nodes("./sts_emul1_address.xml")
#def ipbus(nodes,name):
#   return nodes[name] 
time.sleep(100e-9)
#ID
IDReg=ipbus(hw,"ID")
Buttons=ipbus(hw,"BUTTONS")
Leds=ipbus(hw,"LEDS")

