namespace Ping.Windows.Core.Incoming;

public enum IncomingItemKind { Video, Chat }

public sealed class IncomingDeliveryLedger
{
    private readonly object sync = new();
    private readonly int maximumDelivered;
    private readonly HashSet<DeliveryKey> delivered = [];
    private readonly Queue<DeliveryKey> deliveredOrder = new();
    private readonly HashSet<DeliveryKey> pending = [];

    public IncomingDeliveryLedger(int maximumDelivered = 512)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumDelivered);
        this.maximumDelivered = maximumDelivered;
    }

    public int DeliveredCount { get { lock (sync) return delivered.Count; } }

    public DeliveryReservation? TryReserve(string accountUid, IncomingItemKind kind, string id)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(accountUid);
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        var key = new DeliveryKey(accountUid, kind, id);
        lock (sync)
        {
            if (delivered.Contains(key) || !pending.Add(key)) return null;
            return new DeliveryReservation(this, accountUid, kind, id);
        }
    }

    private void Complete(string accountUid, IncomingItemKind kind, string id, bool success)
    {
        var key = new DeliveryKey(accountUid, kind, id);
        lock (sync)
        {
            pending.Remove(key);
            if (!success || !delivered.Add(key)) return;
            deliveredOrder.Enqueue(key);
            while (deliveredOrder.Count > maximumDelivered) delivered.Remove(deliveredOrder.Dequeue());
        }
    }

    private sealed record DeliveryKey(string AccountUid, IncomingItemKind Kind, string Id);

    public sealed class DeliveryReservation : IDisposable
    {
        private IncomingDeliveryLedger? owner;
        private readonly string accountUid;
        private readonly IncomingItemKind kind;
        private readonly string id;

        internal DeliveryReservation(IncomingDeliveryLedger owner, string accountUid, IncomingItemKind kind, string id)
        {
            this.owner = owner;
            this.accountUid = accountUid;
            this.kind = kind;
            this.id = id;
        }

        public void Commit() => Interlocked.Exchange(ref owner, null)?.Complete(accountUid, kind, id, success: true);
        public void Dispose() => Interlocked.Exchange(ref owner, null)?.Complete(accountUid, kind, id, success: false);
    }
}
