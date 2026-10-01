#if WINDOWS
using System.ComponentModel;
using Ping.Windows.Core.Capture;
using Ping.Windows.Core.Models;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Ping.Windows.App.UI;
using Windows.Media.Core;
using Windows.Media.Playback;

namespace Ping.Windows.App.Capture;

public sealed partial class ScreenFaceMirrorWindow : Window
{
    private readonly ScreenFaceMirrorViewModel viewModel;
    private IFacePreviewSession? previewRecorder;
    private readonly Func<Ping.Windows.Core.Capture.CameraLease, IFacePreviewSession> previewFactory;
    private readonly Ping.Windows.Core.Capture.CameraLease cameraLease;
    private readonly CancellationTokenSource windowLifetime = new();
    public Task CameraShutdown { get; private set; } = Task.CompletedTask;
    private CancellationTokenSource? previewLoopCancellation;
    private Task? previewLoopTask;
    private Task previewStopTask = Task.CompletedTask;
    private Task previewStartTask = Task.CompletedTask;
    private bool handlingEnter;
    private MediaPlayer? reviewPlayer;
    private CaptureMirrorWindowHost? mirrorHost;
    internal CaptureViewportInput ViewportInput { get; private set; } = null!;
    private Task inputShutdown = Task.CompletedTask;
    private bool shouldCloseAfterFade;
    private readonly RecordingPreviewPresenter recordingPreview;
    private Task recordingPreviewShutdown = Task.CompletedTask;

    public ScreenFaceMirrorWindow(ScreenFaceMirrorViewModel viewModel, Ping.Windows.Core.Capture.CameraLease cameraLease,
        Func<Ping.Windows.Core.Capture.CameraLease, IFacePreviewSession>? previewFactory = null)
    {
        this.viewModel = viewModel;
        this.cameraLease = cameraLease;
        this.previewFactory = previewFactory ?? (lease => new FaceRecorder(lease));
        InitializeComponent();
        recordingPreview = new(RecordingPreviewImage, () =>
        {
            ScreenPreviewPlaceholder.Visibility = Visibility.Collapsed;
            FacePreviewBubble.Visibility = Visibility.Collapsed;
        });
        Root.DataContext = viewModel;
        Root.Loaded += HandleLoaded;
        viewModel.PropertyChanged += HandleViewModelPropertyChanged;
        viewModel.FadeOutRequested += HandleFadeOutRequested;
        viewModel.CloseRequested += HandleCloseRequested;
        SetStateBrush();
        ConfigureWindow();
        ViewportInput = new(viewModel, Root, mirrorHost!);
    }

    private async void HandleKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (HandleTargetOrViewportKey(args.Key, CaptureViewportInput.AltPressed))
        {
            args.Handled = true;
            return;
        }

        if (args.Key == global::Windows.System.VirtualKey.Enter)
        {
            args.Handled = true;
            await HandleEnterAsync();
            return;
        }

        if (args.Key == global::Windows.System.VirtualKey.Back
            || args.Key == global::Windows.System.VirtualKey.Delete)
        {
            args.Handled = true;
            await HandleRedoAsync();

            return;
        }

