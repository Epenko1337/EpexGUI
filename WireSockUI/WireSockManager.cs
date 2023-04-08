using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;
using WireSockUI.Config;
using WireSockUI.Properties;
using static WireSockUI.Native.WireguardBoosterExports;

namespace WireSockUI
{
    /// <summary>
    /// Manages the Wireguard tunnel using the Wireguard Booster library.
    /// </summary>
    internal class WireSockManager : IDisposable
    {
        private delegate IntPtr GetHandle(LogPrinter logPrinter, WgbLogLevel logLevel, bool enableTrafficCapture);
        private delegate void SetLogLevel(IntPtr handle, WgbLogLevel logLevel);
        private delegate bool CreateTunnelFromFile(IntPtr handle, string fileName);
        private delegate bool TunnelAction(IntPtr handle);
        private delegate WgbStats TunnelState(IntPtr handle);

        private Mode _adapterMode;
        private GetHandle _getHandle;
        private SetLogLevel _setLogLevel;
        private CreateTunnelFromFile _createTunnelFromFile;        
        private TunnelAction _startTunnel;
        private TunnelAction _stopTunnel;
        private TunnelAction _dropTunnel;
        private TunnelAction _tunnelActive;
        private TunnelState _tunnelState;

        private volatile IntPtr _handle = IntPtr.Zero;
        private string _profileName;

        private BlockingCollection<LogMessage> _logQueue;
        private GCHandle _logPrinterHandle;

        private readonly LogPrinter _logPrinter;

        private WgbLogLevel _logLevel;
        private Control _logControl;
        private LogMessageCallback _logMessageCallback;

        /// <summary>
        /// LogMessage function delegate
        /// </summary>
        /// <param name="message"><see cref="T:LogMessage"/></param>
        public delegate void LogMessageCallback(LogMessage message);

        /// <summary>
        /// <see cref="WireSockmanager" /> operating mode
        /// </summary>
        public enum Mode
        {
            Undefined,
            /// <summary>
            /// "Transparent" mode (default)
            /// </summary>
            Transparent,
            /// <summary>
            /// Virtual network adapter mode
            /// </summary>
            VirtualAdapter
        }

        /// <summary>
        /// WireSock Log message with associated timestamp
        /// </summary>
        public struct LogMessage
        {
            private string _message;

            public DateTime Timestamp;

            public String Message
            {
                get
                {
                    return _message;
                }
                set
                {
                    this.Timestamp = DateTime.Now;
                    _message = value;
                }
            }
        }

        /// <summary>
        /// WireSock tunnel mode <see cref="Mode.Transparent" /> or <see cref="Mode.VirtualAdapter" />
        /// </summary>
        public Mode TunnelMode
        {
            get
            {
                return _adapterMode;
            }
            set
            {
                if (value == _adapterMode)
                    return;

                if (_handle != IntPtr.Zero)
                    throw new InvalidOperationException("Adapter mode cannot be changed while in instantiated state.");

                switch (value)
                {
                    case Mode.VirtualAdapter:
                        _getHandle = wgbp_get_handle;
                        _setLogLevel = wgbp_set_log_level;
                        _createTunnelFromFile = wgbp_create_tunnel_from_file;
                        _startTunnel = wgbp_start_tunnel;
                        _stopTunnel = wgbp_stop_tunnel;
                        _dropTunnel = wgbp_drop_tunnel;
                        _tunnelActive = wgbp_get_tunnel_active;
                        _tunnelState = wgbp_get_tunnel_state;
                        break;
                    default:
                        _getHandle = wgb_get_handle;
                        _setLogLevel = wgb_set_log_level;
                        _createTunnelFromFile = wgb_create_tunnel_from_file;
                        _startTunnel = wgb_start_tunnel;
                        _stopTunnel = wgb_stop_tunnel;
                        _dropTunnel = wgb_drop_tunnel;
                        _tunnelActive = wgb_get_tunnel_active;
                        _tunnelState = wgb_get_tunnel_state;
                        break;
                }

                _adapterMode = value;
            }
        }

        /// <summary>
        /// Return log level configured in settings as <see cref="WgbLogLevel" />
        /// </summary>
        public WgbLogLevel LogLevelSetting
        {
            get
            {
                switch (Properties.Settings.Default.LogLevel)
                {
                    case "Info":
                        return WgbLogLevel.Info;
                    case "Debug":
                        return WgbLogLevel.Debug;
                    case "All":
                        return WgbLogLevel.All;
                    default:
                        return WgbLogLevel.Error;
                }
            }
        }

