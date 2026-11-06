using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using WireSockUI.Native;
using WireSockUI.Properties;
using static WireSockUI.Native.WireguardBoosterExports;

namespace WireSockUI.Forms
{
    internal interface INetworkLockApi
    {
        bool TryIsActive(out bool active, out string diagnostic);
        bool TryReset(out string diagnostic);
    }

    internal sealed class NetworkLockApi : INetworkLockApi
    {
        public bool TryIsActive(out bool active, out string diagnostic)
        {
            return WireSockManager.TryIsNetworkLockActive(out active, out diagnostic);
        }

        public bool TryReset(out string diagnostic)
        {
            return WireSockManager.TryResetNetworkLock(out diagnostic);
        }
    }

    internal sealed class NativeOperationResult<T>
    {
        private NativeOperationResult(bool succeeded, bool timedOut, bool busy, T value, string diagnostic,
            Task<NativeOperationResult<T>> pendingCompletion)
        {
            Succeeded = succeeded;
            TimedOut = timedOut;
            Busy = busy;
            Value = value;
            Diagnostic = diagnostic;
            PendingCompletion = pendingCompletion;
        }

        public bool Succeeded { get; }
        public bool TimedOut { get; }
        public bool Busy { get; }
        public T Value { get; }
        public string Diagnostic { get; }
        public Task<NativeOperationResult<T>> PendingCompletion { get; }

        public static NativeOperationResult<T> Success(T value)
        {
            return new NativeOperationResult<T>(true, false, false, value, null, null);
        }

        public static NativeOperationResult<T> Failure(string diagnostic, T value = default)
        {
            return new NativeOperationResult<T>(false, false, false, value, diagnostic, null);
        }

        public static NativeOperationResult<T> OperationBusy(string diagnostic)
        {
            return new NativeOperationResult<T>(false, false, true, default, diagnostic, null);
        }

        public static NativeOperationResult<T> Timeout(string diagnostic,
            Task<NativeOperationResult<T>> pendingCompletion)
        {
            return new NativeOperationResult<T>(false, true, false, default, diagnostic, pendingCompletion);
        }
    }

    internal sealed class TunnelConnectionResult
    {
        public bool Connected { get; set; }
        public long ConnectionSequence { get; set; }
        public bool RecoveryRequired { get; set; }
        public string Diagnostic { get; set; }
    }

    internal sealed class TunnelLifecycleController
    {
        private readonly WireSockManager _manager;
        private readonly INetworkLockApi _networkLockApi;
        private readonly SemaphoreSlim _nativeOperationGate = new SemaphoreSlim(1, 1);
        private readonly object _shutdownSyncRoot = new object();
        private Task<NativeOperationResult<bool>> _shutdownTask;
        private int _shutdownRequested;

        internal TunnelLifecycleController(WireSockManager.LogMessageCallback logMessageCallback = null)
            : this(new WireSockManager(logMessageCallback), new NetworkLockApi())
        {
        }

        internal TunnelLifecycleController(WireSockManager manager, INetworkLockApi networkLockApi)
        {
            _manager = manager ?? throw new ArgumentNullException(nameof(manager));
            _networkLockApi = networkLockApi ?? throw new ArgumentNullException(nameof(networkLockApi));
            _manager.LogLevel = _manager.LogLevelSetting;
        }

        public bool HasTunnelHandle => _manager.HasTunnelHandle;
        public string ProfileName => _manager.ProfileName;
        public string LastError => _manager.LastError;
        public WgbLogLevel ConfiguredLogLevel => _manager.LogLevelSetting;

        public WireSockManager.Mode TunnelMode
        {
            get => _manager.TunnelMode;
            set => _manager.TunnelMode = value;
        }

