using Gee;

namespace MConnect {

    public class MprisHandler : Object, PacketHandlerInterface {

        public const string MPRIS = "kdeconnect.mpris";
        public const string MPRIS_REQUEST = "kdeconnect.mpris.request";

        private DBusConnection? connection;
        private Gee.HashSet<string> subscribed_players;

        private MprisHandler () {
            subscribed_players = new Gee.HashSet<string> ();
            try {
                connection = Bus.get_sync (BusType.SESSION);
                connection.signal_subscribe (
                    "org.freedesktop.DBus",
                    "org.freedesktop.DBus",
                    "NameOwnerChanged",
                    "/org/freedesktop/DBus",
                    null,
                    DBusSignalFlags.NONE,
                    (bus, sender, path, iface, signal_name, parameters) => {
                        string name = parameters.get_child_value (0).get_string ();
                        if (!name.has_prefix ("org.mpris.MediaPlayer2.")) {
                            return;
                        }
                        foreach (Device dev in Core.instance ().devices_map.values) {
                            if (dev.is_active &&
                                dev.is_paired &&
                                dev.is_capabality_activated (MPRIS)) {
                                send_player_list (dev);
                            }
                        }
                    }
                );
            } catch (Error e) {
                warning ("Cannot connect to the session bus for MPRIS control: %s", e.message);
            }
        }

        public static MprisHandler instance () {
            return new MprisHandler ();
        }

        public string get_pkt_type () {
            return MPRIS;
        }

        public void use_device (Device dev) {
            dev.message.connect (message);
        }

        public void release_device (Device dev) {
            dev.message.disconnect (message);
        }

        private void message (Device dev, Packet pkt) {
            if ((pkt.pkt_type != MPRIS && pkt.pkt_type != MPRIS_REQUEST) ||
                connection == null) {
                return;
            }

            if (pkt.body.has_member ("albumArtUrl")) {
                send_album_art (dev, pkt);
                return;
            }

            if (pkt.body.has_member ("requestPlayerList") &&
                pkt.body.get_boolean_member ("requestPlayerList")) {
                send_player_list (dev);
                return;
            }

            if (pkt.body.has_member ("player") &&
                (pkt.body.has_member ("action") ||
                 pkt.body.has_member ("setVolume") ||
                 pkt.body.has_member ("Seek") ||
                 pkt.body.has_member ("SetPosition"))) {
                control_player (dev, pkt);
                return;
            }

            if (pkt.body.has_member ("requestNowPlaying") &&
                pkt.body.get_boolean_member ("requestNowPlaying")) {
                send_now_playing (dev, pkt.body.has_member ("player")
                    ? pkt.body.get_string_member ("player") : null);
            }

            if (pkt.body.has_member ("requestVolume") &&
                pkt.body.get_boolean_member ("requestVolume")) {
                send_volume (dev, pkt.body.has_member ("player")
                    ? pkt.body.get_string_member ("player") : null);
            }
        }

        private void send_player_list (Device dev) {
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("playerList");
            builder.begin_array ();
            foreach (string bus_name in list_player_names ()) {
                builder.add_string_value (player_name (bus_name));
            }
            builder.end_array ();
            builder.set_member_name ("supportAlbumArtPayload");
            builder.add_boolean_value (true);
            builder.end_object ();
            dev.send (new Packet (MPRIS, builder.get_root ().get_object (), 0));
        }

        private void send_now_playing (Device dev, string? player) {
            string? bus_name = resolve_player (player);

            var builder = new Json.Builder ();
            builder.begin_object ();
            if (bus_name == null) {
                builder.set_member_name ("player");
                builder.add_string_value ("");
            } else {
                string display_name = player_name (bus_name);
                builder.set_member_name ("player");
                builder.add_string_value (display_name);

                add_metadata_properties (builder, bus_name);
                add_boolean_property (builder, "isPlaying", bus_name,
                    "PlaybackStatus", "Playing");
                add_capability_properties (builder, bus_name);

                Variant? position = get_mpris_property (
                    bus_name, "org.mpris.MediaPlayer2.Player", "Position");
                if (position != null) {
                    builder.set_member_name ("pos");
                    builder.add_int_value (position.get_int64 () / 1000);
                }
                Variant? loop_status = get_mpris_property (
                    bus_name, "org.mpris.MediaPlayer2.Player", "LoopStatus");
                if (loop_status != null) {
                    builder.set_member_name ("loopStatus");
                    builder.add_string_value (loop_status.get_string ());
                }
                Variant? shuffle = get_mpris_property (
                    bus_name, "org.mpris.MediaPlayer2.Player", "Shuffle");
                if (shuffle != null) {
                    builder.set_member_name ("shuffle");
                    builder.add_boolean_value (shuffle.get_boolean ());
                }
                Variant? rate = get_mpris_property (
                    bus_name, "org.mpris.MediaPlayer2.Player", "Rate");
                if (rate != null) {
                    builder.set_member_name ("rate");
                    builder.add_double_value (rate.get_double ());
                }
            }
            builder.end_object ();
            dev.send (new Packet (MPRIS, builder.get_root ().get_object (), 0));
        }

