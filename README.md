## EOSConnect

EOSConnect is a GTK KDE Connect client written in Vala, originally designed for elementary OS. Its embedded, mconnect-derived backend communicates with KDE Connect-compatible Android devices.

### Project history and direction

The original EOSConnect was developed as an elementary OS application and later abandoned by its author. Its backend was derived from an older version of mconnect and integrated directly into EOSConnect rather than run as a separate D-Bus service.

Conecto began as a fork of EOSConnect and was substantially rewritten in C++. That rewrite offered a fresh implementation, but it also meant the project had moved away from EOSConnect's existing Vala codebase and its original elementary-oriented application. For this revival, EOSConnect was chosen as the starting point because the goal is specifically to bring back an elementary-friendly GTK application, and its existing interface, plugin structure, and feature work provide a direct foundation. This avoids starting with a wholesale port or replacing the UI before addressing the broken backend and features.

The revival is keeping the GTK application and improving its embedded backend incrementally. The backend has been updated for KDE Connect protocol v8, including the connection handshake, identity capability exchange, pairing, and file-transfer port range. More features are being tested individually; implementation alone is not treated as proof that a feature works.

### Remote mouse and keyboard input

Remote input is verified to work in an X11 session. The X11 implementation uses AT-SPI to synthesize pointer and keyboard events.

Wayland does not permit applications to inject global input in the same way. EOSConnect therefore has a separate client for the standard `org.freedesktop.portal.RemoteDesktop` portal. That portal must be provided by the desktop environment, support keyboard and pointer access, and authorize the session. EOSConnect currently sends input through the portal's D-Bus `Notify*` methods; it does not yet implement the EIS/libei input path.

**Wayland support is not currently working on elementary OS.** The elementary portal backend does not presently implement `RemoteDesktop`, so EOSConnect has no supported portal through which to request remote input there. The client may work on another desktop only if that desktop's selected portal backend exposes the RemoteDesktop interface and compatible D-Bus input methods; that has not yet been verified across other desktops. A portal that only supports EIS/libei is not compatible with the current client.

The first input event can also be missed while the portal session is being created and awaiting authorization. Remote input on Wayland should be considered experimental until the portal support and session behavior are tested on the target desktop.

### Current testing status

- Device discovery, pairing, connections, two-way file transfer, and plugin settings have been tested.
- Remote mouse and keyboard input have been tested in an X11 session.
- Plaintext clipboard synchronization has been tested and works.
- MPRIS multimedia control, live metadata, album art, and player discovery have been tested and work.
- PipeWire/PulseAudio system-volume sink discovery and controls have been tested and work.
- Remote commands can be configured through EOSConnect's device plugin settings and are synchronized to paired devices.
- Telephony call notifications, mute, incoming SMS handling, and automatic media pause/resume have been tested and work.
- SMS and address-book/contact features are implemented in the existing application but have not yet been tested as part of this revival.
- Remote input through a Wayland portal is experimental and unavailable on elementary OS until its portal backend supports RemoteDesktop.

#### Configuring remote commands

Remote commands are disabled until commands are explicitly allowlisted. They can be added, edited, and removed from the EOSConnect device plugin settings. They can also be configured directly in GSettings:

```bash
gsettings set com.github.gyan000.eos-connect kdeconnect-runcommands \
  '{"lock":{"name":"Lock screen","command":"loginctl lock-session"},"shutdown":{"name":"Shutdown","command":"systemctl poweroff"}}'
```

Read the current allowlist with:

```bash
gsettings get com.github.gyan000.eos-connect kdeconnect-runcommands
```

Only commands in this allowlist can be started. Commands are executed through `/bin/sh -c`, so configure only trusted commands and review them before enabling the feature.

### Warning

This project is a work in progress and is not intended for daily use.


### Installation
* On Ubuntu or elementary OS, install these dependencies:
```bash
sudo apt install elementary-sdk libunity-dev libnotify-dev gnutls-dev libsqlite3-dev libedataserver1.2-dev libebook1.2-dev -y
```
* Clone the repository.
* Inside the project, compile with:
```bash
meson build && clear && ninja -C build && glib-compile-schemas ./data/
```
* Start application
  * Start from the build directory:
  ```bash
  GSETTINGS_SCHEMA_DIR=data ./build/src/com.github.gyan000.eos-connect 
  ```
  * Start with complete debug output:
  ```bash
  GSETTINGS_SCHEMA_DIR=data ./build/src/com.github.gyan000.eos-connect -d
  ```