        public Task<NativeOperationResult<TunnelConnectionResult>> ConnectAsync(string profile,
            bool releasePreservedNetworkLockOnFailure, int timeoutMilliseconds)
        {
            return RunWithTimeoutAsync(() =>
            {
                var connected = _manager.Connect(profile);
                var connectionResult = new TunnelConnectionResult
                {
                    Connected = connected,
                    ConnectionSequence = connected ? _manager.ConnectionSequence : 0
                };

                if (connected)
                    return NativeOperationResult<TunnelConnectionResult>.Success(connectionResult);

                var diagnostic = _manager.LastError;
                if (releasePreservedNetworkLockOnFailure && !_manager.HasTunnelHandle &&
                    !TryReleasePreservedNetworkLock(out var resetDiagnostic))
                {
                    connectionResult.RecoveryRequired = true;
                    diagnostic = AppendDiagnostic(diagnostic, resetDiagnostic);
                }

                connectionResult.Diagnostic = diagnostic;

                return NativeOperationResult<TunnelConnectionResult>.Failure(diagnostic, connectionResult);
            }, timeoutMilliseconds, "The native tunnel connect operation timed out.");
        }

        public Task<NativeOperationResult<bool>> DisconnectAsync(long? connectionSequence, bool preserveNetworkLock,
            int timeoutMilliseconds)
        {
            return RunWithTimeoutAsync(() =>
            {
                var disconnected = connectionSequence.HasValue
                    ? _manager.DisconnectIfConnectionSequence(connectionSequence.Value, preserveNetworkLock)
                    : _manager.Disconnect(preserveNetworkLock);
                return disconnected
                    ? NativeOperationResult<bool>.Success(true)
                    : NativeOperationResult<bool>.Failure(_manager.LastError, false);
            }, timeoutMilliseconds, "The native tunnel disconnect operation timed out.");
        }

        public Task<NativeOperationResult<bool>> GetConnectedAsync(int timeoutMilliseconds)
        {
            return RunWithTimeoutAsync(() =>
            {
                return _manager.TryGetConnected(out var connected, out var diagnostic)
                    ? NativeOperationResult<bool>.Success(connected)
                    : NativeOperationResult<bool>.Failure(diagnostic, false);
            }, timeoutMilliseconds, "The native tunnel-state query timed out.", true);
        }

        public Task<NativeOperationResult<WgbStats>> GetStateAsync(int timeoutMilliseconds)
        {
            return RunWithTimeoutAsync(() =>
            {
                return _manager.TryGetState(out var state, out var diagnostic)
                    ? NativeOperationResult<WgbStats>.Success(state)
                    : NativeOperationResult<WgbStats>.Failure(diagnostic);
            }, timeoutMilliseconds, "The native tunnel-statistics query timed out.", true);
        }

        public Task<NativeOperationResult<bool>> ApplyKillSwitchAsync(bool enableKillSwitch,
            int timeoutMilliseconds)
        {
            return RunWithTimeoutAsync(() =>
            {
                if (_manager.HasTunnelHandle)
                {
                    if (enableKillSwitch)
                    {
                        _manager.KillSwitchEnabled = true;
                        return NativeOperationResult<bool>.Success(true);
                    }

                    if (!_manager.TryGetKillSwitchEnabled(out var killSwitchEnabled, out var diagnostic))
                        return NativeOperationResult<bool>.Failure(diagnostic, false);

                    if (killSwitchEnabled)
                        _manager.KillSwitchEnabled = false;

                    return NativeOperationResult<bool>.Success(true);
                }

                if (!enableKillSwitch && !TryReleasePreservedNetworkLock(out var resetDiagnostic))
                    return NativeOperationResult<bool>.Failure(resetDiagnostic, false);

                return NativeOperationResult<bool>.Success(true);
            }, timeoutMilliseconds, "The native Kill Switch update timed out.");
        }

        public Task<NativeOperationResult<bool>> SetLogLevelAsync(WgbLogLevel logLevel, int timeoutMilliseconds)
        {
            return RunWithTimeoutAsync(() =>
            {
                _manager.LogLevel = logLevel;
                return NativeOperationResult<bool>.Success(true);
            }, timeoutMilliseconds, "The native log-level update timed out.");
        }

