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
using EOSConnect;
using EOSConnect.Plugin;

namespace MConnect {

    class TelephonyHandler : Object, PacketHandlerInterface {

        public signal void telephony_update ();

        public const string TELEPHONY = "kdeconnect.telephony";
        public const string SMS_REQUEST = "kdeconnect.sms.request";
        public const string TELEPHONY_REQUEST_MUTE = "kdeconnect.telephony.request_mute";

        public DateTime last_sms_received_date_time { get; private set; }
        private Gee.HashMap<string, string> call_notification_ids;
        private string? mute_device_id;
        public string get_pkt_type () {
            return TELEPHONY;
        }

        private TelephonyHandler () {
            call_notification_ids = new Gee.HashMap<string, string> ();
        }

        public static TelephonyHandler instance () {
            return new TelephonyHandler ();
        }

        public void use_device (Device dev) {
            debug ("Use device %s for telephony.", dev.to_string ());
            dev.message.connect (this.message);
        }

        public void release_device (Device dev) {
            debug ("Release device %s", dev.to_string ());
            dev.message.disconnect (this.message);
        }

        public void message (Device device, Packet pkt) {

            if (pkt.pkt_type != TELEPHONY || device.is_capabality_activated (TELEPHONY) == false) {
                return;
            }

            info ("Got telephony packet.");
            if (pkt.body.has_member ("isCancel") &&
                is_true_member (pkt.body, "isCancel")) {
                withdraw_call_notification (device);
                MprisHandler.instance ().resume_media_after_call ();
                return;
            }
            if (!pkt.body.has_member ("event")) {
                return;
            }

            string id = pkt.id.to_string ();
            string event = pkt.body.get_string_member ("event");
            string phone_number = pkt.body.has_member ("phoneNumber")
                ? pkt.body.get_string_member ("phoneNumber") : _("unknown number");
            string contact_name = pkt.body.has_member ("contactName") ? pkt.body.get_string_member ("contactName") : phone_number;
            string phone_thumbnail = pkt.body.has_member ("phoneThumbnail")
                ? pkt.body.get_string_member ("phoneThumbnail") : "";
            string message_body = pkt.body.has_member ("messageBody")
                ? pkt.body.get_string_member ("messageBody") : "";

            string device_name = (device.custom_name.length > 0) ? device.custom_name : device.name;
            string notif_summary = "";
            string notif_body = "";
            bool set_notification_icon = false;
            string notification_icon_pathname = "";

            if (event == "sms") {
                last_sms_received_date_time = new DateTime.now_utc ();
                SMSContact sms_contact = new SMSContact (phone_number, contact_name, device.id,
                                                         phone_thumbnail, contact_name);
                if (((EOSConnect.Plugin.Telephony)device.get_plugin (TELEPHONY)).is_active) {
                    SMSStore.instance ().add_sms (
                        device,
                        new SMS (
                            message_body,
                            SMS.FROM_CONTACT,
                            SMS.FROM_TYPE_TELEPHONY,
                            last_sms_received_date_time),
                        sms_contact);
                }

                notif_summary = "SMS\u0040" + device_name;
                notif_body = "<i>" + contact_name + "</i>\n";
                notif_body += message_body;

                if (sms_contact.contact_image_path.length > 10) {
                    notification_icon_pathname = sms_contact.contact_image_path;
                    set_notification_icon = true;
                }
            }

            if (event == "ringing" || event == "missedCall") {
                if (event == "ringing") {
                    MprisHandler.instance ().pause_media_for_call ();
                }
                if (event == "missedCall") {
                    MprisHandler.instance ().resume_media_after_call ();
                }
                notif_summary = event == "ringing" ? "Incoming call" : "Missed call";
                notif_summary = notif_summary + "\u0040" + device_name;
                notif_body = contact_name;
                if (phone_number != "" && phone_number != contact_name) {
                    notif_body = contact_name + "\n" + phone_number;
                }
                if (phone_thumbnail.length > 10) {
                    var sms_contact = new SMSContact (
                        phone_number, contact_name, device.id, phone_thumbnail, contact_name);
                    if (sms_contact.set_contact_image ()) {
                        notification_icon_pathname = sms_contact.contact_image_path;
                        set_notification_icon = notification_icon_pathname.length > 10;
                    }
                }
            } else if (event == "talking") {
                withdraw_call_notification (device);
                return;
            } else if (event != "sms") {
                debug ("Ignoring unsupported telephony event %s", event);
                return;
            }

            if (event == "sms") {
                if (device.is_capabality_activated (NotificationHandler.NOTIFICATION) == false ||
                   ((Plugin.Notification)device.get_plugin (NotificationHandler.NOTIFICATION)).settings_receive_is_active == false) {
                    debug ("Notification deactivated for device %s", device.custom_name);
                    return;
                }
            }

            var notification = new GLib.Notification (notif_summary);
            notification.set_body (notif_body);

            if (event == "sms") {
                // Action defined in EOSConnect._init_sms_history_view ()
                notification.set_default_action ("app.telephony-open-sms-tab");
            }
            if (event == "ringing") {
                string call_id = "call_" + device.id + "_" + phone_number;
                call_notification_ids.@set (device.id, call_id);
                mute_device_id = device.id;
                notification.add_button ("Mute call", "app.telephony-mute-call");
                id = call_id;
            } else if (event == "missedCall") {
                id = "missed_call_" + device.id + "_" + phone_number;
                call_notification_ids.@unset (device.id);
            }

            if (set_notification_icon == true) {
                notification.set_icon (new FileIcon (File.new_for_path (notification_icon_pathname)));
            }

            try {
                Core.instance ().application.send_notification (id, notification);
            } catch (Error e) {
                warning ("Unable to send the telephony notification. :/");
            }


            //const string[] accepted_events = { "event" "ringing", "missedCall" };

            //debug ("Call from %s, status %s", number, event);
            //
            // if (event in accepted_events) {
            //     string summary = "Other event";
            //
            //     if (ev == "ringing")
            //         summary = "Incoming call";
            //     if (ev == "missedCall")
            //         summary = "Missed call";
            //
            //     // check if ringing was cancelled
            //     if (ev == "missedCall" && pkt.body.has_member ("isCancel")) {
            //         bool cancelled = pkt.body.get_boolean_member ("isCancel");
            //         if (cancelled == true) {
            //             debug ("call cancelled");
            //             return;
            //         }
            //     }
            //
            //     // telephony packets have no time information
            //     var time = new DateTime.now_local ();
            //     number = "%s %s".printf (time.format ("%X"), number);
            //
            //     var notif = new Notify.Notification (summary, number,
            //                                          "phone");
            //     try {
            //         notif.show ();
            //     } catch (Error e) {
            //         critical ("failed to show notification: %s", e.message);
            //     }
            // }
        }

