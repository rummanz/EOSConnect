namespace EOSConnect.Plugin {

    public class Multimedia : PluginInterface {

        construct {
            name = _("Multimedia");
            icon_name = "audio-x-generic";
            capability_name = MConnect.MprisHandler.MPRIS;
            description = _("Control MPRIS-compatible media players.");
            settings_key_is_active = "kdeconnect-mpris-active";
        }
    }
}
