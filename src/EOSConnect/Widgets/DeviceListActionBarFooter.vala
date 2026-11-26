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
 * gyan000 <gyan000 (at] ijaz.fr>
 */
using MConnect;

namespace EOSConnect.Widgets {

    public class DeviceListActionBarFooter : Gtk.ActionBar {

        public MainWindow main_window { get; construct; }

        private Gtk.Button button_remove;
        private Device _current_device;

        public DeviceListActionBarFooter (MainWindow main_window) {
            Object (main_window: main_window);
        }

        construct {
            button_remove = new Gtk.Button.from_icon_name ("list-remove-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
            button_remove.sensitive = false;
            button_remove.tooltip_text = _("Forget selected device");

            get_style_context ().add_class (Gtk.STYLE_CLASS_INLINE_TOOLBAR);
            add (button_remove);

            button_remove.clicked.connect (() => {
                if (_current_device != null) {
                    _current_device.unpair.begin ();
                }
            });
        }

        public void update_ui (Device device) {
            _current_device = device;
            button_remove.sensitive = device.is_paired;
        }
    }
}
