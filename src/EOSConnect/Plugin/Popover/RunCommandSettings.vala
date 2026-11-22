namespace EOSConnect.Plugin.Popover {

    public class RunCommandSettings : Gtk.Popover {

        public MConnect.Device device { get; construct; }

        private Gtk.ListBox list_box;
        private GLib.Settings global_settings;

        public RunCommandSettings (MConnect.Device device, Gtk.Widget? relative_to) {
            Object (
                device: device,
                relative_to: relative_to,
                modal: true,
                position: Gtk.PositionType.BOTTOM
            );
        }

        construct {
            global_settings = new GLib.Settings (
                "com.github.gyan000.eos-connect");
            var grid = new Gtk.Grid ();
            grid.orientation = Gtk.Orientation.VERTICAL;
            grid.row_spacing = 6;
            grid.margin = 12;
            grid.width_request = 420;

            var title = new Granite.HeaderLabel (_("Remote commands"));
            title.halign = Gtk.Align.START;
            grid.add (title);

            list_box = new Gtk.ListBox ();
            list_box.selection_mode = Gtk.SelectionMode.NONE;
            var scrolled = new Gtk.ScrolledWindow (null, null);
            scrolled.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            scrolled.height_request = 220;
            scrolled.add (list_box);
            grid.add (scrolled);

            var add_button = new Gtk.Button.with_label (_("Add command"));
            add_button.halign = Gtk.Align.END;
            add_button.clicked.connect (() => edit_command (null));
            grid.add (add_button);

            add (grid);
            reload ();
        }

        private void reload () {
            foreach (Gtk.Widget child in list_box.get_children ()) {
                list_box.remove (child);
            }

            foreach (var command in load_commands ()) {
                var row = new Gtk.ListBoxRow ();
                var row_grid = new Gtk.Grid ();
                row_grid.column_spacing = 8;
                row_grid.margin = 6;

                var name = new Gtk.Label (command.name);
                name.xalign = 0;
                name.hexpand = true;
                name.get_style_context ().add_class (Granite.STYLE_CLASS_H3_LABEL);

                var code = new Gtk.Label (command.command);
                code.xalign = 0;
                code.ellipsize = Pango.EllipsizeMode.END;
                code.max_width_chars = 45;

                var edit = new Gtk.Button.from_icon_name ("document-edit-symbolic");
                edit.tooltip_text = _("Edit command");

                var remove = new Gtk.Button.from_icon_name ("edit-delete-symbolic");
                remove.tooltip_text = _("Remove command");

                var command_id = command.id;
                edit.clicked.connect (() => edit_command (command_id));
                remove.clicked.connect (() => remove_command (command_id));

                row_grid.attach (name, 0, 0, 1, 1);
                row_grid.attach (code, 0, 1, 1, 1);
                row_grid.attach (edit, 1, 0, 1, 2);
                row_grid.attach (remove, 2, 0, 1, 2);
                row.add (row_grid);
                list_box.add (row);
            }
            list_box.show_all ();
        }

        private void edit_command (string? id) {
            var dialog = new Gtk.Dialog.with_buttons (
                id == null ? _("Add command") : _("Edit command"),
                null,
                Gtk.DialogFlags.MODAL | Gtk.DialogFlags.USE_HEADER_BAR,
                _("_Cancel"), Gtk.ResponseType.CANCEL,
                _("_Save"), Gtk.ResponseType.APPLY);
            dialog.transient_for = get_toplevel () as Gtk.Window;
            dialog.set_default_response (Gtk.ResponseType.APPLY);

            var content = dialog.get_content_area ();
            content.margin = 12;
            content.spacing = 8;

            var name_entry = new Gtk.Entry ();
            name_entry.placeholder_text = _("Command name");
            var command_entry = new Gtk.Entry ();
            command_entry.placeholder_text = _("Shell command");

            if (id != null) {
                foreach (var command in load_commands ()) {
                    if (command.id == id) {
                        name_entry.text = command.name;
                        command_entry.text = command.command;
                        break;
                    }
                }
            }

            content.add (new Gtk.Label (_("Name")));
            content.add (name_entry);
            content.add (new Gtk.Label (_("Command")));
            content.add (command_entry);

            dialog.response.connect ((response) => {
                if (response == Gtk.ResponseType.APPLY &&
                    name_entry.text.strip ().length > 0 &&
                    command_entry.text.strip ().length > 0) {
                    save_command (id, name_entry.text.strip (), command_entry.text.strip ());
                }
                dialog.destroy ();
            });
            dialog.show_all ();
        }

        private void save_command (string? id, string name, string command) {
            var commands = load_commands_as_object ();
            string key = id ?? Uuid.string_random ();
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("name");
            builder.add_string_value (name);
            builder.set_member_name ("command");
            builder.add_string_value (command);
            builder.end_object ();
            commands.set_object_member (key, builder.get_root ().get_object ());
            save_object (commands);
            reload ();
        }

        private void remove_command (string id) {
            var commands = load_commands_as_object ();
            commands.remove_member (id);
            save_object (commands);
            reload ();
        }

        private void save_object (Json.Object commands) {
            var generator = new Json.Generator ();
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (commands);
            generator.set_root (node);
            global_settings.set_string (
                "kdeconnect-runcommands", generator.to_data (null));
        }

        private Json.Object load_commands_as_object () {
            var object = new Json.Object ();
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (
                    global_settings.get_string ("kdeconnect-runcommands"), -1);
                var root = parser.get_root ();
                if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                    return root.get_object ();
                }
            } catch (Error e) {
                warning ("Cannot load remote commands: %s", e.message);
            }
            return object;
        }

        private Gee.ArrayList<ConfiguredCommand> load_commands () {
            var result = new Gee.ArrayList<ConfiguredCommand> ();
            var object = load_commands_as_object ();
            object.foreach_member ((object, id, node) => {
                if (node == null || node.get_node_type () != Json.NodeType.OBJECT) {
                    return;
                }
                var command = node.get_object ();
                if (command.has_member ("name") && command.has_member ("command")) {
                    result.add (new ConfiguredCommand (
                        id,
                        command.get_string_member ("name"),
                        command.get_string_member ("command")
                    ));
                }
            });
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
