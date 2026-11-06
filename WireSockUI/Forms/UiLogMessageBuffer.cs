using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace WireSockUI.Forms
{
    internal sealed class UiLogMessageBuffer : IDisposable
    {
        private readonly int _batchSize;
        private readonly int _capacity;
        private readonly Action<IReadOnlyList<WireSockManager.LogMessage>> _consumeBatch;
        private readonly Queue<WireSockManager.LogMessage> _messages =
            new Queue<WireSockManager.LogMessage>();
        private readonly Func<Action, bool> _schedule;
        private readonly object _syncRoot = new object();

        private long _droppedMessages;
        private long _dispatcherGeneration;
        private bool _dispatchPending;
        private bool _disposed;

        internal UiLogMessageBuffer(
            int capacity,
            int batchSize,
            Func<Action, bool> schedule,
            Action<IReadOnlyList<WireSockManager.LogMessage>> consumeBatch)
        {
            if (capacity <= 0) throw new ArgumentOutOfRangeException(nameof(capacity));
            if (batchSize <= 0 || batchSize > capacity) throw new ArgumentOutOfRangeException(nameof(batchSize));
            _capacity = capacity;
            _batchSize = batchSize;
            _schedule = schedule ?? throw new ArgumentNullException(nameof(schedule));
            _consumeBatch = consumeBatch ?? throw new ArgumentNullException(nameof(consumeBatch));
        }

        internal void Enqueue(WireSockManager.LogMessage message)
        {
            var shouldSchedule = false;
            long dispatcherGeneration = 0;
            lock (_syncRoot)
            {
                if (_disposed)
                    return;

                if (_messages.Count == _capacity)
                {
                    _messages.Dequeue();
                    _droppedMessages++;
                }

                _messages.Enqueue(message);
                if (!_dispatchPending)
                {
                    _dispatchPending = true;
                    dispatcherGeneration = _dispatcherGeneration;
                    shouldSchedule = true;
                }
            }

            if (shouldSchedule)
                ScheduleOrCancel(() => DrainBatch(dispatcherGeneration), dispatcherGeneration);
        }

        internal void RetryPendingDispatch()
        {
            var shouldSchedule = false;
            long dispatcherGeneration = 0;
            lock (_syncRoot)
            {
                if (!_disposed && _messages.Count > 0 && !_dispatchPending)
                {
                    _dispatchPending = true;
                    dispatcherGeneration = _dispatcherGeneration;
                    shouldSchedule = true;
                }
            }

            if (shouldSchedule)
                ScheduleOrCancel(() => DrainBatch(dispatcherGeneration), dispatcherGeneration);
        }

        internal void NotifyDispatcherReset()
        {
            lock (_syncRoot)
            {
                if (_disposed)
                    return;

                _dispatcherGeneration++;
                _dispatchPending = false;
            }
        }

        internal void Clear()
        {
            lock (_syncRoot)
            {
                if (_disposed)
                    return;

                // Invalidate callbacks that were queued before the user cleared
                // the log so an old batch cannot repopulate the empty view.
                _dispatcherGeneration++;
                _dispatchPending = false;
                _droppedMessages = 0;
                _messages.Clear();
            }
        }

        private void DrainBatch(long dispatcherGeneration)
        {
            List<WireSockManager.LogMessage> batch;
            var scheduleNext = false;
            lock (_syncRoot)
            {
                if (_disposed || dispatcherGeneration != _dispatcherGeneration)
                    return;

                batch = new List<WireSockManager.LogMessage>(_batchSize + 1);
                if (_droppedMessages > 0)
                {
                    batch.Add(CreateDroppedMessage(_droppedMessages));
                    _droppedMessages = 0;
                }

                while (batch.Count < _batchSize && _messages.Count > 0)
                    batch.Add(_messages.Dequeue());

                scheduleNext = _messages.Count > 0;
                _dispatchPending = scheduleNext;
            }

            try
            {
                if (batch.Count > 0)
                    _consumeBatch(batch);
            }
            finally
            {
                if (scheduleNext)
                    ScheduleOrCancel(() => DrainBatch(dispatcherGeneration), dispatcherGeneration);
            }
        }

        private void ScheduleOrCancel(Action callback, long dispatcherGeneration)
        {
            var scheduled = false;
            try
            {
                scheduled = _schedule(callback);
            }
            catch (Exception ex)
            {
                Trace.TraceWarning($"Unable to schedule queued native log messages: {ex.Message}");
            }

            if (!scheduled)
                CancelPendingDispatch(dispatcherGeneration);
        }

        private void CancelPendingDispatch(long dispatcherGeneration)
        {
            lock (_syncRoot)
            {
                if (dispatcherGeneration != _dispatcherGeneration)
                    return;

                _dispatchPending = false;
                if (_disposed)
                    _messages.Clear();
            }
        }

        private static WireSockManager.LogMessage CreateDroppedMessage(long count)
        {
            return new WireSockManager.LogMessage
            {
                Message = $"WireSock UI dropped {count} queued log message{(count == 1 ? string.Empty : "s")} while the interface was busy."
            };
        }

        public void Dispose()
        {
            lock (_syncRoot)
            {
                if (_disposed)
                    return;

                _disposed = true;
                _dispatchPending = false;
                _droppedMessages = 0;
                _messages.Clear();
            }
        }
    }
}