        public Task<NativeOperationResult<bool>> QueryNetworkLockAsync(int timeoutMilliseconds)
        {
            return RunWithTimeoutAsync(() =>
            {
                return _networkLockApi.TryIsActive(out var active, out var diagnostic)
                    ? NativeOperationResult<bool>.Success(active)
                    : NativeOperationResult<bool>.Failure(diagnostic, false);
            }, timeoutMilliseconds, "The native network-lock query timed out.");
        }

        public Task<NativeOperationResult<bool>> ResetNetworkLockAsync(int timeoutMilliseconds)
        {
            return RunWithTimeoutAsync(() =>
            {
                if (_manager.HasTunnelHandle)
                {
                    return NativeOperationResult<bool>.Failure(
                        "WireSock UI refused to reset the global network lock while a tunnel handle remains allocated.",
                        false);
                }

                return _networkLockApi.TryReset(out var diagnostic)
                    ? NativeOperationResult<bool>.Success(true)
                    : NativeOperationResult<bool>.Failure(diagnostic, false);
            }, timeoutMilliseconds, "The native network-lock reset timed out.");
        }

        public async Task<NativeOperationResult<bool>> ShutdownAsync(int timeoutMilliseconds)
        {
            if (timeoutMilliseconds <= 0) throw new ArgumentOutOfRangeException(nameof(timeoutMilliseconds));

            Task<NativeOperationResult<bool>> shutdownTask;
            lock (_shutdownSyncRoot)
            {
                if (_shutdownTask == null)
                {
                    Volatile.Write(ref _shutdownRequested, 1);
                    _shutdownTask = RunShutdownWhenAvailableAsync();
                }

                shutdownTask = _shutdownTask;
            }

            using (var timeoutCancellation = new CancellationTokenSource())
            {
                var timeoutTask = Task.Delay(timeoutMilliseconds, timeoutCancellation.Token);
                if (await Task.WhenAny(shutdownTask, timeoutTask).ConfigureAwait(false) == shutdownTask)
                {
                    timeoutCancellation.Cancel();
                    return await shutdownTask.ConfigureAwait(false);
                }
            }

            return NativeOperationResult<bool>.Timeout(
                "The native shutdown cleanup timed out.",
                shutdownTask);
        }

        internal bool TryReleasePreservedNetworkLock(out string diagnostic)
        {
            diagnostic = null;
            if (_manager.HasTunnelHandle)
            {
                diagnostic =
                    "WireSock UI refused to reset the global network lock while a tunnel handle remains allocated.";
                return false;
            }

            if (!_networkLockApi.TryIsActive(out var networkLockActive, out var queryDiagnostic))
            {
                diagnostic = queryDiagnostic ?? "Unable to query WireSock network lock state.";
                return false;
            }

            if (!networkLockActive)
                return true;

            if (_networkLockApi.TryReset(out var resetDiagnostic))
                return true;

            diagnostic = resetDiagnostic ?? "Unable to reset WireSock network lock.";
            return false;
        }

