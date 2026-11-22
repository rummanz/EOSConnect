namespace MConnect {

    public class ClipboardHandler : Object, PacketHandlerInterface {

        public const string CLIPBOARD = "kdeconnect.clipboard";

        private Gtk.Clipboard clipboard;
        private bool ignore_owner_change = false;

        private ClipboardHandler () {
            var display = Gdk.Display.get_default ();
            clipboard = (display != null)
                ? Gtk.Clipboard.get_for_display (display, Gdk.SELECTION_CLIPBOARD)
                : Gtk.Clipboard.get (Gdk.SELECTION_CLIPBOARD);

            clipboard.owner_change.connect ((event) => {
                if (ignore_owner_change) {
                    ignore_owner_change = false;
                    return;
                }
                send_local_clipboard ();
            });
        }

        public static ClipboardHandler instance () {
            return new ClipboardHandler ();
        }

        public string get_pkt_type () {
            return CLIPBOARD;
        }

        public void use_device (Device dev) {
            dev.message.connect (message);
        }

        public void release_device (Device dev) {
            dev.message.disconnect (message);
        }

        private void message (Device dev, Packet pkt) {
            if (pkt.pkt_type != CLIPBOARD ||
                !pkt.body.has_member ("content")) {
                return;
            }

            ignore_owner_change = true;
            clipboard.set_text (pkt.body.get_string_member ("content"), -1);
            clipboard.store ();
        }

        private void send_local_clipboard () {
            string? text = clipboard.wait_for_text ();
            if (text == null || text.length == 0) {
                return;
            }

            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("content");
            builder.add_string_value (text);
            builder.end_object ();

            foreach (Device device in Core.instance ().devices_map.values) {
                if (device.is_active &&
                    device.is_paired &&
                    device.is_capabality_activated (CLIPBOARD)) {
                    device.send (new Packet (CLIPBOARD, builder.get_root ().get_object()));
                }
            }
        }
    }
}
