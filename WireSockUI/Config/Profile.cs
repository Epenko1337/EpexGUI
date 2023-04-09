using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using WireSockUI.Extensions;

namespace WireSockUI.Config
{
    /// <summary>
    /// WireGuard Profile, including WireSock extensions
    /// </summary>
    internal class Profile
    {
        // Interface values
        private string _privateKey;
        private string _address;
        private string _mtu;
        private string _dns;

        // Peer values
        private string _publicKey;
        private string _presharedKey;
        private string _allowedIPs;
        private string _endpoint;
        private string _persistentKeepAlive;

        // WireSock Extensions
        private string _allowedApps;
        private string _disallowedApps;
        private string _disallowedIPs;
        private string _socks5Proxy;
        private string _socks5ProxyUsername;
        private string _socks5ProxyPassword;

        internal static void ValidateKey(string section, string key, string keyValue)
        {
            byte[] keyBinary;

            if (String.IsNullOrWhiteSpace(keyValue)) return;

            try
            {
                keyBinary = Convert.FromBase64String(keyValue);
            }
            catch (FormatException)
            {
                throw new FormatException($"\"{key}\" in \"{section}\", invalid base64 encoded value.");
            }

            // 256-bit keys only
            if (keyBinary.Length != 32)
            {
                throw new FormatException($"\"{key}\" in \"{section}\", invalid key length, only 256-bit keys are supported.");
            }
        }

