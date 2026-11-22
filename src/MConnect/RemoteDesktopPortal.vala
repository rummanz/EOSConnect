namespace MConnect {

    public class RemoteDesktopPortal : Object {

        private const string BUS_NAME = "org.freedesktop.portal.Desktop";
        private const string OBJECT_PATH = "/org/freedesktop/portal/desktop";
        private const string INTERFACE_NAME = "org.freedesktop.portal.RemoteDesktop";
        private const string REQUEST_INTERFACE = "org.freedesktop.portal.Request";
        private const string SESSION_INTERFACE = "org.freedesktop.portal.Session";

        private DBusConnection connection;
        private string? session_path;
        private bool starting = false;
        private bool failed = false;
        private bool active = false;
        private bool input_error_logged = false;

        public RemoteDesktopPortal () {
            try {
                connection = Bus.get_sync (BusType.SESSION);
            } catch (Error e) {
                warning ("Cannot connect to the desktop portal bus: %s", e.message);
                failed = true;
            }
        }

        public bool is_active {
            get {
                return active;
            }
        }

        public void start () {
            if (active || starting || failed || connection == null) {
                return;
            }

            starting = true;
            var options = new VariantBuilder (new VariantType ("a{sv}"));
            options.add ("{sv}", "handle_token", new Variant.string (new_token ()));
            options.add ("{sv}", "session_handle_token", new Variant.string (new_token ()));
            call_portal ("CreateSession", new Variant ("(@a{sv})", options.end ()), (reply) => {
                string request_path = reply.get_child_value (0).get_string ();
                watch_request (request_path, (response, results) => {
                    if (response != 0) {
                        fail ("Portal denied remote input session creation");
                        return;
                    }

                    var session = results.lookup_value ("session_handle", new VariantType ("o"));
                    if (session == null) {
                        fail ("Portal created a remote input request without a session handle");
                        return;
                    }
                    session_path = session.get_string ();
                    select_devices ();
                });
            });
        }

        public void move_pointer (double dx, double dy) {
            if (!active) {
                return;
            }
            send_input ("NotifyPointerMotion", new Variant ("(o@a{sv}dd)",
                session_path, empty_options (), dx, dy));
        }

        public void pointer_button (uint button, bool pressed) {
            if (!active) {
                return;
            }
            send_input ("NotifyPointerButton", new Variant ("(o@a{sv}iu)",
                session_path, empty_options (), (int) button, pressed ? 1U : 0U));
        }

        public void scroll (double dx, double dy) {
            if (!active) {
                return;
            }
            send_input ("NotifyPointerAxis", new Variant ("(o@a{sv}dd)",
                session_path, empty_options (), dx, dy));
        }

        public void keyval (uint keyval, bool pressed) {
            if (!active) {
                return;
            }
            send_input ("NotifyKeyboardKeysym", new Variant ("(o@a{sv}iu)",
                session_path, empty_options (), (int) keyval, pressed ? 1U : 0U));
        }

        private void select_devices () {
            var options = new VariantBuilder (new VariantType ("a{sv}"));
            options.add ("{sv}", "types", new Variant.uint32 (3));
            options.add ("{sv}", "handle_token", new Variant.string (new_token ()));

            call_portal ("SelectDevices", new Variant ("(o@a{sv})",
                session_path, options.end ()), (reply) => {
                watch_request (reply.get_child_value (0).get_string (), (response, results) => {
                    if (response != 0) {
                        fail ("Portal denied selection of keyboard and pointer access");
                        return;
                    }
                    start_session ();
                });
            });
        }

        private void start_session () {
            var options = new VariantBuilder (new VariantType ("a{sv}"));
            options.add ("{sv}", "handle_token", new Variant.string (new_token ()));
            call_portal ("Start", new Variant ("(os@a{sv})",
                session_path, "", options.end ()), (reply) => {
                watch_request (reply.get_child_value (0).get_string (), (response, results) => {
                    if (response != 0) {
                        fail ("Portal denied the remote input session");
                        return;
                    }

                    active = true;
                    starting = false;
                    failed = false;
                    connection.signal_subscribe (
                        BUS_NAME,
                        SESSION_INTERFACE,
                        "Closed",
                        session_path,
                        null,
                        DBusSignalFlags.NONE,
                        (bus, sender, path, iface, signal_name, parameters) => {
                            active = false;
                            starting = false;
                            session_path = null;
                            warning ("Desktop portal closed the remote input session");
                        }
                    );
                    info ("Remote input is authorized by the desktop portal");
                });
            });
        }

        private void call_portal (string method, Variant parameters, owned PortalCall callback) {
            connection.call.begin (
                BUS_NAME,
                OBJECT_PATH,
                INTERFACE_NAME,
                method,
                parameters,
                new VariantType ("(o)"),
                DBusCallFlags.NONE,
                30000,
                null,
                (obj, result) => {
                    try {
                        callback (connection.call.end (result));
                    } catch (Error e) {
                        string? remote_error = DBusError.get_remote_error (e);
                        if (method == "CreateSession" &&
                            (remote_error == "org.freedesktop.DBus.Error.UnknownMethod" ||
                             remote_error == "org.freedesktop.DBus.Error.UnknownInterface" ||
                             remote_error == "org.freedesktop.DBus.Error.UnknownObject")) {
                            fail ("This desktop's portal does not provide RemoteDesktop support");
                            return;
                        }
                        fail ("Desktop portal %s call failed: %s".printf (method, e.message));
                    }
                }
            );
        }

        private void watch_request (string path, owned PortalResponse callback) {
            uint subscription_id = 0;
            subscription_id = connection.signal_subscribe (
                BUS_NAME,
                REQUEST_INTERFACE,
                "Response",
                path,
                null,
                DBusSignalFlags.NONE,
                (bus, sender, object_path, iface, signal_name, parameters) => {
                    connection.signal_unsubscribe (subscription_id);
                    callback (
                        parameters.get_child_value (0).get_uint32 (),
                        parameters.get_child_value (1)
                    );
                }
            );
        }

        private void send_input (string method, Variant parameters) {
            connection.call.begin (
                BUS_NAME,
                OBJECT_PATH,
                INTERFACE_NAME,
                method,
                parameters,
                null,
                DBusCallFlags.NONE,
                1000,
                null,
                (obj, result) => {
                    try {
                        connection.call.end (result);
                    } catch (Error e) {
                        if (!input_error_logged) {
                            warning ("Desktop portal rejected remote input: %s", e.message);
                            input_error_logged = true;
                        }
                    }
                }
            );
        }

        private Variant empty_options () {
            return new VariantBuilder (new VariantType ("a{sv}")).end ();
        }

        private string new_token () {
            return "eosconnect_%s".printf (Uuid.string_random ().replace ("-", "_"));
        }

        private void fail (string reason) {
            warning ("%s", reason);
            failed = true;
            starting = false;
            active = false;
            session_path = null;
        }

        private delegate void PortalCall (Variant reply);
        private delegate void PortalResponse (uint response, Variant results);
    }
}