        //public void handle_sms_notification (Device device, Packet pkt) {
        //    debug ("Handling missed SMS from notifiation.");
        //    // TOCHECK There's' a "time" field, but, does not seems to be a unix timestamp. And no mention in kdeconnect.
        //    //DateTime glop = new DateTime.from_unix_local (pkt.body.get_string_member ("time").to_int());
        //    //print (">> %s -> %s", pkt.body.get_string_member ("time").to_string (), glop.to_string ());
        //    //return;
        //    SMSStore.instance ().handle_missed_sms (
        //        device,
        //        new SMS (
        //            pkt.body.get_string_member ("text"),
        //            SMS.FROM_CONTACT,
        //            SMS.FROM_TYPE_NOTIFICATION,
        //            new DateTime.now_utc ()
        //        ),
        //        pkt.body.get_string_member ("title"));
        //}

        private bool is_true_member (Json.Object body, string member) {
            if (!body.has_member (member)) {
                return false;
            }
            var node = body.get_member (member);
            if (node.get_node_type () == Json.NodeType.VALUE) {
                try {
                    return node.get_boolean ();
                } catch (Error e) {
                }
                string? value = node.get_string ();
                return value != null &&
                    (value.down () == "true" || value == "1");
            }
            return false;
        }

        private void withdraw_call_notification (Device device) {
            string? notification_id;
            call_notification_ids.unset (device.id, out notification_id);
            if (notification_id == null) {
                notification_id = "call_" + device.id;
            }
            try {
                Core.instance ().application.withdraw_notification (notification_id);
            } catch (Error e) {
                warning ("Unable to close call notification: %s", e.message);
            }
            if (mute_device_id == device.id) {
                mute_device_id = null;
            }
        }

        public void mute_current_call () {
            if (mute_device_id == null) {
                return;
            }
            foreach (Device device in Core.instance ().devices_map.values) {
                if (device.id == mute_device_id) {
                    var builder = new Json.Builder ();
                    builder.begin_object ();
                    builder.set_member_name ("action");
                    builder.add_string_value ("mute");
                    builder.end_object ();
                    device.send (new Packet (TELEPHONY_REQUEST_MUTE,
                                             builder.get_root ().get_object()));
                    return;
                }
            }
        }

        /**
         * make_sms_packet:
         * @number: recipient's number
         * @message: message
         *
         * @return allocated packet
         */
        private Packet _make_sms_packet (string number, string message) {
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("sendSms");
            builder.add_boolean_value (true);
            builder.set_member_name ("phoneNumber");
            builder.add_string_value (number);
            builder.set_member_name ("messageBody");
            builder.add_string_value (message);
            builder.end_object ();

            return new Packet (SMS_REQUEST, builder.get_root ().get_object ());
        }

        /**
         * send_sms:
         *
         * Reques to send an SMS to @number with message @message.
         */
        public void send_sms (Device device, string number, string message) {
            device.send (_make_sms_packet (number, message));
        }
    }
}