        private void send_volume (Device dev, string? player) {
            string? bus_name = resolve_player (player);
            if (bus_name == null) {
                return;
            }
            Variant? volume = get_mpris_property (
                bus_name, "org.mpris.MediaPlayer2.Player", "Volume");
            if (volume == null) {
                return;
            }
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("player");
            builder.add_string_value (player_name (bus_name));
            builder.set_member_name ("volume");
            builder.add_int_value ((int64) (volume.get_double () * 100));
            builder.end_object ();
            dev.send (new Packet (MPRIS, builder.get_root ().get_object (), 0));
        }

        private void control_player (Device dev, Packet pkt) {
            string? player = resolve_player (pkt.body.get_string_member ("player"));
            if (player == null) {
                send_player_list (dev);
                return;
            }

            if (pkt.body.has_member ("action")) {
                string action = pkt.body.get_string_member ("action");
                if (action == "PlayPause") {
                    call_player (player, "PlayPause", null);
                } else if (action == "Play") {
                    call_player (player, "Play", null);
                } else if (action == "Pause") {
                    call_player (player, "Pause", null);
                } else if (action == "Stop") {
                    call_player (player, "Stop", null);
                } else if (action == "Next") {
                    call_player (player, "Next", null);
                } else if (action == "Previous") {
                    call_player (player, "Previous", null);
                }
            }

            if (pkt.body.has_member ("setVolume")) {
                set_property (player, "Volume",
                    new Variant.double (
                        pkt.body.get_int_member ("setVolume") / 100.0));
            }
            if (pkt.body.has_member ("setLoopStatus")) {
                set_property (player, "LoopStatus",
                    new Variant.string (pkt.body.get_string_member ("setLoopStatus")));
            }
            if (pkt.body.has_member ("setShuffle")) {
                set_property (player, "Shuffle",
                    new Variant.boolean (pkt.body.get_boolean_member ("setShuffle")));
            }
            if (pkt.body.has_member ("Seek")) {
                int64 offset = pkt.body.get_int_member ("Seek");
                if (offset >= -10000 && offset <= 10000) {
                    offset *= 1000;
                }
                call_player (player, "Seek",
                    new Variant ("(x)", offset));
            }
            if (pkt.body.has_member ("SetPosition")) {
                Variant? position = get_mpris_property (
                    player, "org.mpris.MediaPlayer2.Player", "Position");
                int64 target = pkt.body.get_int_member ("SetPosition") * 1000;
                int64 offset = target - (position != null ? position.get_int64 () : 0);
                call_player (player, "Seek", new Variant ("(x)", offset));
            }
        }

        private void call_player (string player, string method, Variant? parameters) {
            try {
                connection.call_sync (
                    player,
                    "/org/mpris/MediaPlayer2",
                    "org.mpris.MediaPlayer2.Player",
                    method,
                    parameters,
                    null,
                    DBusCallFlags.NONE,
                    1000);
            } catch (Error e) {
                warning ("MPRIS call %s failed: %s", method, e.message);
            }
        }

        private void set_property (string player, string property, Variant value) {
            try {
                connection.call_sync (
                    player,
                    "/org/mpris/MediaPlayer2",
                    "org.freedesktop.DBus.Properties",
                    "Set",
                    new Variant ("(ssv)", "org.mpris.MediaPlayer2.Player", property, value),
                    null,
                    DBusCallFlags.NONE,
                    1000);
            } catch (Error e) {
                warning ("Cannot set MPRIS property %s: %s", property, e.message);
            }
        }

        private Variant? get_mpris_property (string player, string interface_name, string property) {
            try {
                var reply = connection.call_sync (
                    player,
                    "/org/mpris/MediaPlayer2",
                    "org.freedesktop.DBus.Properties",
                    "Get",
                    new Variant ("(ss)", interface_name, property),
                    new VariantType ("(v)"),
                    DBusCallFlags.NONE,
                    1000);
                return reply.get_child_value (0).get_variant ();
            } catch (Error e) {
                return null;
            }
        }

