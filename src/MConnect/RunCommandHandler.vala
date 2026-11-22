namespace MConnect {

    public class RunCommandHandler : Object, PacketHandlerInterface {

        public const string RUNCOMMAND = "kdeconnect.runcommand";
        public const string RUNCOMMAND_REQUEST = "kdeconnect.runcommand.request";
        public const string SETTINGS_ID = "com.github.gyan000.eos-connect";

        private Settings? settings;
        private Gee.ArrayList<Pid> child_processes;
        private Gee.ArrayList<Device> devices;

        private RunCommandHandler () {
            settings = new Settings (SETTINGS_ID);
            child_processes = new Gee.ArrayList<Pid> ();
            devices = new Gee.ArrayList<Device> ();
            settings.changed.connect ((key) => {
                if (key != "kdeconnect-runcommands") {
                    return;
                }
                foreach (Device dev in devices) {
                    if (dev.is_active && dev.is_paired) {
                        send_command_list (dev);
                    }
                }
            });
        }

        public static RunCommandHandler instance () {
            return new RunCommandHandler ();
        }

        public string get_pkt_type () {
            return RUNCOMMAND;
        }

        public void use_device (Device dev) {
            dev.message.connect (message);
            dev.paired.connect (device_paired);
            if (!devices.contains (dev)) {
                devices.add (dev);
            }
            if (dev.is_active && dev.is_paired) {
                send_command_list (dev);
            }
        }

        public void release_device (Device dev) {
            dev.message.disconnect (message);
            dev.paired.disconnect (device_paired);
            devices.remove (dev);
        }

        private void device_paired (bool paired) {
            if (!paired) {
                return;
            }
            foreach (Device dev in devices) {
                if (dev.is_active && dev.is_paired) {
                    send_command_list (dev);
                }
            }
        }

        private void message (Device dev, Packet pkt) {
            if ((pkt.pkt_type != RUNCOMMAND && pkt.pkt_type != RUNCOMMAND_REQUEST) ||
                settings == null) {
                return;
            }

            if ((pkt.body.has_member ("request") &&
                 pkt.body.get_boolean_member ("request")) ||
                (pkt.body.has_member ("requestCommandList") &&
                 pkt.body.get_boolean_member ("requestCommandList"))) {
                send_command_list (dev);
                return;
            }

            if (pkt.body.has_member ("stop") &&
                pkt.body.get_boolean_member ("stop")) {
                stop_commands ();
                return;
            }
            if (pkt.body.has_member ("setup") &&
                pkt.body.get_boolean_member ("setup")) {
                info ("Remote command setup requested by %s", dev.name);
                return;
            }

            string key = "";
            if (pkt.body.has_member ("key")) {
                key = pkt.body.get_string_member ("key");
            } else if (pkt.body.has_member ("commandId")) {
                key = pkt.body.get_string_member ("commandId");
            }
            if (key != "") {
                execute_command (key);
            }
        }

        private void send_command_list (Device dev) {
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("commandList");
            builder.add_string_value (settings.get_string ("kdeconnect-runcommands"));
            builder.set_member_name ("canAddCommand");
            builder.add_boolean_value (true);
            builder.end_object ();
            dev.send (new Packet (RUNCOMMAND, builder.get_root ().get_object (), 0));
        }

        private void execute_command (string key) {
            foreach (var command in configured_commands ()) {
                if (command.id == key) {
                    try {
                        Pid child_pid;
                        Process.spawn_async (
                            null,
                            {"/bin/sh", "-c", command.command},
                            null,
                            SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                            null,
                            out child_pid);
                        child_processes.add (child_pid);
                        ChildWatch.add (child_pid, (pid, status) => {
                            child_processes.remove (pid);
                            Process.close_pid (pid);
                        });
                        info ("Started configured remote command %s", key);
                    } catch (SpawnError e) {
                        warning ("Cannot start configured remote command %s: %s",
                                 key, e.message);
                    }
                    return;
                }
            }
            warning ("Ignoring unknown remote command ID %s", key);
        }

        private void stop_commands () {
            foreach (Pid pid in child_processes.to_array ()) {
                Posix.kill (pid, Posix.SIGKILL);
            }
            child_processes.clear ();
        }

        private Gee.ArrayList<ConfiguredCommand> configured_commands () {
            var result = new Gee.ArrayList<ConfiguredCommand> ();
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (settings.get_string ("kdeconnect-runcommands"), -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    return result;
                }
                var object = root.get_object ();
                object.foreach_member ((object, id, node) => {
                    if (node == null || node.get_node_type () != Json.NodeType.OBJECT) {
                        return;
                    }
                    var command = node.get_object ();
                    if (!command.has_member ("name") ||
                        !command.has_member ("command")) {
                        return;
                    }
                    result.add (new ConfiguredCommand (
                        id,
                        command.get_string_member ("name"),
                        command.get_string_member ("command")
                    ));
                });
            } catch (Error e) {
                warning ("Cannot read configured remote commands: %s", e.message);
            }
            return result;
        }

        private class ConfiguredCommand : Object {
            public string id;
            public string name;
            public string command;

            public ConfiguredCommand (string id, string name, string command) {
                this.id = id;
                this.name = name;
                this.command = command;
            }
        }
    }
}