        private async Task<NativeOperationResult<T>> RunWithTimeoutAsync<T>(
            Func<NativeOperationResult<T>> operation, int timeoutMilliseconds, string timeoutDiagnostic,
            bool skipIfBusy = false)
        {
            if (operation == null) throw new ArgumentNullException(nameof(operation));
            if (timeoutMilliseconds <= 0) throw new ArgumentOutOfRangeException(nameof(timeoutMilliseconds));
            if (Volatile.Read(ref _shutdownRequested) != 0)
                return NativeOperationResult<T>.Failure(
                    "The native operation was rejected because WireSock UI is shutting down.");

            var timeoutBudget = Stopwatch.StartNew();
            var acquired = skipIfBusy
                ? await _nativeOperationGate.WaitAsync(0).ConfigureAwait(false)
                : await _nativeOperationGate.WaitAsync(timeoutMilliseconds).ConfigureAwait(false);
            if (!acquired)
            {
                return NativeOperationResult<T>.OperationBusy(
                    skipIfBusy
                        ? "The native operation scheduler is busy; this monitor poll was skipped."
                        : "The native operation could not start because another native operation is still running.");
            }

            if (Volatile.Read(ref _shutdownRequested) != 0)
            {
                _nativeOperationGate.Release();
                return NativeOperationResult<T>.Failure(
                    "The native operation was rejected because WireSock UI is shutting down.");
            }

            var elapsedMilliseconds = Math.Min(
                timeoutBudget.ElapsedMilliseconds,
                int.MaxValue);
            var remainingMilliseconds =
                timeoutMilliseconds - (int)elapsedMilliseconds;
            if (remainingMilliseconds <= 0)
            {
                _nativeOperationGate.Release();
                return NativeOperationResult<T>.OperationBusy(
                    "The native operation could not start within its execution deadline.");
            }

            Task<NativeOperationResult<T>> operationTask;
            try
            {
                operationTask = Task.Run(() =>
                {
                    try
                    {
                        return operation();
                    }
                    catch (Exception ex)
                    {
                        return NativeOperationResult<T>.Failure(ex.Message);
                    }
                    finally
                    {
                        _nativeOperationGate.Release();
                    }
                });
            }
            catch (Exception ex)
            {
                _nativeOperationGate.Release();
                return NativeOperationResult<T>.Failure(ex.Message);
            }

            using (var timeoutCancellation = new CancellationTokenSource())
            {
                var timeoutTask = Task.Delay(remainingMilliseconds, timeoutCancellation.Token);
                if (await Task.WhenAny(operationTask, timeoutTask).ConfigureAwait(false) == operationTask)
                {
                    timeoutCancellation.Cancel();
                    return await operationTask.ConfigureAwait(false);
                }
            }

            return NativeOperationResult<T>.Timeout(timeoutDiagnostic, operationTask);
        }

        private async Task<NativeOperationResult<bool>> RunShutdownWhenAvailableAsync()
        {
            await _nativeOperationGate.WaitAsync().ConfigureAwait(false);
            try
            {
                return await Task.Run(() =>
                {
                    try
                    {
                        return PerformShutdown();
                    }
                    catch (Exception ex)
                    {
                        return NativeOperationResult<bool>.Failure(ex.Message, false);
                    }
                }).ConfigureAwait(false);
            }
            finally
            {
                _nativeOperationGate.Release();
            }
        }

        private NativeOperationResult<bool> PerformShutdown()
        {
            try
            {
                _manager.Disconnect();
            }
            finally
            {
                _manager.Dispose();
            }

            var handleRemainedAllocated = _manager.HasTunnelHandle;
            var diagnostic = handleRemainedAllocated
                ? "The native tunnel handle remained allocated after shutdown cleanup returned."
                : null;
            if (!handleRemainedAllocated &&
                !TryReleasePreservedNetworkLock(out var networkLockDiagnostic))
                diagnostic = AppendDiagnostic(diagnostic, networkLockDiagnostic);

            return string.IsNullOrWhiteSpace(diagnostic)
                ? NativeOperationResult<bool>.Success(true)
                : NativeOperationResult<bool>.Failure(diagnostic, false);
        }

        private static string AppendDiagnostic(string diagnostic, string additionalDiagnostic)
        {
            if (string.IsNullOrWhiteSpace(diagnostic))
                return additionalDiagnostic;
            if (string.IsNullOrWhiteSpace(additionalDiagnostic))
                return diagnostic;
            return $"{diagnostic}{Environment.NewLine}{Environment.NewLine}{additionalDiagnostic}";
        }
    }
}
