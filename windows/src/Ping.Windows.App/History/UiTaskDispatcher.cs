namespace Ping.Windows.App.History;

public sealed class UiTaskDispatcher(Func<bool> hasThreadAccess, Func<Action, bool> tryEnqueue)
{
    public Task<T> RunAsync<T>(Func<Task<T>> work)
    {
        if (hasThreadAccess()) return work();
        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!tryEnqueue(async () =>
        {
            try { completion.TrySetResult(await work()); }
            catch (Exception error) { completion.TrySetException(error); }
        })) completion.TrySetException(new OperationCanceledException("창이 닫혔습니다."));
        return completion.Task;
    }
}
