namespace EOSConnect.Plugin {

    public class RunCommand : PluginInterface {

        private EOSConnect.Plugin.Popover.RunCommandSettings? settings_popover;

        construct {
            name = _("Commands");
            icon_name = "utilities-terminal";
            capability_name = MConnect.RunCommandHandler.RUNCOMMAND;
            description = _("Start allowlisted commands from paired devices.");
            settings_key_is_active = "kdeconnect-runcommand-active";
            show_configure_button = true;
        }

        public override void handle_configure_button (MConnect.Device device) {
            if (settings_popover == null) {
                settings_popover = new EOSConnect.Plugin.Popover.RunCommandSettings (
                    device, row_configure_button);
                settings_popover.show_all ();
                settings_popover.popup ();
                settings_popover.destroy.connect (() => {
                    settings_popover = null;
                });
            }
        }
    }
}
