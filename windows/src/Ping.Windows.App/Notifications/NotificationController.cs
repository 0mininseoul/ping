using System.Security;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;

#if WINDOWS
using Microsoft.Windows.AppLifecycle;
using Microsoft.Windows.AppNotifications;
#endif

namespace Ping.Windows.App.Notifications;

public sealed class IncomingMessagePoller
{
    private static readonly TimeSpan DefaultInterval = TimeSpan.FromSeconds(2);
    private readonly Func<CancellationToken, Task<IReadOnlyList<VideoMessage>>> loadMessagesAsync;
    private readonly Func<TimeSpan, CancellationToken, Task> delayAsync;
    private readonly TimeSpan interval;

    public IncomingMessagePoller(
        MessageService messageService,
        TimeSpan? interval = null,
        Func<TimeSpan, CancellationToken, Task>? delayAsync = null)
        : this(
            messageService.IncomingAsync,
            interval,
            delayAsync)
    {
    }

    public IncomingMessagePoller(
        Func<CancellationToken, Task<IReadOnlyList<VideoMessage>>> loadMessagesAsync,
        TimeSpan? interval = null,
        Func<TimeSpan, CancellationToken, Task>? delayAsync = null)
    {
        this.loadMessagesAsync = loadMessagesAsync;
        this.interval = interval ?? DefaultInterval;
        this.delayAsync = delayAsync ?? ((duration, token) => Task.Delay(duration, token));
    }

    public async Task RunAsync(
        Func<VideoMessage, CancellationToken, Task> onMessageAsync,
        CancellationToken cancellationToken = default)
    {
        var yieldedIds = new HashSet<string>(StringComparer.Ordinal);
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                foreach (var message in await PollOnceAsync(yieldedIds, cancellationToken).ConfigureAwait(false))
                {
                    await onMessageAsync(message, cancellationToken).ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception)
            {
            }

            await delayAsync(interval, cancellationToken).ConfigureAwait(false);
        }
    }

    public async Task<IReadOnlyList<VideoMessage>> PollOnceAsync(
        ISet<string> yieldedIds,
        CancellationToken cancellationToken = default)
    {
        var messages = await loadMessagesAsync(cancellationToken).ConfigureAwait(false);
        var freshMessages = new List<VideoMessage>();
        foreach (var message in messages.OrderBy(message => message.CreatedAt ?? DateTimeOffset.MaxValue))
        {
            if (message.Id is not { Length: > 0 } id || yieldedIds.Contains(id))
            {
                continue;
            }

            yieldedIds.Add(id);
            freshMessages.Add(message);
        }

        return freshMessages;
    }
}

public sealed class NotifiedMessageRegistry
{
    private readonly HashSet<string> notifiedIds = new(StringComparer.Ordinal);

    public bool TryMarkNotified(VideoMessage message)
    {
        if (message.Id is not { Length: > 0 } id)
        {
            return false;
        }

        lock (notifiedIds)
        {
            return notifiedIds.Add(id);
        }
    }

    public bool Contains(string messageId)
    {
        lock (notifiedIds)
        {
            return notifiedIds.Contains(messageId);
        }
    }
}

public sealed class NotificationController : IDisposable
{
    private readonly Func<string, CancellationToken, Task> openMessageAsync;
    private readonly NotifiedMessageRegistry registry;
    private bool disposed;

    public NotificationController(
        Func<string, CancellationToken, Task> openMessageAsync,
        NotifiedMessageRegistry? registry = null)
    {
        this.openMessageAsync = openMessageAsync;
        this.registry = registry ?? new NotifiedMessageRegistry();
    }

    public void Start()
    {
#if WINDOWS
        AppNotificationManager.Default.NotificationInvoked += HandleNotificationInvoked;
        AppNotificationManager.Default.Register();
#endif
    }

    public NotificationActivationArguments? TryGetInitialActivationArguments()
    {
#if WINDOWS
        try
        {
            var activatedArgs = AppInstance.GetCurrent().GetActivatedEventArgs();
            if (activatedArgs is null || activatedArgs.Kind != ExtendedActivationKind.AppNotification)
            {
                return null;
            }

            return activatedArgs.Data is AppNotificationActivatedEventArgs notificationArgs
                ? ParseActivationArguments(notificationArgs)
                : null;
        }
        catch (Exception)
        {
            return null;
        }
#else
        return null;
#endif
    }

    public bool TryShowIncoming(VideoMessage message)
    {
        if (!registry.TryMarkNotified(message))
        {
            return false;
        }

#if WINDOWS
        var notification = new AppNotification(NotificationXml(message));
        AppNotificationManager.Default.Show(notification);
#endif
        return true;
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

#if WINDOWS
        AppNotificationManager.Default.NotificationInvoked -= HandleNotificationInvoked;
#endif
        disposed = true;
    }

#if WINDOWS
    private void HandleNotificationInvoked(
        AppNotificationManager sender,
        AppNotificationActivatedEventArgs args)
    {
        var parsed = ParseActivationArguments(args);
        if (!string.Equals(parsed.Action, "play", StringComparison.Ordinal)
            || string.IsNullOrWhiteSpace(parsed.MessageId))
        {
            return;
        }

        _ = openMessageAsync(parsed.MessageId, CancellationToken.None);
    }

    private static NotificationActivationArguments ParseActivationArguments(AppNotificationActivatedEventArgs args)
    {
        var parsed = NotificationActivationArguments.From(args.Arguments);
        return parsed.HasValues
            ? parsed
            : NotificationActivationArguments.Parse(args.Argument);
    }
#endif

    private static string NotificationXml(VideoMessage message)
    {
        var messageId = Uri.EscapeDataString(message.Id ?? string.Empty);
        var sender = SecurityElement.Escape(message.SenderNickname) ?? "Ping";
        return
            $"""
            <toast launch="action=play&amp;message_id={messageId}">
              <visual>
                <binding template="ToastGeneric">
                  <text>{sender}</text>
                  <text>새 Ping 메시지</text>
                </binding>
              </visual>
            </toast>
            """;
    }
}

public sealed record NotificationActivationArguments(string? Action, string? MessageId)
{
    public bool HasValues =>
        !string.IsNullOrWhiteSpace(Action) || !string.IsNullOrWhiteSpace(MessageId);

    public static NotificationActivationArguments From(IDictionary<string, string> values)
    {
        values.TryGetValue("action", out var action);
        values.TryGetValue("message_id", out var messageId);
        return new(action, messageId);
    }

    public static NotificationActivationArguments Parse(string? arguments)
    {
        if (string.IsNullOrWhiteSpace(arguments))
        {
            return new(null, null);
        }

        var values = arguments
            .Split('&', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => part.Split('=', 2))
            .Where(parts => parts.Length == 2)
            .ToDictionary(
                parts => Uri.UnescapeDataString(parts[0]),
                parts => Uri.UnescapeDataString(parts[1]),
                StringComparer.Ordinal);
        values.TryGetValue("action", out var action);
        values.TryGetValue("message_id", out var messageId);
        return new(action, messageId);
    }
}
