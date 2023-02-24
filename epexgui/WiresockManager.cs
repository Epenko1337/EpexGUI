using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using static epexgui.WireguardBoosterExports;

namespace epexgui
{
    /// <summary>
    /// Manages the Wireguard tunnel using the Wireguard Booster library.
    /// </summary>
    internal class WiresockManager
    {
        private readonly TextBox _outBox;
        public bool Connected;
        private IntPtr _wgboosterNatHandle = IntPtr.Zero;
        private IntPtr _wgboosterNicHandle = IntPtr.Zero;
        private volatile bool _adapterMode;

        private LogPrinter _logPrinter;

        // Create a GCHandle to keep the delegate alive
        private GCHandle _logPrinterHandle;

        /// <summary>
        /// Initializes a new instance of the WiresockManager class with the specified TextBox control.
        /// </summary>
        /// <param name="output">The TextBox control to use for logging messages.</param>
        /// <param name="adapterMode">Indicates if Wireguard tunnel should spawn the virtual Wiresock network interface</param>
        public WiresockManager(TextBox output, bool adapterMode)
        {
            _outBox = output;
            _adapterMode = adapterMode;
        }

        /// <summary>
        /// Disposes the GCHandle for the log printer delegate.
        /// </summary>
        public void Dispose()
        {
            if (_logPrinterHandle.IsAllocated)
            {
                _logPrinterHandle.Free();
            }
        }

        /// <summary>
        /// Appends the specified message to the _outBox control on the UI thread.
        /// </summary>
        /// <param name="message">The message to append to the _outBox control.</param>
        internal void PrintLog(string message)
        {
            if (_outBox.IsHandleCreated)
            {
                // Invoke the specified delegate on the UI thread, which appends the message to the _outBox control.
                _outBox.Invoke((MethodInvoker)delegate
                {
                    _outBox.AppendText(message);
                    _outBox.AppendText(Environment.NewLine);
                });
            }
        }

        /// <summary>
        /// Connects to the Wireguard tunnel using the specified configuration file.
        /// </summary>
        /// <param name="configPath">The path to the Wireguard configuration file.</param>
        public void Connect(string configPath)
        {
            // Create a new instance of the LogPrinter delegate
            _logPrinter = PrintLog;

            // Create a GCHandle to keep the delegate alive
            _logPrinterHandle = GCHandle.Alloc(_logPrinter);

            if (_wgboosterNatHandle == IntPtr.Zero)
            {
                _wgboosterNatHandle = wgb_get_handle(_logPrinter,
                    Global.SetMan.AppSettings.EnableDebugLog ? WgbLogLevel.All : WgbLogLevel.Error,
                    false);
            }

            if (_wgboosterNicHandle == IntPtr.Zero)
            {
                _wgboosterNicHandle = wgbp_get_handle(_logPrinter,
                    Global.SetMan.AppSettings.EnableDebugLog ? WgbLogLevel.All : WgbLogLevel.Error,
                    false);
            }

            if (_wgboosterNatHandle == IntPtr.Zero || _wgboosterNicHandle == IntPtr.Zero)
            {
                MessageBox.Show(@"Failed to connect to tunnel manager. Please check log", @"Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (!_adapterMode)
            {
                if (!wgb_create_tunnel_from_file_w(_wgboosterNatHandle, configPath))
                {
                    MessageBox.Show(@"Failed to create the tunnel from the provided configuration. Please check log",
                        @"Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
            }
            else
            {
                if (!wgbp_create_tunnel_from_file_w(_wgboosterNicHandle, configPath))
                {
                    MessageBox.Show(@"Failed to create the tunnel from the provided configuration. Please check log",
                        @"Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
            }

            if (!_adapterMode)
            {
                if (!wgb_start_tunnel(_wgboosterNatHandle))
                {
                    MessageBox.Show(@"Tunnel has failed to start. Please check log", @"Error", MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    wgb_drop_tunnel(_wgboosterNatHandle);
                    return;
                }
            }
            else
            {
                if (!wgbp_start_tunnel(_wgboosterNicHandle))
                {
                    MessageBox.Show(@"Tunnel has failed to start. Please check log", @"Error", MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    wgbp_drop_tunnel(_wgboosterNicHandle);
                    return;
                }
            }

            Connected = true;
        }

        public void EnableDebugLog(bool bEnable)
        {
            wgb_set_log_level(_wgboosterNatHandle, bEnable ? WgbLogLevel.All : WgbLogLevel.Error);
            wgbp_set_log_level(_wgboosterNicHandle, bEnable ? WgbLogLevel.All : WgbLogLevel.Error);
        }

        /// <summary>
        /// Stops and disconnects from the Wireguard tunnel asynchronously.
        /// </summary>
        public async Task DisconnectAsync()
        {
            await Task.Run(() =>
            {
                wgb_stop_tunnel(_wgboosterNatHandle);
                wgb_drop_tunnel(_wgboosterNatHandle);
                wgbp_stop_tunnel(_wgboosterNicHandle);
                wgbp_drop_tunnel(_wgboosterNicHandle);

                Connected = false;
            });
        }

        public void SetAdapterMode(bool adapterMode)
        {
            _adapterMode = adapterMode;
        }
    }
}
