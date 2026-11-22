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
using Gee;

namespace MConnect {

    public class Core : Object {

        public TlsCertificate certificate { get; private set; }
        public PacketHandlers handlers { get; private set; default = null; }
        // public Config config { get; private set; default = null; }
        public TransferManager transfer_manager { get; set; default = null; }
        public GLib.Application application;
        public HashMap<string, Device> devices_map;
        public GLib.Settings main_settings;
        public string device_id { get; private set; default = ""; }

        private static Core _instance = null;

        private Core () { }

        public static Core ? instance () throws Error {
            if (Core._instance == null) {
                init_user_dirs ();

                // var config = init_config ();
                var cert = init_crypto ();
                string device_id = init_device_id ();
                var handlers = new PacketHandlers ();

                var core = new Core ();
                // core.config = config;
                core.certificate = cert;
                core.device_id = device_id;
                core.handlers = handlers;

                info ("Supported interfaces: %s", string.joinv (", ", handlers.interfaces));
                Core._instance = core;
            }

            return Core._instance;
        }

        public static string get_storage_dir () {
            return Path.build_filename (Environment.get_user_data_dir (), "mconnect");
        }

        public static string get_config_dir () {
            return Path.build_filename (Environment.get_user_config_dir (), "mconnect");
        }

        public static string get_cache_dir () {
            return Path.build_filename (Environment.get_user_cache_dir (), "mconnect");
        }

        private static void init_user_dirs () {
            DirUtils.create_with_parents (get_storage_dir (), 0700);
            DirUtils.create_with_parents (get_config_dir (), 0700);
        }

        private static TlsCertificate init_crypto () throws Error {
            var key_file = File.new_for_path (Path.build_filename (get_storage_dir (), "private.pem"));
            var cert_file = File.new_for_path (Path.build_filename (get_storage_dir (), "certificate.pem"));
            if (key_file.query_exists () == false || cert_file.query_exists () == false) {
                try {
                    string host_name = Environment.get_host_name ();
                    string user = Environment.get_user_name ();
                    Crypt.generate_key_cert (key_file.get_path (),
                                             cert_file.get_path (),
                                             @"$user@$host_name");
                } catch (Error e) {
                    warning ("Failed to generate private key or certificate: %s", e.message);
                    throw e;
                }
            }

            TlsCertificate tls_cert;
            try {
                tls_cert = new TlsCertificate.from_files (cert_file.get_path (), key_file.get_path ());
            } catch (Error e) {
                warning ("Failed to load certificate or key: %s", e.message);
                throw e;
            }
            return tls_cert;
        }

        private static string init_device_id () throws Error {
            string path = Path.build_filename (get_config_dir (), "device-id");
            string device_id = "";
            size_t length;
            bool device_id_exists = false;

            try {
                FileUtils.get_contents (path, out device_id, out length);
                device_id_exists = true;
            } catch (FileError e) {
                if (e is FileError.NOENT) {
                    debug ("No stored KDE Connect device ID; generating one.");
                } else {
                    throw e;
                }
            }

            if (device_id_exists) {
                device_id = device_id.strip ();
                if (Uuid.string_is_valid (device_id)) {
                    return device_id;
                }

                warning ("Stored device ID is invalid; generating a new KDE Connect device ID.");
            }

            device_id = Uuid.string_random ();
            if (!FileUtils.set_contents (path, device_id)) {
                throw new IOError.FAILED ("Could not save KDE Connect device ID to %s", path);
            }

            return device_id;
        }

        // private static Config init_config () {
        //     string user_config_path = get_config_dir () + "/" + Config.FILE;
        //     var config = new Config (get_config_dir ());
        //     // Write configuration to user config file if none is present.
        //     if (config.path != user_config_path) {
        //         config.dump_to_file (user_config_path);
        //     }
        //     return config;
        // }
    }
}
