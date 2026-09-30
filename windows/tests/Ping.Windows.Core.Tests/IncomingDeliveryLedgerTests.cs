using Ping.Windows.Core.Incoming;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class IncomingDeliveryLedgerTests
{
    [Fact]
    public void InFlightReservationPreventsConcurrentDuplicateAndFailureCanRetry()
    {
        var ledger = new IncomingDeliveryLedger();
        using (var first = ledger.TryReserve("account", IncomingItemKind.Video, "id"))
        {
            Assert.NotNull(first);
            Assert.Null(ledger.TryReserve("account", IncomingItemKind.Video, "id"));
        }
        using var retry = ledger.TryReserve("account", IncomingItemKind.Video, "id");
        Assert.NotNull(retry);
        retry.Commit();
        Assert.Null(ledger.TryReserve("account", IncomingItemKind.Video, "id"));
    }

    [Fact]
    public void AccountsAndItemKindsHaveIndependentNamespaces()
    {
        var ledger = new IncomingDeliveryLedger();
        using var video = ledger.TryReserve("a", IncomingItemKind.Video, "id");
        video!.Commit();
        using var otherAccount = ledger.TryReserve("b", IncomingItemKind.Video, "id");
        using var chat = ledger.TryReserve("a", IncomingItemKind.Chat, "id");
        Assert.NotNull(otherAccount);
        Assert.NotNull(chat);
    }

    [Fact]
    public void BoundedHistoryEvictsOldestCompletedEntryButKeepsPendingReservation()
    {
        var ledger = new IncomingDeliveryLedger(maximumDelivered: 2);
        using var pending = ledger.TryReserve("a", IncomingItemKind.Video, "pending");
        foreach (var id in new[] { "one", "two", "three" })
        {
            using var lease = ledger.TryReserve("a", IncomingItemKind.Video, id);
            lease!.Commit();
        }
        Assert.Null(ledger.TryReserve("a", IncomingItemKind.Video, "pending"));
        Assert.Null(ledger.TryReserve("a", IncomingItemKind.Video, "three"));
        using var old = ledger.TryReserve("a", IncomingItemKind.Video, "one");
        Assert.NotNull(old);
        Assert.Equal(2, ledger.DeliveredCount);
    }

    [Fact]
    public async Task ReservationIsAtomicAcrossConcurrentObservers()
    {
        var ledger = new IncomingDeliveryLedger();
        var leases = await Task.WhenAll(Enumerable.Range(0, 20).Select(_ => Task.Run(() => ledger.TryReserve("a", IncomingItemKind.Video, "id"))));
        var winner = Assert.Single(leases, lease => lease is not null);
        winner!.Dispose();
    }
}