        internal static void ValidateAddresses(string section, string key, string keyValue, Func<string, bool> validator)
        {
            if (String.IsNullOrWhiteSpace(keyValue)) return;

            foreach (String value in keyValue.Split(new char[] { ',' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (!validator(value))
                {
                    throw new FormatException($"\"{key}\" in \"{section}\", invalid address \"{value}\".");
                }
            }
        }

        /// <summary>
        /// Local interface private key
        /// </summary>
        public String PrivateKey
        {
            get { return _privateKey; }
            set
            {
                ValidateKey("Interface", "PrivateKey", value);
                _privateKey = value;
            }
        }

        /// <summary>
        /// Local interface public key, derived from private key
        /// </summary>
        public String PublicKey
        {
            get
            {
                if (!String.IsNullOrEmpty(_privateKey))
                {
                    // Determine public key from private key data
                    return
                        Convert.ToBase64String(
                            Curve25519.GetPublicKey(
                                Convert.FromBase64String(this.PrivateKey)));
                }

                return null;
            }
        }

        /// <summary>
        /// List of interface IP addresses
        /// </summary>
        public String Address
        {
            get
            {
                return _address;
            }
            set
            {
                ValidateAddresses("Interface", "Address", value, Native.IPHelper.IsValidIPNetwork);
                _address = value;
            }
        }

        /// <summary>
        /// List of interface DNS servers
        /// </summary>
        public String DNS
        {
            get
            {
                return _dns;
            }
            set
            {
                ValidateAddresses("Interface", "DNS", value, Native.IPHelper.IsValidIPAddress);
                _dns = value;
            }
        }

        /// <summary>
        /// Interface Maximum Transmissable Unit size
        /// </summary>
        public String MTU
        {
            get
            {
                return _mtu;
            }
            set
            {
                if (!String.IsNullOrWhiteSpace(value))
                {
                    if (!int.TryParse(value, out int mtu))
                        throw new FormatException("\"MTU\" in \"Interface\", is not a numerical value.");

                    if (mtu < 576 || mtu > 65535)
                        throw new FormatException("\"MTU\" in \"Interface\", invalid value. Expected 576...65535.");

                    _mtu = value;
                }
                else
                {
                    _mtu = null;
                }
            }
        }

        /// <summary>
        /// Peer public key
        /// </summary>
        public String PeerKey
        {
            get { return _publicKey; }
            set
            {
                ValidateKey("Peer", "PublicKey", value);
                _publicKey = value;
            }
        }

        /// <summary>
        /// Peer preshared key (optional)
        /// </summary>
        public String PresharedKey
        {
            get { return _presharedKey; }
            set
            {
                ValidateKey("Peer", "PresharedKey", value);
                _presharedKey = value;
            }
        }

        /// <summary>
        /// Peer allowed IP list
        /// </summary>
        public String AllowedIPs
        {
            get
            {
                return _allowedIPs;
            }
            set
            {
                ValidateAddresses("Peer", "AllowedIPs", value, Native.IPHelper.IsValidIPNetwork);
                _allowedIPs = value;
            }
        }

        /// <summary>
        /// Peer endpoint address (DNS or IP)
        /// </summary>
        public String Endpoint
        {
            get { return _endpoint; }
            set
            {
                if (!Native.IPHelper.IsValidAddress(value))
                    throw new FormatException("\"Endpoint\" in \"Peer\", is not a valid IPv4, IPv6 or domain address.");

                _endpoint = value;
            }
        }


        /// <summary>
        /// Persistent keep alive interval
        /// </summary>
        public String PersistentKeepAlive
        {
            get
            {
                return _persistentKeepAlive;
            }
            set
            {
                if (!String.IsNullOrWhiteSpace(value))
                {
                    if (!int.TryParse(value, out int mtu))
                        throw new FormatException("\"PersistentKeepalive\" in \"Peer\", is not a numerical value.");

                    if (mtu < 0 || mtu > 65535)
                        throw new FormatException("\"PersistentKeepalive\" in \"Peer\", invalid value. Expected 0...65535.");

                    _persistentKeepAlive = value;
                }
                else
                {
                    _persistentKeepAlive = null;
                }
            }
        }

        /// <summary>
        /// Peer allowed applications list
        /// </summary>
        /// <remarks>WireSock specific extension</remarks>
        public String AllowedApps
        {
            get
            {
                return _allowedApps;
            }
            set
            {
                _allowedApps = value;
            }
        }

        /// <summary>
        /// Peer disallowed applications list
        /// </summary>
        /// <remarks>WireSock specific extension</remarks>
        public String DisallowedApps
        {
            get
            {
                return _disallowedApps;
            }
            set
            {
                _disallowedApps = value;
            }
        }

        /// <summary>
        /// Peer disallowed IP addresses
        /// </summary>
        /// <remarks>WireSock specific extension</remarks>
        public String DisallowedIPs
        {
            get
            {
                return _disallowedIPs;
            }
            set
            {
                _disallowedIPs = value;
            }
        }

        /// <summary>
        /// Peer SOCKS5 proxy
        /// </summary>
        /// <remarks>WireSock specific extension</remarks>
        public String Socks5Proxy
        {
            get
            {
                return _socks5Proxy;
            }
            set
            {
                if (!String.IsNullOrEmpty(value))
                {
                    if (!Native.IPHelper.IsValidAddress(value))
                        throw new FormatException("\"Endpoint\" in \"Peer\", is not a valid IPv4, IPv6 or domain address.");

                    _socks5Proxy = value;
                }
                else
                {
                    _socks5Proxy = null;
                }
            }
        }

        /// <summary>
        /// Peer SOCKS5 proxy username
        /// </summary>
        /// <remarks>WireSock specific extension</remarks>
        public String Socks5ProxyUsername
        {
            get
            {
                return _socks5ProxyUsername;
            }
            set
            {
                _socks5ProxyUsername = value;
            }
        }

        /// <summary>
        /// Peer SOCKS5 proxy password
        /// </summary>
        /// <remarks>WireSock specific extension</remarks>
        public String Socks5ProxyPassword
        {
            get
            {
                return _socks5ProxyPassword;
            }
            set
            {
                _socks5ProxyPassword = value;
            }
        }

        public static IEnumerable<String> GetProfiles()
        {
            String[] files = Directory.GetFiles(Global.ConfigsFolder);

            foreach (String file in files)
            {
                if (!file.EndsWith(".conf")) continue;

                yield return Path.GetFileNameWithoutExtension(file);
            }
        }

        /// <summary>
        /// Retrieve the full path to a given <paramref name="profileName"/>
        /// </summary>
        /// <param name="profileName">Profile name</param>
        /// <returns>Full path to the profile</returns>
        /// <remarks>The profile might not exist, this merely returns the path it should be at.</remarks>
        public static String GetProfilePath(string profileName)
        {
            return Path.Combine(Global.ConfigsFolder, profileName + ".conf");
        }

        /// <summary>
        /// Load an existing named profile
        /// </summary>
        /// <param name="profileName">Profile name (i.e. filename without extension)</param>
        public static Profile LoadProfile(string profileName)
        {
            String filename = GetProfilePath(profileName);
            return new Profile(filename);
        }

        /// <summary>
        /// Create an empty profile from scratch
        /// </summary>
        public Profile()
        {
        }

        /// <summary>
        /// Load a profile from specified filepath
        /// </summary>
        /// <param name="profilePath">Full filepath to a profile</param>
        public Profile(String profilePath)
        {
            if (!File.Exists(profilePath))
            {
                throw new FileNotFoundException($"Profile {Path.GetFileName(profilePath)} does not exist.");
            }

            IEnumerable<string> sections = Native.INIFile.GetSectionNames(profilePath);

            if (!sections.Contains("Interface"))
                throw new ArgumentException($"Profile {Path.GetFileName(profilePath)} does not contain an \"Interface\" section.");

            Dictionary<String, String> section = Native.INIFile.GetSection(profilePath, "Interface");

            // Validate minimum required fields
            if (!section.ContainsKey("PrivateKey"))
                throw new ArgumentException($"Profile {Path.GetFileName(profilePath)}, section \"Interface\" does not have a \"PrivateKey\" defined.");

            if (!section.ContainsKey("Address"))
                throw new ArgumentException($"Profile {Path.GetFileName(profilePath)}, section \"Interface\" does not have a \"Address\" defined.");

            this.PrivateKey = section.Get<string, string>("PrivateKey");
            this.Address = section.Get<string, string>("Address");
            this.DNS = section.Get<string, string>("DNS");
            this.MTU = section.Get<string, string>("MTU");

            if (!sections.Contains("Peer"))
                throw new ArgumentException($"Profile {Path.GetFileName(profilePath)} does not contain an \"Peer\" section.");

            section = Native.INIFile.GetSection(profilePath, "Peer");

            // Validate minimum required fields
            if (!section.ContainsKey("PublicKey"))
                throw new ArgumentException($"Profile {Path.GetFileName(profilePath)}, section \"Peer\" does not have a \"PublicKey\" defined.");

            if (!section.ContainsKey("Endpoint"))
                throw new ArgumentException($"Profile {Path.GetFileName(profilePath)}, section \"Peer\" does not have a \"Endpoint\" defined.");

            this.PeerKey = section.Get<string, string>("PublicKey");
            this.PresharedKey = section.Get<string, string>("PresharedKey");
            this.AllowedIPs = section.Get<string, string>("AllowedIPs");
            this.Endpoint = section.Get<string, string>("Endpoint");
            this.PersistentKeepAlive = section.Get<string, string>("PersistentKeepAlive");

            this.AllowedApps = section.Get<string, string>("AllowedApps");
            this.DisallowedApps = section.Get<string, string>("DisallowedApps");
            this.DisallowedIPs = section.Get<string, string>("DisallowedIPs");
            this.Socks5Proxy = section.Get<string, string>("Socks5Proxy");
            this.Socks5ProxyUsername = section.Get<string, string>("Socks5Username");
            this.Socks5ProxyPassword = section.Get<string, string>("Socks5ProxyPassword");
        }

    }
}
