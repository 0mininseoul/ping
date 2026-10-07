using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Ping.Windows.App.History;

public sealed partial class HistoryWindow
{
    private string? lastScrolledRoomId;
    private string? observedRoomId;
    private string? pendingRoomEntryId;
    private ScrollViewer? timelineScrollViewer;
    private string? pendingScrollRoomId;
    private TimelineHistoryItem? pendingScrollItem;
    private bool pendingScrollToNewest;
    private bool pendingScrollPrimed;
    private double? pendingScrollOffset;
    private (TimelineHistoryItem Item, double Y)? pendingScrollAnchor;
    private TimelineHistoryItem[] viewportRows = [];
    private string? viewportRoomId;
    private double? viewportOffset;
    private bool viewportFollowsNewest;
    private (TimelineHistoryItem Item, double Y)? viewportAnchor;

    private void HandleTimelineRoomChanged()
    {
        if (observedRoomId == viewModel.SelectedRoom?.Id) return;
        observedRoomId = viewModel.SelectedRoom?.Id;
        pendingRoomEntryId = observedRoomId;
        lastScrolledRoomId = null;
        ClearPendingTimelineScroll();
    }

    private void TimelineScrollViewer_ViewChanged(object? sender, ScrollViewerViewChangedEventArgs args)
    {
        if (pendingScrollItem is not null && !detached)
            DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, ApplyPendingTimelineScroll);
    }

    private void ClearPendingTimelineScroll()
    {
        pendingScrollRoomId = null;
        pendingScrollItem = null;
        pendingScrollToNewest = false;
        pendingScrollPrimed = false;
        pendingScrollOffset = null;
        pendingScrollAnchor = null;
    }

    private void QueueNewestTimelineScroll()
    {
        // A room can be selected while the previous room's rows are still visible.
        if (viewModel.TimelineRoomId != viewModel.SelectedRoom?.Id) return;
        if (viewModel.Timeline.LastOrDefault() is { } newest)
            QueueTimelineScroll(newest, toNewest: true);
    }

    private void QueueTimelineScroll(TimelineHistoryItem target, bool toNewest)
    {
        ClearPendingTimelineScroll();
        pendingScrollRoomId = viewModel.SelectedRoom?.Id;
        pendingScrollItem = target;
        pendingScrollToNewest = toNewest;
        VideosList.InvalidateMeasure();
        // Layout may already have finished before the async room load returns.
        DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, ApplyPendingTimelineScroll);
    }

    private void ApplyPendingTimelineScroll()
    {
        if (detached || VideosList.ActualHeight <= 0 || VideosList.Visibility != Visibility.Visible) return;
        if (pendingScrollRoomId != viewModel.SelectedRoom?.Id)
        {
            ClearPendingTimelineScroll();
            return;
        }
        if (FindVisualChild<ScrollViewer>(VideosList) is not { } scroll || scroll.ViewportHeight <= 0) return;
        if (!ReferenceEquals(timelineScrollViewer, scroll))
        {
            if (timelineScrollViewer is not null) timelineScrollViewer.ViewChanged -= TimelineScrollViewer_ViewChanged;
            timelineScrollViewer = scroll;
            timelineScrollViewer.ViewChanged += TimelineScrollViewer_ViewChanged;
        }

        if (pendingScrollItem is { } target)
        {
            if (!viewModel.Timeline.Contains(target))
            {
                ClearPendingTimelineScroll();
                return;
            }
            if (!pendingScrollPrimed)
            {
                pendingScrollPrimed = true;
                VideosList.ScrollIntoView(target);
                VideosList.InvalidateMeasure();
                return;
            }
            if (VideosList.ContainerFromItem(target) is not FrameworkElement container || container.ActualHeight <= 0) return;
            var y = container.TransformToVisual(VideosList).TransformPoint(new global::Windows.Foundation.Point()).Y;
            var bottomVisible = y + container.ActualHeight <= scroll.ViewportHeight + 1;
            if (pendingScrollToNewest)
            {
                // Virtualized rows must be measured before the final bottom offset is known.
                if (bottomVisible && scroll.ScrollableHeight - scroll.VerticalOffset <= 1)
                {
                    lastScrolledRoomId = pendingScrollRoomId;
                    ClearPendingTimelineScroll();
                }
                else scroll.ChangeView(null, scroll.ScrollableHeight, null, true);
            }
            else if ((bottomVisible && y >= -1)
                || (container.ActualHeight >= scroll.ViewportHeight && y <= 1 && y + container.ActualHeight >= scroll.ViewportHeight - 1))
            {
                lastScrolledRoomId = pendingScrollRoomId;
                ClearPendingTimelineScroll();
            }
            else VideosList.ScrollIntoView(target);
            return;
        }

        if (pendingScrollOffset is not { } offset) return;
        if (pendingScrollAnchor is { } anchor && VideosList.ContainerFromItem(anchor.Item) is FrameworkElement anchoredContainer)
            offset = scroll.VerticalOffset + anchoredContainer.TransformToVisual(VideosList).TransformPoint(new global::Windows.Foundation.Point()).Y - anchor.Y;
        ClearPendingTimelineScroll();
        scroll.ChangeView(null, Math.Clamp(offset, 0, scroll.ScrollableHeight), null, true);
    }

    private void CaptureTimelineViewport(object? sender, EventArgs args)
    {
        viewportRoomId = viewModel.SelectedRoom?.Id;
        viewportRows = viewModel.Timeline.ToArray();
        viewportOffset = null;
        viewportAnchor = null;
        viewportFollowsNewest = false;
        if (pendingScrollItem is not null || viewportRoomId != lastScrolledRoomId
            || FindVisualChild<ScrollViewer>(VideosList) is not { } scroll) return;
        viewportOffset = scroll.VerticalOffset;
        viewportFollowsNewest = scroll.ScrollableHeight - scroll.VerticalOffset <= 32;
        foreach (var row in viewportRows)
        {
            if (VideosList.ContainerFromItem(row) is not FrameworkElement container) continue;
            var y = container.TransformToVisual(VideosList).TransformPoint(new global::Windows.Foundation.Point()).Y;
            if (y + container.ActualHeight <= 0 || y >= VideosList.ActualHeight) continue;
            viewportAnchor = (row, y);
            break;
        }
    }

    private void RestoreTimelineViewport(object? sender, EventArgs args)
    {
        if (pendingScrollItem is not null && !pendingScrollToNewest) return;
        if (viewModel.SelectedRoom?.Id != lastScrolledRoomId || pendingScrollToNewest)
        {
            QueueNewestTimelineScroll();
            return;
        }
        if (viewportOffset is null || viewportRoomId != viewModel.SelectedRoom?.Id
            || viewportRows.SequenceEqual(viewModel.Timeline)) return;
        if (viewportFollowsNewest)
            QueueNewestTimelineScroll();
        else
        {
            ClearPendingTimelineScroll();
            pendingScrollRoomId = viewportRoomId;
            pendingScrollOffset = viewportOffset;
            pendingScrollAnchor = viewportAnchor is { } anchor && viewModel.Timeline.Contains(anchor.Item) ? anchor : null;
            VideosList.InvalidateMeasure();
        }
    }
}