        public WgbLogLevel LogLevel
        {
            get
            {
                return _logLevel;
            }
            set
            {
                _logLevel = value;

                // Update loglevel directly if instantiated
                if (_handle != IntPtr.Zero)
                    _setLogLevel(_handle, value);
            }
        }

        /// <summary>
        /// <c>true</c> if a tunnel is currently active, otherwise <c>false</c>
        /// </summary>
        public bool Connected
        {
            get
            {
                if (_handle != IntPtr.Zero)
                    return _tunnelActive(_handle);

                return false;
            }
        }

        /// <summary>
        /// Current active profile, if any
        /// </summary>
        public String ProfileName
        {
            get
            {
                return _profileName;
            }
        }

        /// <summary>
        /// Appends the specified message to the _outBox control on the UI thread.
        /// </summary>
        /// <param name="message">The message to append to the _outBox control.</param>
        private void PrintLog(string message)
        {
            _logQueue.Add(new LogMessage() { Message = message });
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="WireSockManager" />.
        /// </summary>
        /// <param name="logControl"><see cref="T:Control" /> owning the <paramref name="logMessageCallback"/></param>
        /// <param name="logMessageCallback"><see cref="T:LogMessageCallback" /></param>
        public WireSockManager(Control logControl = null, LogMessageCallback logMessageCallback = null)
        {
            _logQueue = new BlockingCollection<LogMessage>(new ConcurrentQueue<LogMessage>());
            _logControl = logControl;
            _logMessageCallback = logMessageCallback;

            Task.Run(() =>
            {
                try
                {
                    while (true)
                    {
                        LogMessage message = _logQueue.Take();

                        if (_logControl != null && _logMessageCallback != null)
                        {
                            if (_logControl.InvokeRequired)
                                _logControl.BeginInvoke(_logMessageCallback, new object[] { message });
                            else
                                _logMessageCallback(message);
                        }
                    }
                }
                catch (InvalidOperationException)
                {
                }
            });

            this.TunnelMode = Mode.Transparent;

            // Create a new instance of the LogPrinter delegate
            _logPrinter = PrintLog;

            // Create a GCHandle to keep the delegate alive
            _logPrinterHandle = GCHandle.Alloc(_logPrinter);
        }

        ~WireSockManager()
        {
            Dispose();
        }

        /// <summary>
        /// Disposes the GCHandle for the log printer delegate.
        /// </summary>
        public void Dispose()
        {
            if (_handle != IntPtr.Zero)
                Disconnect();

            if (_logPrinterHandle.IsAllocated)
                _logPrinterHandle.Free();

            _logQueue.CompleteAdding();
        }

        /// <summary>
        /// Create a Wireguard tunnel using the specified configuration file.
        /// </summary>
        /// <param name="profile">Profile identifier</param>
        public bool Connect(string profile)
        {
            String profilePath = Profile.GetProfilePath(profile);

            if (_handle == IntPtr.Zero)
                _handle = _getHandle(_logPrinter, _logLevel, false);

            if (_handle == IntPtr.Zero)
            {
                MessageBox.Show(Resources.TunnelErrorManager, Resources.TunnelErrorTitle,
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }

            if (!_createTunnelFromFile(_handle, profilePath))
            {
                MessageBox.Show(Resources.TunnelErrorCreate,
                    Resources.TunnelErrorTitle, MessageBoxButtons.OK, MessageBoxIcon.Error);

                _handle = IntPtr.Zero;
                return false;
            }

            if (!_startTunnel(_handle))
            {
                MessageBox.Show(Resources.TunnelErrorStart, Resources.TunnelErrorTitle, MessageBoxButtons.OK,
                    MessageBoxIcon.Error);

                _dropTunnel(_handle);
                _handle = IntPtr.Zero;
                return false;
            }

            // Update connected profile
            _profileName = profile;

            return true;
        }

        /// <summary>
        /// Stops and disconnects from the Wireguard tunnel asynchronously.
        /// </summary>
        public void Disconnect()
        {
            if (_handle != IntPtr.Zero)
            {
                _stopTunnel(_handle);
                _dropTunnel(_handle);

                _handle = IntPtr.Zero;
                _profileName = null;
            }
        }

        /// <summary>
        /// Get current tunnel state, or empty if no connection
        /// </summary>
        /// <returns><see cref="WgbStats"/></returns>
        public WgbStats GetState()
        {
            if (_handle != IntPtr.Zero)
                return _tunnelState(_handle);

            return new WgbStats();
        }
    }
}
