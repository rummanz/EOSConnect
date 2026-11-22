/**
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
namespace MConnect {

    public class MousepadHandler : Object, PacketHandlerInterface {

        public const string MOUSEPAD_REQUEST = "kdeconnect.mousepad.request";
        public const string MOUSEPAD = "kdeconnect.mousepad";

        private Gdk.Display? display;
        private RemoteDesktopPortal? portal;
        private bool wayland;

        private MousepadHandler () {
            wayland = Environment.get_variable ("XDG_SESSION_TYPE") == "wayland";
            if (wayland) {
                portal = new RemoteDesktopPortal ();
            } else if (!Atspi.is_initialized ()) {
                Atspi.init ();
                if (!Atspi.is_initialized ()) {
                    warning ("Failed to initialize AT-SPI; remote input is unavailable");
                }
            }

            display = Gdk.Display.get_default ();
            if (display == null) {
                warning ("Failed to obtain the default display for remote input");
            }
        }

        public static MousepadHandler instance () {
            return new MousepadHandler ();
        }

        public string get_pkt_type () {
            return MOUSEPAD_REQUEST;
        }

        public void use_device (Device dev) {
            debug ("Enable remote mouse and keyboard input from %s", dev.to_string ());
            dev.message.connect (message);
        }

        public void release_device (Device dev) {
            debug ("Disable remote mouse and keyboard input from %s", dev.to_string ());
            dev.message.disconnect (message);
        }

        private void message (Device dev, Packet pkt) {
            if (pkt.pkt_type != MOUSEPAD_REQUEST && pkt.pkt_type != MOUSEPAD) {
                return;
            }

            debug ("Received remote input packet from %s", dev.to_string ());
            if (wayland) {
                if (!portal.is_active) {
                    portal.start ();
                    return;
                }
                handle_wayland_input (pkt);
                return;
            }

            if (display == null) {
                warning ("Cannot handle remote input: no display is available");
                return;
            }

            try {
                if (pkt.body.has_member ("singleclick")) {
                    send_click (1);
                } else if (pkt.body.has_member ("doubleclick")) {
                    send_click (1, true);
                } else if (pkt.body.has_member ("rightclick")) {
                    send_click (3);
                } else if (pkt.body.has_member ("middleclick")) {
                    send_click (2);
                } else if (pkt.body.has_member ("singlehold")) {
                    send_button_event (1, "p");
                } else if (pkt.body.has_member ("singlerelease")) {
                    send_button_event (1, "r");
                } else if (pkt.body.has_member ("dx") && pkt.body.has_member ("dy")) {
                    double dx = pkt.body.get_double_member ("dx");
                    double dy = pkt.body.get_double_member ("dy");
                    if (pkt.body.has_member ("scroll") &&
                        pkt.body.get_boolean_member ("scroll")) {
                        scroll (dx, dy);
                    } else {
                        move_cursor (dx, dy);
                    }
                } else if (pkt.body.has_member ("key")) {
                    send_text (
                        pkt.body.get_string_member ("key"),
                        pkt.body.has_member ("shift") && pkt.body.get_boolean_member ("shift"),
                        pkt.body.has_member ("ctrl") && pkt.body.get_boolean_member ("ctrl"),
                        pkt.body.has_member ("alt") && pkt.body.get_boolean_member ("alt"),
                        pkt.body.has_member ("super") && pkt.body.get_boolean_member ("super")
                    );
                } else if (pkt.body.has_member ("specialKey")) {
                    send_special_key (
                        (uint) pkt.body.get_int_member ("specialKey"),
                        pkt.body.has_member ("shift") && pkt.body.get_boolean_member ("shift"),
                        pkt.body.has_member ("ctrl") && pkt.body.get_boolean_member ("ctrl"),
                        pkt.body.has_member ("alt") && pkt.body.get_boolean_member ("alt"),
                        pkt.body.has_member ("super") && pkt.body.get_boolean_member ("super")
                    );
                } else {
                    debug ("Ignoring unrecognized remote input packet");
                }
            } catch (Error e) {
                warning ("Failed to handle remote input packet: %s", e.message);
            }
        }

        private void handle_wayland_input (Packet pkt) {
            if (pkt.body.has_member ("singleclick")) {
                click (272);
            } else if (pkt.body.has_member ("doubleclick")) {
                click (272);
                click (272);
            } else if (pkt.body.has_member ("rightclick")) {
                click (273);
            } else if (pkt.body.has_member ("middleclick")) {
                click (274);
            } else if (pkt.body.has_member ("singlehold")) {
                portal.pointer_button (272, true);
            } else if (pkt.body.has_member ("singlerelease")) {
                portal.pointer_button (272, false);
            } else if (pkt.body.has_member ("dx") && pkt.body.has_member ("dy")) {
                double dx = pkt.body.get_double_member ("dx");
                double dy = pkt.body.get_double_member ("dy");
                if (pkt.body.has_member ("scroll") &&
                    pkt.body.get_boolean_member ("scroll")) {
                    portal.scroll (dx, dy);
                } else {
                    portal.move_pointer (dx, dy);
                }
            } else if (pkt.body.has_member ("key")) {
                send_portal_text (
                    pkt.body.get_string_member ("key"),
                    get_bool (pkt, "shift"),
                    get_bool (pkt, "ctrl"),
                    get_bool (pkt, "alt"),
                    get_bool (pkt, "super")
                );
            } else if (pkt.body.has_member ("specialKey")) {
                send_portal_special_key (
                    (uint) pkt.body.get_int_member ("specialKey"),
                    get_bool (pkt, "shift"),
                    get_bool (pkt, "ctrl"),
                    get_bool (pkt, "alt"),
                    get_bool (pkt, "super")
                );
            }
        }

        private bool get_bool (Packet pkt, string member) {
            return pkt.body.has_member (member) && pkt.body.get_boolean_member (member);
        }

        private void click (uint button) {
            portal.pointer_button (button, true);
            portal.pointer_button (button, false);
        }

        private void send_portal_text (string text, bool shift, bool ctrl, bool alt, bool super) {
            send_portal_modifiers (shift, ctrl, alt, super, true);
            int index = 0;
            unichar character;
            while (text.get_next_char (ref index, out character)) {
                portal.keyval (Gdk.unicode_to_keyval (character), true);
                portal.keyval (Gdk.unicode_to_keyval (character), false);
            }
            send_portal_modifiers (shift, ctrl, alt, super, false);
        }

        private void send_portal_special_key (uint key, bool shift, bool ctrl, bool alt, bool super) {
            string? name = special_key_name (key);
            if (name == null) {
                warning ("Ignoring unsupported remote special key %u", key);
                return;
            }

            uint keyval = Gdk.keyval_from_name (name);
            if (keyval == 0) {
                warning ("Cannot map remote special key %s", name);
                return;
            }
            send_portal_modifiers (shift, ctrl, alt, super, true);
            portal.keyval (keyval, true);
            portal.keyval (keyval, false);
            send_portal_modifiers (shift, ctrl, alt, super, false);
        }

        private void send_portal_modifiers (bool shift, bool ctrl, bool alt, bool super, bool pressed) {
            if (shift) {
                portal.keyval (Gdk.keyval_from_name ("Shift_L"), pressed);
            }
            if (ctrl) {
                portal.keyval (Gdk.keyval_from_name ("Control_L"), pressed);
            }
            if (alt) {
                portal.keyval (Gdk.keyval_from_name ("Alt_L"), pressed);
            }
            if (super) {
                portal.keyval (Gdk.keyval_from_name ("Super_L"), pressed);
            }
        }

        private void move_cursor (double dx, double dy) throws Error {
            if (!Atspi.generate_mouse_event ((long) dx, (long) dy, "rel")) {
                warning ("AT-SPI did not generate a relative mouse movement");
            }
        }

        private void scroll (double dx, double dy) throws Error {
            if (dx > 0) {
                send_click (7);
            } else if (dx < 0) {
                send_click (6);
            }

            while (dy > 3.0) {
                send_click (5);
                dy /= 4.0;
            }
            while (dy < -3.0) {
                send_click (4);
                dy /= 4.0;
            }
        }

        private void send_click (int button, bool double_click = false) throws Error {
            send_button_event (button, "c");
            if (double_click) {
                send_button_event (button, "c");
            }
        }

        private void send_button_event (int button, string event_type) throws Error {
            int x;
            int y;
            display.get_default_seat ().get_pointer ().get_position (null, out x, out y);
            if (!Atspi.generate_mouse_event (x, y, "b%u%s".printf ((uint) button, event_type))) {
                warning ("AT-SPI did not generate mouse button %d event", button);
            }
        }

        private void send_text (string text, bool shift, bool ctrl, bool alt, bool super) throws Error {
            press_modifiers (shift, ctrl, alt, super);
            if (!Atspi.generate_keyboard_event (0, text, Atspi.KeySynthType.STRING)) {
                warning ("AT-SPI did not generate keyboard text");
            }
            release_modifiers (shift, ctrl, alt, super);
        }

        private void send_special_key (uint key, bool shift, bool ctrl, bool alt, bool super) throws Error {
            string? key_name = special_key_name (key);
            if (key_name == null) {
                warning ("Ignoring unsupported remote special key %u", key);
                return;
            }

            press_modifiers (shift, ctrl, alt, super);
            uint keyval = Gdk.keyval_from_name (key_name);
            if (!Atspi.generate_keyboard_event (
                (long) keyval,
                null,
                Atspi.KeySynthType.SYM
            )) {
                warning ("AT-SPI did not generate key %s", key_name);
            }
            release_modifiers (shift, ctrl, alt, super);
        }

        private void press_modifiers (bool shift, bool ctrl, bool alt, bool super) throws Error {
            if (shift) {
                synthesize_key ("Shift_L", Atspi.KeySynthType.PRESS);
            }
            if (ctrl) {
                synthesize_key ("Control_L", Atspi.KeySynthType.PRESS);
            }
            if (alt) {
                synthesize_key ("Alt_L", Atspi.KeySynthType.PRESS);
            }
            if (super) {
                synthesize_key ("Super_L", Atspi.KeySynthType.PRESS);
            }
        }

        private void release_modifiers (bool shift, bool ctrl, bool alt, bool super) throws Error {
            if (super) {
                synthesize_key ("Super_L", Atspi.KeySynthType.RELEASE);
            }
            if (alt) {
                synthesize_key ("Alt_L", Atspi.KeySynthType.RELEASE);
            }
            if (ctrl) {
                synthesize_key ("Control_L", Atspi.KeySynthType.RELEASE);
            }
            if (shift) {
                synthesize_key ("Shift_L", Atspi.KeySynthType.RELEASE);
            }
        }

        private void synthesize_key (string name, Atspi.KeySynthType synth_type) throws Error {
            uint keyval = Gdk.keyval_from_name (name);
            if (keyval == 0 || !Atspi.generate_keyboard_event ((long) keyval, null, synth_type)) {
                warning ("AT-SPI did not generate modifier key %s", name);
            }
        }

        private string? special_key_name (uint key) {
            switch (key) {
                case 1: return "BackSpace";
                case 2: return "Tab";
                case 4: return "Left";
                case 5: return "Up";
                case 6: return "Right";
                case 7: return "Down";
                case 8: return "Page_Up";
                case 9: return "Page_Down";
                case 10: return "Home";
                case 11: return "End";
                case 12: return "Return";
                case 13: return "Delete";
                case 14: return "Escape";
                case 15: return "Print";
                case 16: return "Scroll_Lock";
                case 17: return "Control_L";
                case 18: return "Alt_L";
                case 19: return "Shift_L";
                case 20: return "Super_L";
                case 21: return "F1";
                case 22: return "F2";
                case 23: return "F3";
                case 24: return "F4";
                case 25: return "F5";
                case 26: return "F6";
                case 27: return "F7";
                case 28: return "F8";
                case 29: return "F9";
                case 30: return "F10";
                case 31: return "F11";
                case 32: return "F12";
                default: return null;
            }
        }
    }
}
