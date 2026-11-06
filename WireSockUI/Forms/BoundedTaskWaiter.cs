using System;
using System.Threading;
using System.Threading.Tasks;

namespace WireSockUI.Forms
{
    internal static class BoundedTaskWaiter
    {
        internal static async Task<bool> WaitAsync(Task task, int timeoutMilliseconds)
        {
            if (task == null)
                throw new ArgumentNullException(nameof(task));
            if (timeoutMilliseconds <= 0)
                throw new ArgumentOutOfRangeException(nameof(timeoutMilliseconds));

            Task completedTask;
            using (var timeoutCancellation = new CancellationTokenSource())
            {
                var timeoutTask = Task.Delay(timeoutMilliseconds, timeoutCancellation.Token);
                completedTask = await Task.WhenAny(task, timeoutTask).ConfigureAwait(false);
                if (completedTask == task)
                    timeoutCancellation.Cancel();
            }

            if (completedTask != task)
            {
                _ = task.ContinueWith(
                    completed =>
                    {
                        // Observe a late fault without retaining the caller or
                        // escalating it through the finalizer thread.
                        var ignored = completed.Exception;
                    },
                    CancellationToken.None,
                    TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously,
                    TaskScheduler.Default);
                return false;
            }

            await task.ConfigureAwait(false);
            return true;
        }
    }
}
