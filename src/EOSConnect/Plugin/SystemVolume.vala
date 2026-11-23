namespace EOSConnect.Plugin {

    public class SystemVolume : PluginInterface {

        construct {
            name = _("System volume");
            icon_name = "audio-volume-high";
            capability_name = MConnect.SystemVolumeHandler.SYSTEMVOLUME;
            description = _("Control PipeWire or PulseAudio sinks and output devices.");
            settings_key_is_active = "kdeconnect-systemvolume-active";
        }
    }
}