        if (args.Key == global::Windows.System.VirtualKey.Escape)
        {
            args.Handled = true;
            viewModel.HandleEscape();
        }
    }

    internal async Task HandleEnterAsync()
    {
        if (handlingEnter || windowLifetime.IsCancellationRequested) return;
        handlingEnter = true;
        var selection = viewModel.CaptureSelection;
        var recording = viewModel.CanRecord;
        if (recording) viewModel.SetCapturePreparing(true);
        try
        {
            if (recording) await StopPreviewAsync();
            if (windowLifetime.IsCancellationRequested) return;
            var preview = recording ? recordingPreview.Start() : null;
            await viewModel.HandleEnterAsync(selection, preview);
        }
        finally
        {
            if (recording) await recordingPreview.StopAsync();
            viewModel.SetCapturePreparing(false);
            handlingEnter = false;
            if (!viewModel.IsCloseRequested && !viewModel.HasReviewedClip) _ = StartPreviewAsync();
        }
    }

    internal async Task HandleRedoAsync()
    {
        if (handlingEnter || windowLifetime.IsCancellationRequested || !viewModel.HasReviewedClip) return;
        handlingEnter = true;
        try
        {
            await viewModel.HandleRedoAsync();
            if (!viewModel.IsCloseRequested && !viewModel.HasReviewedClip) await StartPreviewAsync();
        }
        finally { handlingEnter = false; }
    }

    internal bool HandleTargetOrViewportKey(global::Windows.System.VirtualKey key, bool alt)
    {
        if (alt && key is (global::Windows.System.VirtualKey.Number0 or global::Windows.System.VirtualKey.NumberPad0)) return ViewportInput.Reset(true);
        return HandleTargetKey(key);
    }

    private bool HandleTargetKey(global::Windows.System.VirtualKey key)
    {
        switch (key)
        {
            case global::Windows.System.VirtualKey.Tab:
                return viewModel.SelectNextTarget();
            case global::Windows.System.VirtualKey.A:
            case global::Windows.System.VirtualKey.Number0:
            case global::Windows.System.VirtualKey.NumberPad0:
                return viewModel.SelectAllTargets();
        }

        var keyValue = (int)key;
        if (keyValue >= (int)global::Windows.System.VirtualKey.Number1
            && keyValue <= (int)global::Windows.System.VirtualKey.Number9)
        {
            return viewModel.SelectTargetAtIndex(keyValue - (int)global::Windows.System.VirtualKey.Number1);
        }

        if (keyValue >= (int)global::Windows.System.VirtualKey.NumberPad1
            && keyValue <= (int)global::Windows.System.VirtualKey.NumberPad9)
        {
            return viewModel.SelectTargetAtIndex(keyValue - (int)global::Windows.System.VirtualKey.NumberPad1);
        }

        return false;
    }

    private void PartnerChip_Tapped(object sender, TappedRoutedEventArgs args)
    {
        if (!viewModel.CanSelectTarget || !viewModel.HasTargetMenu)
        {
            return;
        }

        var flyout = new MenuFlyout();
        foreach (var option in viewModel.TargetOptions)
        {
            var item = new ToggleMenuFlyoutItem
            {
                Text = option.Label,
                IsChecked = option.IsSelected
            };
            item.Click += (_, _) => viewModel.SelectTargetOption(option);
            flyout.Items.Add(item);
        }

        flyout.ShowAt(PartnerChip);
        args.Handled = true;
    }

    private void HandleLoaded(object sender, RoutedEventArgs args)
    {
        Root.Focus(FocusState.Programmatic);
        mirrorHost?.Refresh();
        _ = StartPreviewAsync();
    }

    private void HandleViewModelPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName == nameof(ScreenFaceMirrorViewModel.State)
            || args.PropertyName == nameof(ScreenFaceMirrorViewModel.IsAllTargetsSelected))
        {
            SetStateBrush();
        }

        if (args.PropertyName == nameof(ScreenFaceMirrorViewModel.State)
            || args.PropertyName == nameof(ScreenFaceMirrorViewModel.ReviewVideoUri))
        {
            UpdateReviewPlayback();
        }

        if (args.PropertyName == nameof(ScreenFaceMirrorViewModel.ScreenPreviewUri))
        {
            ScreenPreviewPlaceholder.Visibility =
                viewModel.ScreenPreviewUri is null && viewModel.State != MirrorState.Reviewing
                    ? Visibility.Visible
                    : Visibility.Collapsed;
        }
    }

    private void HandleCloseRequested(object? sender, EventArgs args)
    {
        if (shouldCloseAfterFade)
        {
            return;
        }

        Close();
    }

    private async void HandleFadeOutRequested(object? sender, EventArgs args)
    {
        shouldCloseAfterFade = true;
        var animation = new DoubleAnimation
        {
            To = 0,
            Duration = new Duration(TimeSpan.FromMilliseconds(300))
        };
        Storyboard.SetTarget(animation, Root);
        Storyboard.SetTargetProperty(animation, nameof(Root.Opacity));
        var storyboard = new Storyboard();
        storyboard.Children.Add(animation);
        var completed = new TaskCompletionSource();
        storyboard.Completed += (_, _) => completed.SetResult();
        storyboard.Begin();
        await completed.Task;
        Close();
    }

    private void ConfigureWindow()
    {
        mirrorHost = new(this, Root, CaptureMode.ScreenFace, viewModel.PreferredMirrorPosition,
            (bounds, display, save) =>
            {
                viewModel.UpdateMirrorPlacement(bounds, display.Display, display.WorkArea, save);
                viewModel.UpdateCaptureMonitor(display.MonitorIndex);
            },
            (width, height) =>
            {
                MirrorBorder.CornerRadius = new(16);
                HintLabel.MaxWidth = Math.Max(20, width - 48);
                ViewportGuideLabel.MaxWidth = Math.Max(20, width - 48);
                PartnerLabelElement.MaxWidth = Math.Max(20, width - 48);
                var diameter = Math.Min(width, height) * .32;
                var padding = Math.Min(width, height) * .045;
                FacePreviewBubble.Width = diameter;
                FacePreviewBubble.Height = diameter;
                FacePreviewBubble.Margin = new(0, 0, padding, padding);
                FacePreviewBubble.CornerRadius = new(diameter / 2);
                RoundedCompositionClip.Apply(FacePreviewBubble, diameter, diameter, diameter / 2);
            }, PartnerChip);
    }
    private Task StartPreviewAsync()
    {
        if (!previewStartTask.IsCompleted) return previewStartTask;
        return previewStartTask = StartPreviewCoreAsync();
    }

    private async Task StartPreviewCoreAsync()
    {
        await StopPreviewAsync();
        if (windowLifetime.IsCancellationRequested) return;
        if (viewModel.State == MirrorState.Reviewing || viewModel.HasReviewedClip)
        {
            return;
        }

        previewLoopCancellation = CancellationTokenSource.CreateLinkedTokenSource(windowLifetime.Token);
        var token = previewLoopCancellation.Token;

        var loopTask = viewModel.RunPreviewLoopAsync(token);
        previewLoopTask = loopTask;
        try
        {
            previewRecorder = previewFactory(cameraLease);
            await previewRecorder.StartPreviewAsync(FacePreviewElement, token);
            if (token.IsCancellationRequested) return;
            FacePreviewPlaceholder.Visibility = Visibility.Collapsed;
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception) when (!token.IsCancellationRequested)
        {
            FacePreviewPlaceholder.Visibility = Visibility.Visible;
        }

        _ = loopTask.ContinueWith(
            task =>
            {
                _ = task.Exception;
            },
            CancellationToken.None,
            TaskContinuationOptions.OnlyOnFaulted,
            TaskScheduler.Default);
    }

    private Task StopPreviewAsync()
    {
        if (!previewStopTask.IsCompleted) return previewStopTask;
        return previewStopTask = StopPreviewCoreAsync();
    }

    private async Task StopPreviewCoreAsync()
    {
        var cancellation = previewLoopCancellation;
        var previewTask = previewLoopTask;
        var recorder = previewRecorder;
        previewLoopCancellation = null;
        previewLoopTask = null;
        previewRecorder = null;
        cancellation?.Cancel();
        if (previewTask is not null)
        {
            try
            {
                await previewTask;
            }
            catch (Exception)
            {
                System.Diagnostics.Debug.WriteLine("Ping preview loop stopped after failure.");
            }
        }

        cancellation?.Dispose();
        try
        {
            if (recorder is not null) await recorder.StopPreviewAsync(FacePreviewElement);
        }
        catch (Exception)
        {
        }
    }

    private void HandleClosed(object sender, WindowEventArgs args)
    {
        inputShutdown = ViewportInput.StopAsync();
        mirrorHost?.Dispose();
        Root.Loaded -= HandleLoaded;
        viewModel.PropertyChanged -= HandleViewModelPropertyChanged;
        viewModel.FadeOutRequested -= HandleFadeOutRequested;
        viewModel.CloseRequested -= HandleCloseRequested;
        windowLifetime.Cancel();
        recordingPreviewShutdown = recordingPreview.StopAsync();
        StopReviewPlayback();
        viewModel.HandleWindowClosed();
        CameraShutdown = ShutdownCameraAsync();
    }

    private async Task ShutdownCameraAsync()
    {
        try
        {
            await inputShutdown;
            await recordingPreviewShutdown;
            try { await StopPreviewAsync(); }
            finally { await viewModel.WaitForOperationAsync(); }
            viewModel.DisposePreview();
        }
        finally { cameraLease.Dispose(); windowLifetime.Dispose(); }
    }

    private void UpdateReviewPlayback()
    {
        if (viewModel.ReviewVideoUri is not { } uri
            || viewModel.State is not (MirrorState.Reviewing or MirrorState.Failed))
        {
            StopReviewPlayback();
            ReviewElement.Visibility = Visibility.Collapsed;
            FacePreviewBubble.Visibility = Visibility.Visible;
            if (viewModel.ScreenPreviewUri is null)
            {
                ScreenPreviewPlaceholder.Visibility = Visibility.Visible;
            }

            return;
        }

        ScreenPreviewPlaceholder.Visibility = Visibility.Collapsed;
        FacePreviewBubble.Visibility = Visibility.Collapsed;
        ReviewElement.Visibility = Visibility.Visible;
        StopReviewPlayback();
        reviewPlayer = new MediaPlayer
        {
            AutoPlay = false,
            IsMuted = true,
            Source = MediaSource.CreateFromUri(uri)
        };
        reviewPlayer.MediaEnded += HandleReviewMediaEnded;
        ReviewElement.SetMediaPlayer(reviewPlayer);
        reviewPlayer.Play();
    }

    private void StopReviewPlayback()
    {
        ReviewElement.SetMediaPlayer(null);
        if (reviewPlayer is null)
        {
            return;
        }

        reviewPlayer.MediaEnded -= HandleReviewMediaEnded;
        reviewPlayer.Dispose();
        reviewPlayer = null;
    }

    private static void HandleReviewMediaEnded(MediaPlayer sender, object args)
    {
        sender.PlaybackSession.Position = TimeSpan.Zero;
        sender.Play();
    }

    private void SetStateBrush()
    {
        var key = viewModel.State switch
        {
            MirrorState.Idle when viewModel.IsAllTargetsSelected => "PingRainbowBorderBrush",
            MirrorState.Reviewing when viewModel.IsAllTargetsSelected => "PingRainbowBorderBrush",
            MirrorState.Idle => "PingBorderIdleBrush",
            MirrorState.Reviewing => "PingBorderIdleBrush",
            MirrorState.Recording => "PingBorderRecordingBrush",
            MirrorState.Uploading => "PingRainbowBorderBrush",
            MirrorState.Failed => "PingBorderFailedBrush",
            _ => "PingBorderIdleBrush"
        };

        var thickness = (viewModel.State is MirrorState.Idle or MirrorState.Reviewing) && !viewModel.IsAllTargetsSelected ? 1 : 2;
        MirrorBorder.BorderBrush = Root.Resources[key] as Brush;
        MirrorBorder.BorderThickness = new Thickness(thickness);
    }
}
#endif
