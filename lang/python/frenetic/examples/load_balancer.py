import frenetic, sys, json, time, argparse
import os.path
from frenetic.syntax import *
import array
from ryu.lib.packet import packet

client_port = 1

def get(pkt,protocol):
    for p in pkt:
        if p.protocol_name == protocol:
            return p

# Returns 0 as a default
def packet_src_port(payload):
  pkt = packet.Packet(array.array('b', payload.data))
  ip = get(pkt, "ipv4")

  if ip.proto == 6:
    return get(pkt, "tcp").src_port
  else:
    return 0

class State(object):

  def __init__(self, server_ports):
    self.connections = {}
    self.server_ports = server_ports
    self.next_server_index = 0

  def next_server_port(self):
    n = self.next_server_index
    self.next_server_index = (n + 1) % len(self.server_ports)
    return self.server_ports[n]

  def new_connection(self, src_port):
    if not(src_port in self.connections):
      self.connections[src_port] = self.next_server_port()
    return self.connections[src_port]

class LoadBalancer(frenetic.App):

  client_id = "load_balancer"

  def __init__(self, client_port, state):
    frenetic.App.__init__(self)
    self.client_port = client_port
    self.state = state

  def policy(self):
    conns = self.state.connections
    pol = (Union(self.route(src_port) for src_port in conns) |
            self.to_controller())
    return Filter(Test(EthType(0x800))) >> pol

  def connected(self):
      self.update(self.policy())

  def route(self, src_tcp_port):
    dst_sw_port = self.state.connections[src_tcp_port]
    client_to_server = \
      Filter(Test(Location(Physical(self.client_port))) &
             Test(TCPSrcPort(src_tcp_port))) >> \
      Mod(Location(Physical(dst_sw_port)))
    server_to_client = \
      Filter(Test(Location(Physical(dst_sw_port))) &
             Test(TCPDstPort(src_tcp_port))) >> \
      Mod(Location(Physical(self.client_port)))
    return Filter(Test(IPProto(6))) >> (client_to_server | server_to_client)

  def to_controller(self):
    known_src_ports = self.state.connections.keys()
    return Filter(Test(Location(Physical(self.client_port))) &
                  ~Or(Test(TCPSrcPort(pt)) for pt in known_src_ports)) >> \
      Mod(Location(Pipe("http")))

  def packet_in(self, switch_id, port_id, payload):
    src = packet_src_port(payload)
    server_port = self.state.new_connection(src)
    print "Sending traffic from TCP port %s to switch port %s" % (src, server_port)
    self.update(self.policy())

    # Assumes no address-translation
    self.pkt_out(switch_id = switch_id, payload = payload,
                 actions = [Output(Physical(server_port))])

if __name__ == '__main__':
  parser = argparse.ArgumentParser(description="A simple load balancer")
  parser.add_argument("--client-port", type=int, default="1")
  parser.add_argument("--server-ports", metavar="P", type=int, nargs="+",
                      help="Ports on which servers are running")
  args = parser.parse_args()
  app = LoadBalancer(args.client_port, State(args.server_ports))
  app.start_event_loop()