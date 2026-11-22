namespace EOSConnect.Plugin {

    public class Clipboard : PluginInterface {

        construct {
            name = _("Clipboard");
            icon_name = "edit-paste";
            capability_name = MConnect.ClipboardHandler.CLIPBOARD;
            description = _("Synchronize the clipboard between paired devices.");
            settings_key_is_active = "kdeconnect-clipboard-active";
        }
    }
}