* To install it:
```bash
sudo ninja -C build install
  ```

### Roadmap
#### v0.1
- [x] Import mconnect, remove useless stuff.
- [x] List available devices.
- [x] Use Tablet or Phone or Computre icons in devices list.
- [x] Pair automatically.
- [x] Plugin configuration by device: plugin list, custom name.
- [x] List configured device in dynamic quicklist.
- [x] Dconf: global setting and by device settings.

#### v0.2 - ping
- [x] Send / receive ping, with notification.
- [x] Ping plugin configurarion. (button to send a ping.)

#### v0.3 - battery
- [x] Receive notification when battery below a threshold.
- [x] Battery plugin configuration. (option to setup charge percentage warning)
- [x] Show battery percentage in dynamic quicklist.

#### v0.4 - notification
- [x] Send / receive notifications.
- [x] Notification plugin configuration. (configuration window to activate/deactivate send/receive notifications globally and by application, with application filter.)
- [ ] Synchronise notifications on both devices. (when notification closed on a device, it should close on the other device.)

#### v0.4 - share
- [x] Send one or more files, with popup with file advancement.
- [x] Receive files, with advancement using launcher api to display progress bar on the icon in the dock.
- [x] Share plugin configuration. (option to setup default save folder)
- [x] Add option to Files's context menu to send file(s) to a device.

#### v0.5 - SMS and contacts
- [ ] Send / receive SMS, with SMS notification. (implemented; not yet tested in this revival)
- [ ] Option to display SMS tab in dynamic quicklist. (not yet tested)
- [ ] Tab in main window with SMS history by contact. (not yet tested)
- [ ] Add an icon on header bar to send SMS to one or more contacts. (not yet tested)
- [ ] Load contacts from address books using libedataserver and libebook, including phone numbers and contact photos. (implemented; not yet tested)
- [ ] Widget to send SMS, with input text and dropdown to select an available device.
- [ ] Display matching contacts when entering a phone number or contact name in the SMS widget.
- [ ] Store SMS by phone number in SQLite and browse message history.
- [ ] When user do not want to store SMS with sqlite, use a dummy SMS store.
- [ ] General option, for all devices, to activate or not the storage of SMS history.
- [ ] SMS plugin configuration. (to setup how many days of history we want to keep)

#### v0.5.1 - Telephony
- [x] Incoming call, missed-call, talking, and call-cancellation notifications. (verified)
- [x] Contact name and optional phone-thumbnail photo in call notifications.
- [x] Mute-call notification action. (verified)
- [x] Store and display incoming SMS in the existing SMS history.
- [x] Telephony plugin SMS-storage configuration.
- [x] Automatically pause playing MPRIS media for incoming calls and resume it when the call ends. (verified)

#### v0.7 - Commands
- [x] Execute an explicit allowlist of configured commands.
- [x] Command plugin configuration window.
- [x] Synchronize configured commands with paired devices.
- [ ] Remote command confirmation UI.

#### v0.8 - Clipboard
- [x] Synchronize plaintext clipboard content with paired devices. (verified)
- [x] Clipboard plugin configuration.

#### v0.9 - Multimedia control 
- [x] MPRIS player discovery and basic playback, track, volume, and seeking controls. (verified)
- [x] Local PipeWire/PulseAudio sink discovery and remote volume, mute, and default-sink control.
- [x] MPRIS album-art payload delivery and live metadata updates. (verified)
- [x] Multimedia control plugin configuration.

#### v0.9.1 - Remote control
- [x] Remote mouse and keyboard input on X11.
- [ ] Remote mouse and keyboard input through a Wayland RemoteDesktop portal. (experimental; requires a compatible portal backend; unavailable on elementary OS currently)
- [ ] Dedicated presentation / slide-control feature. (not implemented)
- [ ] Remote control plugin configuration

#### v1
- [ ] Remove refresh icon at bottom of devices list. 
- [ ] Unpair device, with icon at bottom of devices list.
- [ ] Option, when unpairing a device, to delete everything: configuration, SMS history.
- [ ] Welcome screen, with how-to setup.
- [ ] Option to setup public visible name of EOSConnect.
- [ ] Translations: french.
- [ ] Code cleanup.
