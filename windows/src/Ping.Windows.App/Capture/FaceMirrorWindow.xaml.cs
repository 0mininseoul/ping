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
using Windows.Graphics;
using Windows.Media.Core;
using Windows.Media.Playback;

namespace Ping.Windows.App.Capture;

public sealed partial class FaceMirrorWindow : Window
{
    private readonly FaceMirrorViewModel viewModel;
    private readonly FaceRecorder? previewRecorder;
    private readonly Ping.Windows.Core.Capture.CameraLease cameraLease;
    private readonly CancellationTokenSource windowLifetime = new();
    public Task CameraShutdown { get; private set; } = Task.CompletedTask;
    private MediaPlayer? reviewPlayer;
    private CaptureMirrorWindowHost? mirrorHost;
    private bool shouldCloseAfterFade;

    public FaceMirrorWindow(FaceMirrorViewModel viewModel, Ping.Windows.Core.Capture.CameraLease cameraLease)
    {
        this.viewModel = viewModel;
        this.cameraLease = cameraLease;
        previewRecorder = viewModel.Recorder as FaceRecorder;
        InitializeComponent();
        Ping.Windows.App.UI.PingAppearance.Register(this);
        Root.DataContext = viewModel;
        Root.Loaded += HandleLoaded;
        viewModel.PropertyChanged += HandleViewModelPropertyChanged;
        viewModel.FadeOutRequested += HandleFadeOutRequested;
        viewModel.CloseRequested += HandleCloseRequested;
        SetStateBrush();
        ConfigureWindow();
    }

    private async void HandleKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (HandleTargetKey(args.Key))
        {
            args.Handled = true;
            return;
        }

        if (args.Key == global::Windows.System.VirtualKey.Enter)
        {
            args.Handled = true;
            await viewModel.HandleEnterAsync();
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

    internal Task HandleRedoAsync() => viewModel.HandleRedoAsync();

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

    private void HandleViewModelPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName == nameof(FaceMirrorViewModel.State)
            || args.PropertyName == nameof(FaceMirrorViewModel.IsAllTargetsSelected))
        {
            SetStateBrush();
        }

        if (args.PropertyName == nameof(FaceMirrorViewModel.State)
            || args.PropertyName == nameof(FaceMirrorViewModel.ReviewVideoUri))
        {
            UpdateReviewPlayback();
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
        mirrorHost = new(this, Root, CaptureMode.FaceOnly, viewModel.PreferredMirrorPosition,
            (bounds, display, save) => viewModel.UpdateMirrorPlacement(bounds, display.Display, display.WorkArea, save),
            (width, height) =>
            {
                MirrorBorder.CornerRadius = new(width / 2);
                HintLabel.MaxWidth = Math.Max(20, width - 88);
                PartnerLabelElement.MaxWidth = Math.Max(20, width - 48);
            }, PartnerChip);
    }
    private async void HandleLoaded(object sender, RoutedEventArgs args)
    {
        if (windowLifetime.IsCancellationRequested) return;
        Root.Focus(FocusState.Programmatic);
        mirrorHost?.Refresh();
        if (previewRecorder is null)
        {
            return;
        }

        try
        {
            await previewRecorder.StartPreviewAsync(PreviewElement, windowLifetime.Token);
            if (windowLifetime.IsCancellationRequested) return;
            PreviewPlaceholder.Visibility = Visibility.Collapsed;
            UpdateReviewPlayback();
        }
        catch (Exception)
        {
            PreviewPlaceholder.Visibility = Visibility.Visible;
        }
    }

    private void HandleClosed(object sender, WindowEventArgs args)
    {
        mirrorHost?.Dispose();
        Root.Loaded -= HandleLoaded;
        viewModel.PropertyChanged -= HandleViewModelPropertyChanged;
        viewModel.FadeOutRequested -= HandleFadeOutRequested;
        viewModel.CloseRequested -= HandleCloseRequested;
        windowLifetime.Cancel();
        StopReviewPlayback();
        viewModel.HandleWindowClosed();
        CameraShutdown = ShutdownCameraAsync();
    }

    private async Task ShutdownCameraAsync()
    {
        try
        {
            try { if (previewRecorder is not null) await previewRecorder.StopPreviewAsync(PreviewElement); }
            finally { await viewModel.WaitForOperationAsync(); }
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
            PreviewElement.Visibility = Visibility.Visible;
            return;
        }

        PreviewElement.Visibility = Visibility.Collapsed;
        PreviewPlaceholder.Visibility = Visibility.Collapsed;
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
