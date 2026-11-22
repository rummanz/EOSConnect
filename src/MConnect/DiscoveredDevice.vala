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
    /**
     * Newly discovered device wrapper.
     */
    public class DiscoveredDevice : Object {

        public string id {
            get; private set; default = "";
        }
        public string name {
            get; private set; default = "";
        }
        // public string custom_name {
        //     get; private set; default = "";
        // }
        // public int device_num {
        //     get; private set; default = 0;
        // }
        public string device_type {
            get; private set; default = "";
        }
        // public uint battery_level {
        //     get; private set; default = 100;
        // }
        // public bool battery_charging {
        //     get; private set; default = false;
        // }
        public uint protocol_version {
            get; private set; default = 8;
        }
        public uint tcp_port {
            get; private set; default = 1716;
        }
        public InetAddress host {
            get; private set; default = null;
        }
        public string[] outgoing_capabilities {
            get; private set; default = null;
        }
        public string[] incoming_capabilities {
            get; private set; default = null;
        }
        public bool capabilities_known { get; private set; default = false; }

        /**
         * Constructs DiscoveredDevice based on identity packet.
         *
         * @param pkt identity packet
         * @param host source host that the packet came from
         */
        public DiscoveredDevice.from_identity (Packet pkt, InetAddress host) {

            debug ("Got packet: %s", pkt.to_string ());

            var body = pkt.body;
            this.host = host;
            this.name = body.has_member ("deviceName") ? body.get_string_member ("deviceName") : "";
            this.id = body.has_member ("deviceId") ? body.get_string_member ("deviceId") : "";
            this.device_type = body.has_member ("deviceType") ? body.get_string_member ("deviceType") : "desktop";
            this.protocol_version = body.has_member ("protocolVersion")
                ? (uint) body.get_int_member ("protocolVersion")
                : (uint) Packet.PROTOCOL_VERSION;
            this.tcp_port = body.has_member ("tcpPort") ? (uint) body.get_int_member ("tcpPort") : 1716;
            this.capabilities_known = body.has_member ("incomingCapabilities") &&
                body.has_member ("outgoingCapabilities");

            if (body.has_member ("incomingCapabilities")) {
                var incoming = body.get_array_member ("incomingCapabilities");
                this.incoming_capabilities = new string[incoming.get_length ()];
                incoming.foreach_element ((a, i, n) => {
                    this.incoming_capabilities[i] = n.get_string ();
                });
            } else {
                this.incoming_capabilities = {};
            }

            if (body.has_member ("outgoingCapabilities")) {
                var outgoing = body.get_array_member ("outgoingCapabilities");
                this.outgoing_capabilities = new string[outgoing.get_length ()];
                outgoing.foreach_element ((a, i, n) => {
                    this.outgoing_capabilities[i] = n.get_string ();
                });
            } else {
                this.outgoing_capabilities = {};
            }

            debug ("Discovered new device: %s", this.to_string ());
        }

        public string to_string () {
            return "Discovered-%s-%s-%s-%u".printf (this.id,
                                                    this.name,
                                                    this.device_type,
                                                    this.protocol_version);
        }

        // public string to_unique_string () {
        //     return Utils.make_unique_device_string (this.id,
        //                                             this.name,
        //                                             this.device_type,
        //                                             this.protocol_version);
        // }
    }
}
