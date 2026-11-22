/**
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * AUTHORS
 * Maciek Borzecki <maciek.borzecki (at] gmail.com>
 * gyan000 <gyan000 (at] ijaz.fr>
 */

namespace MConnect {

    public class Discovery : GLib.Object {

        private const uint DISCOVERY_PORT = 1716;
        private const uint MIN_TCP_PORT = 1716;
        private const uint MAX_TCP_PORT = 1764;

        public signal void device_found (DiscoveredDevice dev);

        private Socket socket = null;

        public Discovery () {
        }

        ~Discovery () {
            debug ("Cleaning up discovery...");
            if (this.socket != null) {
                this.socket.close ();
            }
        }

        public void listen () throws Error {
            this.socket = new Socket (SocketFamily.IPV4, SocketType.DATAGRAM, SocketProtocol.UDP);
            var sa = new InetSocketAddress (new InetAddress.any (SocketFamily.IPV4),
                                            (uint16) DISCOVERY_PORT);
            debug ("Start listening for new devices at: %s:%u", sa.address.to_string (), sa.port);

            try {
                this.socket.bind (sa, false);
            } catch (Error e) {
                this.socket.close ();
                this.socket = null;
                throw e;
            }

            var source = socket.create_source (IOCondition.IN);
            source.set_callback ((s, c) => {
                this.incomingPacket ();
                return true;
            });
            
            source.attach (MainContext.default ());
        }

        private void incomingPacket () {
            debug ("Incoming packet.");

            uint8 buffer[8193];
            SocketAddress sa;
            InetSocketAddress isa;

            try {
                ssize_t read = this.socket.receive_from (out sa, buffer);
                if (read < 0 || read >= 8193) {
                    warning ("Ignoring oversized discovery packet");
                    return;
                }
                buffer[(int) read] = 0;
                isa = (InetSocketAddress) sa;
                debug ("Got %zd bytes from: %s:%u", read, isa.address.to_string (), isa.port);
            } catch (Error e) {
                warning ("Failed to receive packet: %s", e.message);
                return;
            }

            debug ("Message data: %s", (string) buffer);
            this.parsePacketFromHost ((string) buffer, isa.address);
        }

        private void parsePacketFromHost (string data, InetAddress host) {
            // Expecing an identity packet.
            var pkt = Packet.new_from_data (data);
            if (pkt == null) {
                warning ("Ignoring malformed discovery packet from %s", host.to_string ());
                return;
            }
            if (pkt.pkt_type != Packet.IDENTITY) {
                message ("Unexpected packet type %s from device %s", pkt.pkt_type, host.to_string ());
                return;
            }

            if (!pkt.body.has_member ("deviceId") ||
                !pkt.body.has_member ("deviceName") ||
                !pkt.body.has_member ("protocolVersion") ||
                !pkt.body.has_member ("tcpPort")) {
                warning ("Ignoring incomplete discovery packet from %s", host.to_string ());
                return;
            }

            var dev = new DiscoveredDevice.from_identity (pkt, host);
            if (dev.protocol_version < (uint) Packet.PROTOCOL_VERSION) {
                warning ("Ignoring device %s using unsupported protocol version %u",
                         dev.name, dev.protocol_version);
                return;
            }
            if (dev.tcp_port < MIN_TCP_PORT || dev.tcp_port > MAX_TCP_PORT) {
                warning ("Ignoring device %s advertising an out-of-range TCP port %u",
                         dev.name, dev.tcp_port);
                return;
            }

            message ("Connection from device: \'%s\', responds at: %s:%u", dev.name, host.to_string (), dev.tcp_port);
            device_found (dev);
        }
    }
}