        private void add_metadata_properties (Json.Builder builder, string player) {
            Variant? metadata = get_mpris_property (
                player, "org.mpris.MediaPlayer2.Player", "Metadata");
            if (metadata == null) {
                return;
            }

            Variant? title = metadata.lookup_value ("xesam:title", null);
            Variant? artist = metadata.lookup_value ("xesam:artist", null);
            Variant? album = metadata.lookup_value ("xesam:album", null);
            Variant? art_url = metadata.lookup_value ("mpris:artUrl", null);
            Variant? length = metadata.lookup_value ("mpris:length", null);
            Variant? url = metadata.lookup_value ("xesam:url", null);

            builder.set_member_name ("title");
            builder.add_string_value (title != null ? title.get_string () : "");
            builder.set_member_name ("artist");
            builder.add_string_value (artist != null ? string.joinv (", ", artist.get_strv ()) : "");
            builder.set_member_name ("album");
            builder.add_string_value (album != null ? album.get_string () : "");
            builder.set_member_name ("albumArtUrl");
            builder.add_string_value (art_url != null ? art_url.get_string () : "");
            builder.set_member_name ("length");
            builder.add_int_value (length != null ? length.get_int64 () / 1000 : -1);
            builder.set_member_name ("url");
            builder.add_string_value (url != null ? url.get_string () : "");
        }

        private void add_boolean_property (Json.Builder builder, string output_name,
                                           string player, string property,
                                           string positive_value) {
            Variant? value = get_mpris_property (
                player, "org.mpris.MediaPlayer2.Player", property);
            if (value == null) {
                return;
            }
            builder.set_member_name (output_name);
            builder.add_boolean_value (value.get_string () == positive_value);
        }

        private void add_capability_properties (Json.Builder builder, string player) {
            add_capability (builder, "canPause", player, "CanPause");
            add_capability (builder, "canPlay", player, "CanPlay");
            add_capability (builder, "canGoNext", player, "CanGoNext");
            add_capability (builder, "canGoPrevious", player, "CanGoPrevious");
            add_capability (builder, "canSeek", player, "CanSeek");
        }

        private void add_capability (Json.Builder builder, string output_name,
                                     string player, string property) {
            Variant? value = get_mpris_property (
                player, "org.mpris.MediaPlayer2.Player", property);
            builder.set_member_name (output_name);
            builder.add_boolean_value (value != null && value.get_boolean ());
        }

        private void subscribe_player (string bus_name) {
            if (subscribed_players.contains (bus_name) || connection == null) {
                return;
            }
            subscribed_players.add (bus_name);
            connection.signal_subscribe (
                bus_name,
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
                "/org/mpris/MediaPlayer2",
                null,
                DBusSignalFlags.NONE,
                (bus, sender, path, iface, signal_name, parameters) => {
                    foreach (Device dev in Core.instance ().devices_map.values) {
                        if (dev.is_active &&
                            dev.is_paired &&
                            dev.is_capabality_activated (MPRIS)) {
                            send_now_playing (dev, bus_name);
                            send_volume (dev, bus_name);
                        }
                    }
                }
            );
        }

        private string[] list_player_names () {
            string[] names = {};
            if (connection == null) {
                return names;
            }
            try {
                var reply = connection.call_sync (
                    "org.freedesktop.DBus",
                    "/org/freedesktop/DBus",
                    "org.freedesktop.DBus",
                    "ListNames",
                    null,
                    new VariantType ("(as)"),
                    DBusCallFlags.NONE,
                    1000);
                foreach (string name in reply.get_child_value (0).get_strv ()) {
                    if (name.has_prefix ("org.mpris.MediaPlayer2.") &&
                        !name.contains (".kdeconnect.") &&
                        name != "org.mpris.MediaPlayer2.playerctld") {
                        names += name;
                        subscribe_player (name);
                    }
                }
            } catch (Error e) {
                warning ("Cannot enumerate MPRIS players: %s", e.message);
            }
            return names;
        }

        private string? resolve_player (string? player) {
            string[] names = list_player_names ();
            if (player == null || player.length == 0) {
                return names.length > 0 ? names[0] : null;
            }
            foreach (string bus_name in names) {
                if (bus_name == player || player_name (bus_name) == player) {
                    return bus_name;
                }
            }
            if (player.has_prefix ("org.mpris.MediaPlayer2.")) {
                foreach (string bus_name in names) {
                    if (bus_name == player) {
                        return bus_name;
                    }
                }
            }
            return null;
        }

        private string player_name (string bus_name) {
            try {
                Variant? identity = get_mpris_property (
                    bus_name, "org.mpris.MediaPlayer2", "Identity");
                if (identity != null && identity.get_string ().length > 0) {
                    return identity.get_string ();
                }
            } catch (Error e) {
            }
            string name = bus_name.replace ("org.mpris.MediaPlayer2.", "");
            return name != "" ? name : bus_name;
        }

        private Gee.ArrayList<string> paused_for_call;

