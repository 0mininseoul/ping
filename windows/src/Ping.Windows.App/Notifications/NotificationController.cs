using System.Security;
using System.Text.Json;
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

public sealed class IncomingChatPoller
{
    private static readonly TimeSpan DefaultInterval = TimeSpan.FromSeconds(10);
    private readonly ChatMessageService chatService;
    private readonly RoomService roomService;
    private readonly Func<string?> currentUidProvider;
    private readonly Func<TimeSpan, CancellationToken, Task> delayAsync;
    private readonly TimeSpan interval;

    public IncomingChatPoller(
        ChatMessageService chatService,
        RoomService roomService,
        Func<string?> currentUidProvider,
        TimeSpan? interval = null,
        Func<TimeSpan, CancellationToken, Task>? delayAsync = null)
    {
        this.chatService = chatService;
        this.roomService = roomService;
        this.currentUidProvider = currentUidProvider;
        this.interval = interval ?? DefaultInterval;
        this.delayAsync = delayAsync ?? ((duration, token) => Task.Delay(duration, token));
    }

    public async Task RunAsync(
        Func<IncomingChatNotification, CancellationToken, Task> onChatAsync,
        CancellationToken cancellationToken = default)
    {
        var yieldedChatIds = new HashSet<string>(StringComparer.Ordinal);
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                foreach (var notification in await PollOnceAsync(yieldedChatIds, cancellationToken).ConfigureAwait(false))
                {
                    await onChatAsync(notification, cancellationToken).ConfigureAwait(false);
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

    public async Task<IReadOnlyList<IncomingChatNotification>> PollOnceAsync(
        ISet<string> yieldedChatIds,
        CancellationToken cancellationToken = default)
    {
        var currentUid = currentUidProvider();
        if (string.IsNullOrWhiteSpace(currentUid))
        {
            return [];
        }

        var unreadCounts = await chatService.UnreadChatCountsAsync(cancellationToken).ConfigureAwait(false);
        if (unreadCounts.Count == 0)
        {
            return [];
        }

        var rooms = await roomService.MyRoomsAsync(cancellationToken).ConfigureAwait(false);
        var roomsById = rooms
            .Where(room => room.Id is not null)
            .ToDictionary(room => room.Id!, StringComparer.Ordinal);
        var notifications = new List<IncomingChatNotification>();

        foreach (var (roomId, unreadCount) in unreadCounts.OrderBy(pair => pair.Key, StringComparer.Ordinal))
        {
            if (unreadCount <= 0 || !roomsById.TryGetValue(roomId, out var room))
            {
                continue;
            }

            var pageLimit = ChatNotificationPageLimit(unreadCount);
            var messages = await chatService.RoomChatMessagesAsync(roomId, limit: pageLimit, cancellationToken: cancellationToken)
                .ConfigureAwait(false);
            var latestUnread = messages
                .Where(message => !string.Equals(message.SenderUid, currentUid, StringComparison.Ordinal))
                .OrderByDescending(message => message.CreatedAt ?? DateTimeOffset.MinValue)
                .FirstOrDefault();
            if (latestUnread?.Id is not { Length: > 0 } chatId || yieldedChatIds.Contains(chatId))
            {
                continue;
            }

            yieldedChatIds.Add(chatId);
            notifications.Add(new IncomingChatNotification(latestUnread, room.Name, unreadCount));
        }

        return notifications;
    }

    private static int ChatNotificationPageLimit(int unreadCount) =>
        Math.Clamp(unreadCount + 10, 10, 50);
}

public sealed record IncomingChatNotification(ChatMessage Message, string RoomName, int UnreadCount);

public sealed class NotifiedMessageRegistry
{
    private const int MaximumPersistedIds = 300;
    private readonly HashSet<string> notifiedIds = new(StringComparer.Ordinal);
    private readonly List<string> orderedIds = [];
    private readonly string? persistencePath;

    public NotifiedMessageRegistry()
        : this(DefaultPersistencePath())
    {
    }

    public NotifiedMessageRegistry(string persistencePath)
    {
        this.persistencePath = persistencePath;
        LoadPersistedIds();
    }

    private NotifiedMessageRegistry(string? persistencePath, bool loadPersistedIds)
    {
        this.persistencePath = persistencePath;
        if (loadPersistedIds)
        {
            LoadPersistedIds();
        }
    }

    public static NotifiedMessageRegistry InMemory() =>
        new(persistencePath: null, loadPersistedIds: false);

    public bool TryMarkNotified(VideoMessage message)
    {
        if (message.Id is not { Length: > 0 } id)
        {
            return false;
        }

        lock (notifiedIds)
        {
            if (!notifiedIds.Add(id))
            {
                return false;
            }

            orderedIds.Add(id);
            TrimToRecentWindow();
            PersistIds();
            return true;
        }
    }

    public bool Contains(string messageId)
    {
        lock (notifiedIds)
        {
            return notifiedIds.Contains(messageId);
        }
    }

    public void Forget(string messageId)
    {
        lock (notifiedIds)
        {
            notifiedIds.Remove(messageId);
            orderedIds.RemoveAll(id => string.Equals(id, messageId, StringComparison.Ordinal));
            PersistIds();
        }
    }

    private void LoadPersistedIds()
    {
        if (persistencePath is null || !File.Exists(persistencePath))
        {
            return;
        }

        try
        {
            var ids = JsonSerializer.Deserialize<IReadOnlyList<string>>(File.ReadAllText(persistencePath))
                ?? [];
            foreach (var id in ids.Where(id => !string.IsNullOrWhiteSpace(id)).TakeLast(MaximumPersistedIds))
            {
                if (notifiedIds.Add(id))
                {
                    orderedIds.Add(id);
                }
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
        }
    }

    private void PersistIds()
    {
        if (persistencePath is null)
        {
            return;
        }

        try
        {
            var directory = Path.GetDirectoryName(persistencePath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(persistencePath, JsonSerializer.Serialize(orderedIds));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }
    }

    private void TrimToRecentWindow()
    {
        while (orderedIds.Count > MaximumPersistedIds)
        {
            var removedId = orderedIds[0];
            orderedIds.RemoveAt(0);
            notifiedIds.Remove(removedId);
        }
    }

    private static string DefaultPersistencePath()
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(localAppData, "Ping", "NotifiedMessageIds.json");
    }
}

public sealed class NotificationController : IDisposable
{
    private readonly Func<string, CancellationToken, Task> openMessageAsync;
    private readonly NotifiedMessageRegistry registry;
    private readonly NotifiedChatRegistry chatRegistry;
    private bool disposed;
#if WINDOWS
    private readonly Func<string, string, CancellationToken, Task>? openChatAsync;
    private bool isRegistered;
#endif

    public NotificationController(
        Func<string, CancellationToken, Task> openMessageAsync,
        Func<string, string, CancellationToken, Task>? openChatAsync = null,
        NotifiedMessageRegistry? registry = null,
        NotifiedChatRegistry? chatRegistry = null)
    {
        this.openMessageAsync = openMessageAsync;
#if WINDOWS
        this.openChatAsync = openChatAsync;
#endif
        this.registry = registry ?? new NotifiedMessageRegistry();
        this.chatRegistry = chatRegistry ?? new NotifiedChatRegistry();
    }

    public void Start()
    {
#if WINDOWS
        try
        {
            AppNotificationManager.Default.NotificationInvoked += HandleNotificationInvoked;
            AppNotificationManager.Default.Register();
            isRegistered = true;
        }
        catch (Exception)
        {
            AppNotificationManager.Default.NotificationInvoked -= HandleNotificationInvoked;
            isRegistered = false;
        }
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
#if WINDOWS
        if (!isRegistered)
        {
            return false;
        }
#endif

        if (!registry.TryMarkNotified(message))
        {
            return false;
        }

#if WINDOWS
        try
        {
            var notification = new AppNotification(NotificationXml(message));
            AppNotificationManager.Default.Show(notification);
        }
        catch (Exception)
        {
            if (message.Id is { Length: > 0 } id)
            {
                registry.Forget(id);
            }

            return false;
        }
#endif
        return true;
    }

    public bool TryShowIncomingChat(IncomingChatNotification notification)
    {
#if WINDOWS
        if (!isRegistered)
        {
            return false;
        }
#endif

        if (!chatRegistry.TryMarkNotified(notification.Message))
        {
            return false;
        }

#if WINDOWS
        try
        {
            var toast = new AppNotification(NotificationXml(notification));
            AppNotificationManager.Default.Show(toast);
        }
        catch (Exception)
        {
            if (notification.Message.Id is { Length: > 0 } id)
            {
                chatRegistry.Forget(id);
            }

            return false;
        }
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
        isRegistered = false;
#endif
        disposed = true;
    }

#if WINDOWS
    private void HandleNotificationInvoked(
        AppNotificationManager sender,
        AppNotificationActivatedEventArgs args)
    {
        var parsed = ParseActivationArguments(args);
        if (string.Equals(parsed.Action, "play", StringComparison.Ordinal)
            && !string.IsNullOrWhiteSpace(parsed.MessageId))
        {
            _ = openMessageAsync(parsed.MessageId, CancellationToken.None);
            return;
        }

        if (!string.Equals(parsed.Action, "chat", StringComparison.Ordinal)
            || string.IsNullOrWhiteSpace(parsed.ChatId)
            || string.IsNullOrWhiteSpace(parsed.RoomId)
            || openChatAsync is null)
        {
            return;
        }

        _ = openChatAsync(parsed.ChatId, parsed.RoomId, CancellationToken.None);
    }

    private static NotificationActivationArguments ParseActivationArguments(AppNotificationActivatedEventArgs args)
        => NotificationActivationArguments.From(args);
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

    private static string NotificationXml(IncomingChatNotification notification)
    {
        var chatId = Uri.EscapeDataString(notification.Message.Id ?? string.Empty);
        var roomId = Uri.EscapeDataString(notification.Message.RoomId);
        var sender = SecurityElement.Escape(notification.Message.SenderNickname) ?? "Ping";
        var roomName = SecurityElement.Escape(notification.RoomName) ?? "Room";
        var body = string.IsNullOrWhiteSpace(notification.Message.Body)
            ? "Image attachment"
            : notification.Message.Body;
        if (body.Length > 160)
        {
            body = body[..160] + "...";
        }

        var escapedBody = SecurityElement.Escape(body) ?? string.Empty;
        var countText = notification.UnreadCount > 1
            ? $"{notification.UnreadCount} unread messages"
            : roomName;
        var escapedCount = SecurityElement.Escape(countText) ?? roomName;
        return
            $"""
            <toast launch="action=chat&amp;chat_id={chatId}&amp;room_id={roomId}">
              <visual>
                <binding template="ToastGeneric">
                  <text>{sender}</text>
                  <text>{escapedBody}</text>
                  <text>{escapedCount}</text>
                </binding>
              </visual>
            </toast>
            """;
    }
}

public sealed class NotifiedChatRegistry
{
    private const int MaximumPersistedIds = 500;
    private readonly HashSet<string> notifiedIds = new(StringComparer.Ordinal);
    private readonly List<string> orderedIds = [];
    private readonly string? persistencePath;

    public NotifiedChatRegistry()
        : this(DefaultPersistencePath())
    {
    }

    public NotifiedChatRegistry(string persistencePath)
    {
        this.persistencePath = persistencePath;
        LoadPersistedIds();
    }

    private NotifiedChatRegistry(string? persistencePath, bool loadPersistedIds)
    {
        this.persistencePath = persistencePath;
        if (loadPersistedIds)
        {
            LoadPersistedIds();
        }
    }

    public static NotifiedChatRegistry InMemory() =>
        new(persistencePath: null, loadPersistedIds: false);

    public bool TryMarkNotified(ChatMessage message)
    {
        if (message.Id is not { Length: > 0 } id)
        {
            return false;
        }

        lock (notifiedIds)
        {
            if (!notifiedIds.Add(id))
            {
                return false;
            }

            orderedIds.Add(id);
            TrimToRecentWindow();
            PersistIds();
            return true;
        }
    }

    public bool Contains(string chatId)
    {
        lock (notifiedIds)
        {
            return notifiedIds.Contains(chatId);
        }
    }

    public void Forget(string chatId)
    {
        lock (notifiedIds)
        {
            notifiedIds.Remove(chatId);
            orderedIds.RemoveAll(id => string.Equals(id, chatId, StringComparison.Ordinal));
            PersistIds();
        }
    }

    private void LoadPersistedIds()
    {
        if (persistencePath is null || !File.Exists(persistencePath))
        {
            return;
        }

        try
        {
            var ids = JsonSerializer.Deserialize<IReadOnlyList<string>>(File.ReadAllText(persistencePath))
                ?? [];
            foreach (var id in ids.Where(id => !string.IsNullOrWhiteSpace(id)).TakeLast(MaximumPersistedIds))
            {
                if (notifiedIds.Add(id))
                {
                    orderedIds.Add(id);
                }
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
        }
    }

    private void PersistIds()
    {
        if (persistencePath is null)
        {
            return;
        }

        try
        {
            var directory = Path.GetDirectoryName(persistencePath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(persistencePath, JsonSerializer.Serialize(orderedIds));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }
    }

    private void TrimToRecentWindow()
    {
        while (orderedIds.Count > MaximumPersistedIds)
        {
            var removedId = orderedIds[0];
            orderedIds.RemoveAt(0);
            notifiedIds.Remove(removedId);
        }
    }

    private static string DefaultPersistencePath()
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(localAppData, "Ping", "NotifiedChatIds.json");
    }
}

public sealed record NotificationActivationArguments(
    string? Action,
    string? MessageId,
    string? ChatId = null,
    string? RoomId = null)
{
    public bool HasValues =>
        !string.IsNullOrWhiteSpace(Action)
        || !string.IsNullOrWhiteSpace(MessageId)
        || !string.IsNullOrWhiteSpace(ChatId)
        || !string.IsNullOrWhiteSpace(RoomId);

    public static NotificationActivationArguments From(IDictionary<string, string> values)
    {
        values.TryGetValue("action", out var action);
        values.TryGetValue("message_id", out var messageId);
        values.TryGetValue("chat_id", out var chatId);
        values.TryGetValue("room_id", out var roomId);
        return new(action, messageId, chatId, roomId);
    }

#if WINDOWS
    public static NotificationActivationArguments From(AppNotificationActivatedEventArgs args)
    {
        var parsed = From(args.Arguments);
        return parsed.HasValues
            ? parsed
            : Parse(args.Argument);
    }
#endif

    public static NotificationActivationArguments Parse(string? arguments)
    {
        if (string.IsNullOrWhiteSpace(arguments))
        {
            return new(null, null);
        }

        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var part in arguments.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = part.Split('=', 2);
            if (parts.Length != 2)
            {
                continue;
            }

            if (!TryUnescapeComponent(parts[0], out var key) || values.ContainsKey(key))
            {
                continue;
            }

            if (!TryUnescapeComponent(parts[1], out var value))
            {
                continue;
            }

            values[key] = value;
        }

        values.TryGetValue("action", out var action);
        values.TryGetValue("message_id", out var messageId);
        values.TryGetValue("chat_id", out var chatId);
        values.TryGetValue("room_id", out var roomId);
        return new(action, messageId, chatId, roomId);
    }

    private static bool TryUnescapeComponent(string value, out string unescaped)
    {
        unescaped = string.Empty;
        if (!HasValidPercentEscapes(value))
        {
            return false;
        }

        unescaped = Uri.UnescapeDataString(value);
        return true;
    }

    private static bool HasValidPercentEscapes(string value)
    {
        for (var index = 0; index < value.Length; index++)
        {
            if (value[index] != '%')
            {
                continue;
            }

            if (index + 2 >= value.Length
                || !Uri.IsHexDigit(value[index + 1])
                || !Uri.IsHexDigit(value[index + 2]))
            {
                return false;
            }

            index += 2;
        }

        return true;
    }
}
