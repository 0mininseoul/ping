#if PING_UI_SMOKE
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Ping.Windows.App.Capture;
using Ping.Windows.App.Onboarding;
using Ping.Windows.App.Hotkeys;
using Ping.Windows.App.Setup;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using global::Windows.Graphics.Imaging;
using global::Windows.Storage;

namespace Ping.Windows.App.Diagnostics;

// Screenshot delivery only: no account bootstrap, permission probes, camera or test suite.
internal static class AccountKeyPreview
{
    internal static string? OutputDirectory { get; set; }

    internal static async Task RunAsync(App app)
    {
        Directory.CreateDirectory(OutputDirectory!);
        GuidedSetupWindow? window = null;
        SettingsWindow? settingsWindow = null;
        try
        {
            var model = new GuidedSetupViewModel(new(
                (name, _) => Task.FromResult(name), (_, _, _) => Task.CompletedTask,
                (_, _) => Task.FromResult<IReadOnlyList<Room>>([]), (_, _, _) => Task.CompletedTask,
                () => "screenshot-preview"));
            await model.NextAsync(); await model.NextAsync();
            model.Nickname = "민지";
            window = new(model, () => { }, _ => Task.FromResult(OnboardingEnvironmentState.Ready()));
            window.Activate();
            var root = (FrameworkElement)window.Content;
            root.RequestedTheme = ElementTheme.Light;
            await Task.Delay(400);
            await CaptureAsync(root, "onboarding-nickname-light.png");
            root.RequestedTheme = ElementTheme.Dark;
            await Task.Delay(200);
            await CaptureAsync(root, "onboarding-nickname-dark.png");
            root.RequestedTheme = ElementTheme.Light;
            await Task.Delay(200);
            var displayDialog = AccountKeyDialogs.ConnectAsync(root, CancellationToken.None);
            ContentDialog? dialog = null;
            for (var attempt = 0; attempt < 40 && dialog is null; attempt++)
            {
                dialog = VisualTreeHelper.GetOpenPopupsForXamlRoot(root.XamlRoot)
                    .SelectMany(popup => Descendants(popup.Child)).OfType<ContentDialog>().FirstOrDefault();
                if (dialog is null) await Task.Delay(50);
            }
            if (dialog is null) throw new InvalidOperationException("The screenshot dialog did not open.");
            await Task.Delay(250);
            await CaptureDialogAsync(dialog, "existing-account-dialog.png");
            dialog.Hide();
            await displayDialog;
            bool keyEnabled = false;
            var settingsModel = new SettingsWindowViewModel("민지", HotkeyBinding.Defaults(), ScreenFaceQuickSendSettings.Default,
                _ => { }, () => { }, new PreviewStartup(), archiveRootPath: OutputDirectory,
                ensureArchiveFolders: () => { }, deleteExpiredArchiveFiles: () => { }, openArchiveFolder: _ => Task.FromResult(false),
                loadAccounts: _ => Task.FromResult<IReadOnlyList<StoredAccountSummary>>([new("preview", "민지", DateTimeOffset.UtcNow, true)]),
                changeAccount: (_, _) => throw new NotSupportedException("Screenshot preview only"),
                updates: new UpdateSettingsViewModel("미리보기", _ => Task.FromResult<Ping.Windows.Core.Updates.WindowsUpdateCandidate?>(null),
                    (_, _, _) => Task.CompletedTask),
                loadAccountKey: _ => Task.FromResult(keyEnabled), saveAccountKey: (_, _) => Task.CompletedTask);
            settingsWindow = new(settingsModel);
            settingsWindow.Activate();
            var settingsRoot = (Grid)settingsWindow.Content;
            settingsRoot.RequestedTheme = ElementTheme.Light;
            await Task.Delay(300);
            ((ScrollViewer)settingsRoot.FindName("GeneralScroll")).ChangeView(null, double.MaxValue, null, disableAnimation: true);
            await Task.Delay(200);
            await CaptureAsync(settingsRoot, "settings-account-key.png");
            await CaptureKeyDialogAsync(settingsRoot, settingsModel, "account-key-create-dialog.png");
            keyEnabled = true;
            await settingsModel.AccountKey.RefreshAsync(CancellationToken.None);
            await CaptureKeyDialogAsync(settingsRoot, settingsModel, "account-key-change-dialog.png");
            File.WriteAllText(Path.Combine(OutputDirectory!, "capture-complete.txt"), "Native WinUI screenshots; no authentication or backend requests.");
        }
        catch (Exception error) { File.WriteAllText(Path.Combine(OutputDirectory!, "capture-error.txt"), error.ToString()); }
        finally { settingsWindow?.Close(); window?.Close(); app.Exit(); }
    }

    private static async Task CaptureKeyDialogAsync(FrameworkElement root, SettingsWindowViewModel model, string name)
    {
        var display = AccountKeyDialogs.SetKeyAsync(root, model.Nickname, model.AccountKey, CancellationToken.None);
        ContentDialog? dialog = null;
        for (var attempt = 0; attempt < 40 && dialog is null; attempt++)
        {
            dialog = VisualTreeHelper.GetOpenPopupsForXamlRoot(root.XamlRoot)
                .SelectMany(popup => Descendants(popup.Child)).OfType<ContentDialog>().FirstOrDefault();
            if (dialog is null) await Task.Delay(50);
        }
        if (dialog is null) throw new InvalidOperationException("The key screenshot dialog did not open.");
        await Task.Delay(250);
        await CaptureDialogAsync(dialog, name);
        dialog.Hide(); await display;
    }

    private sealed class PreviewStartup : IStartupTaskController
    {
        public Task<PingStartupTaskStatus> GetStatusAsync(CancellationToken token = default)
            => Task.FromResult(new PingStartupTaskStatus(PingStartupTaskState.Disabled, "미리보기"));
        public Task<PingStartupTaskStatus> SetEnabledAsync(bool enabled, CancellationToken token = default) => GetStatusAsync(token);
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        yield return root;
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
            foreach (var child in Descendants(VisualTreeHelper.GetChild(root, index))) yield return child;
    }

    private static Task CaptureDialogAsync(ContentDialog dialog, string name) => CaptureAsync(
        Descendants(dialog).OfType<FrameworkElement>().FirstOrDefault(element => element.Name == "BackgroundElement") ?? dialog, name);

    private static async Task CaptureAsync(FrameworkElement root, string name)
    {
        root.UpdateLayout();
        var bitmap = new RenderTargetBitmap();
        await bitmap.RenderAsync(root);
        var pixels = (await bitmap.GetPixelsAsync()).ToArray();
        var path = Path.Combine(OutputDirectory!, name);
        File.WriteAllBytes(path, []);
        var file = await StorageFile.GetFileFromPathAsync(path);
        using var stream = await file.OpenAsync(FileAccessMode.ReadWrite);
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied,
            (uint)bitmap.PixelWidth, (uint)bitmap.PixelHeight, 96, 96, pixels);
        await encoder.FlushAsync();
    }
}
#endif