        public void pause_media_for_call () {
            if (paused_for_call == null) {
                paused_for_call = new Gee.ArrayList<string> ();
            }
            paused_for_call.clear ();
            foreach (string bus_name in list_player_names ()) {
                Variant? status = get_mpris_property (
                    bus_name, "org.mpris.MediaPlayer2.Player", "PlaybackStatus");
                if (status != null && status.get_string () == "Playing") {
                    call_player (bus_name, "Pause", null);
                    paused_for_call.add (bus_name);
                }
            }
        }

        public void resume_media_after_call () {
            if (paused_for_call == null) {
                paused_for_call = new Gee.ArrayList<string> ();
            }
            if (paused_for_call.size == 0) {
                Gee.ArrayList<string> playing_before_call =
                    new Gee.ArrayList<string> ();
                foreach (string bus_name in list_player_names ()) {
                    Variant? status = get_mpris_property (
                        bus_name, "org.mpris.MediaPlayer2.Player", "PlaybackStatus");
                    if (status != null && status.get_string () == "Paused") {
                        playing_before_call.add (bus_name);
                    }
                }
                if (playing_before_call.size == 0) {
                    return;
                }
                paused_for_call.add_all (playing_before_call);
            }

            debug ("Resuming media paused for incoming call");
            string[] to_resume = paused_for_call.to_array ();
            paused_for_call.clear ();
            foreach (string bus_name in to_resume) {
                resume_player_after_call (bus_name);
            }
            Timeout.add (500, () => {
                foreach (string bus_name in to_resume) {
                    Variant? status = get_mpris_property (
                        bus_name, "org.mpris.MediaPlayer2.Player", "PlaybackStatus");
                    if (status != null && status.get_string () != "Playing") {
                        debug ("Retrying media resume for %s", bus_name);
                        resume_player_after_call (bus_name);
                    }
                }
                return false;
            });
            Timeout.add (1500, () => {
                foreach (string bus_name in to_resume) {
                    Variant? status = get_mpris_property (
                        bus_name, "org.mpris.MediaPlayer2.Player", "PlaybackStatus");
                    if (status != null && status.get_string () != "Playing") {
                        debug ("Retrying media resume again for %s", bus_name);
                        resume_player_after_call (bus_name);
                    }
                }
                return false;
            });
        }

        private void resume_player_after_call (string bus_name) {
            Variant? can_play = get_mpris_property (
                bus_name, "org.mpris.MediaPlayer2.Player", "CanPlay");
            if (can_play == null || can_play.get_boolean ()) {
                debug ("Sending Play to %s after call", bus_name);
                call_player (bus_name, "Play", null);
            } else {
                warning ("Cannot resume %s: player reports CanPlay=false", bus_name);
            }
        }

        private void send_album_art (Device dev, Packet pkt) {
            if (!pkt.body.has_member ("player") || !pkt.body.has_member ("albumArtUrl")) {
                return;
            }
            string player = pkt.body.get_string_member ("player");
            string? bus_name = resolve_player (player);
            if (bus_name == null) {
                return;
            }
            string requested_url = pkt.body.get_string_member ("albumArtUrl");
            if (!requested_url.has_prefix ("file://")) {
                return;
            }
            Variant? metadata = get_mpris_property (
                bus_name, "org.mpris.MediaPlayer2.Player", "Metadata");
            if (metadata == null) {
                return;
            }
            Variant? art_url = metadata.lookup_value ("mpris:artUrl", null);
            if (art_url == null || art_url.get_string () != requested_url) {
                return;
            }
            File file = File.new_for_uri (requested_url);
            if (!file.query_exists ()) {
                return;
            }
            try {
                FileInputStream input = file.read ();
                FileInfo info = file.query_info (
                    FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
                uint port;
                var listener = Core.instance ().transfer_manager.make_listener (out port);
                if (listener == null) {
                    warning ("Cannot allocate album-art transfer listener");
                    return;
                }
                var transfer = new UploadTransfer (dev, listener, input, info.get_size ());
                Core.instance ().transfer_manager.push_job (transfer);
                transfer.start_async.begin ();

                var builder = new Json.Builder ();
                builder.begin_object ();
                builder.set_member_name ("transferringAlbumArt");
                builder.add_boolean_value (true);
                builder.set_member_name ("player");
                builder.add_string_value (player);
                builder.set_member_name ("albumArtUrl");
                builder.add_string_value (requested_url);
                builder.end_object ();
                var packet = new Packet (MPRIS, builder.get_root ().get_object ());
                packet.payload = Packet.Payload () {
                    size = info.get_size (),
                    port = port
                };
                dev.send (packet);
            } catch (Error e) {
                warning ("Cannot send MPRIS album art: %s", e.message);
            }
        }
    }
}
