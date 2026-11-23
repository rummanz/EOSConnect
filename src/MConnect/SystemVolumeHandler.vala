namespace MConnect {

    public class SystemVolumeHandler : Object, PacketHandlerInterface {

        public const string SYSTEMVOLUME = "kdeconnect.systemvolume";
        public const string SYSTEMVOLUME_REQUEST = "kdeconnect.systemvolume.request";

        private SystemVolumeHandler () {
        }

        public static SystemVolumeHandler instance () {
            return new SystemVolumeHandler ();
        }

        public string get_pkt_type () {
            return SYSTEMVOLUME;
        }

        public void use_device (Device dev) {
            dev.message.connect (message);
            send_sink_list (dev);
        }

        public void release_device (Device dev) {
            dev.message.disconnect (message);
        }

        private void message (Device dev, Packet pkt) {
            if (pkt.pkt_type != SYSTEMVOLUME_REQUEST) {
                return;
            }
            if (pkt.body.has_member ("requestSinks") &&
                pkt.body.get_boolean_member ("requestSinks")) {
                send_sink_list (dev);
                return;
            }
            if (!pkt.body.has_member ("name")) {
                return;
            }
            string name = pkt.body.get_string_member ("name");
            int id = sink_id (name);
            if (id == 0) {
                warning ("Cannot find PipeWire sink %s", name);
                return;
            }
            if (pkt.body.has_member ("volume")) {
                int volume = (int) pkt.body.get_int_member ("volume");
                run_wpctl ("set-volume " + id.to_string () + " " + volume.to_string () + "%");
            }
            if (pkt.body.has_member ("muted")) {
                bool muted = pkt.body.get_boolean_member ("muted");
                run_wpctl ("set-mute " + id.to_string () + " " + (muted ? "1" : "0"));
            }
            if (pkt.body.has_member ("enabled") &&
                pkt.body.get_boolean_member ("enabled")) {
                run_wpctl (@"set-default $id");
            }
            send_sink_list (dev);
        }

        private void send_sink_list (Device dev) {
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("sinkList");
            builder.begin_array ();
            foreach (var sink in list_sinks ()) {
                builder.begin_object ();
                builder.set_member_name ("name");
                builder.add_string_value (sink.name);
                builder.set_member_name ("description");
                builder.add_string_value (sink.description);
                builder.set_member_name ("volume");
                builder.add_int_value (sink.volume);
                builder.set_member_name ("maxVolume");
                builder.add_int_value (100);
                builder.set_member_name ("muted");
                builder.add_boolean_value (sink.muted);
                builder.set_member_name ("enabled");
                builder.add_boolean_value (sink.enabled);
                builder.end_object ();
            }
            builder.end_array ();
            builder.end_object ();
            dev.send (new Packet (SYSTEMVOLUME, builder.get_root ().get_object (), 0));
        }

        private Gee.ArrayList<PipeWireSink> list_sinks () {
            var result = new Gee.ArrayList<PipeWireSink> ();
            try {
                string output;
                string error_output;
                int status;
                Process.spawn_sync (
                    null, {"pw-dump"},
                    null, SpawnFlags.SEARCH_PATH,
                    null, out output, out error_output, out status);
                var parser = new Json.Parser ();
                parser.load_from_data (output, -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                    return result;
                }
                int default_id = default_sink_id ();
                foreach (var node in root.get_array ().get_elements ()) {
                    if (node.get_node_type () != Json.NodeType.OBJECT) {
                        continue;
                    }
                    var object = node.get_object ();
                    if (!object.has_member ("info")) {
                        continue;
                    }
                    var info = object.get_object_member ("info");
                    if (info == null || !info.has_member ("props")) {
                        continue;
                    }
                    var props = info.get_object_member ("props");
                    if (props == null ||
                        !props.has_member ("media.class") ||
                        props.get_string_member ("media.class") != "Audio/Sink") {
                        continue;
                    }
                    if (!props.has_member ("node.name") ||
                        !object.has_member ("id")) {
                        continue;
                    }
                    int id = (int) object.get_int_member ("id");
                    string name = props.get_string_member ("node.name");
                    string description = props.has_member ("node.description")
                        ? props.get_string_member ("node.description") : name;
                    int volume = 0;
                    bool muted = false;
                    wpctl_values (id, out volume, out muted);
                    result.add (new PipeWireSink (
                        id, name, description, volume, muted, id == default_id));
                }
            } catch (Error e) {
                warning ("Cannot enumerate PipeWire sinks: %s", e.message);
            }
            return result;
        }

        private int sink_id (string name) {
            foreach (var sink in list_sinks ()) {
                if (sink.name == name) {
                    return sink.id;
                }
            }
            return 0;
        }

        private int default_sink_id () {
            try {
                string output;
                string error_output;
                int status;
                Process.spawn_sync (
                    null, {"wpctl", "status"},
                    null, SpawnFlags.SEARCH_PATH,
                    null, out output, out error_output, out status);
                bool sinks_section = false;
                foreach (string line in output.split ("\n")) {
                    if (line.contains ("├─ Sinks:") || line.contains ("└─ Sinks:")) {
                        sinks_section = true;
                        continue;
                    }
                    if (sinks_section && line.contains ("*")) {
                        string[] fields = line.strip ().split (".");
                        if (fields.length > 1) {
                            return int.parse (fields[0].replace ("*", "").strip ());
                        }
                    }
                    if (sinks_section &&
                        (line.contains ("├─ Sink endpoints:") ||
                         line.contains ("└─ Sink endpoints:"))) {
                        break;
                    }
                }
            } catch (Error e) {
            }
            return 0;
        }

        private void wpctl_values (int id, out int volume, out bool muted) {
            volume = 0;
            muted = false;
            try {
                string output;
                string error_output;
                int status;
                Process.spawn_sync (
                    null, {"wpctl", "get-volume", id.to_string ()},
                    null, SpawnFlags.SEARCH_PATH,
                    null, out output, out error_output, out status);
                muted = output.contains ("[MUTED]");
                int colon = output.index_of (":");
                if (colon >= 0) {
                    string value = output.substring (colon + 1).strip ();
                    string number = value.split (" ")[0];
                    double fraction = double.parse (number);
                    volume = (int) (fraction * 100);
                }
            } catch (Error e) {
            }
        }

        private void run_wpctl (string arguments) {
            try {
                string[] argv = {"wpctl"};
                foreach (string arg in arguments.split (" ")) {
                    argv += arg;
                }
                int wait_status;
                Process.spawn_sync (
                    null, argv, null, SpawnFlags.SEARCH_PATH,
                    null, null, null, out wait_status);
            } catch (SpawnError e) {
                warning ("Cannot control PipeWire audio sink: %s", e.message);
            }
        }

        private class PipeWireSink : Object {
            public string name;
            public string description;
            public int volume;
            public bool muted;
            public bool enabled;
            public int id;

            public PipeWireSink (int id, string name, string description, int volume,
                                 bool muted, bool enabled) {
                this.id = id;
                this.name = name;
                this.description = description;
                this.volume = volume;
                this.muted = muted;
                this.enabled = enabled;
            }
        }
    }
}
