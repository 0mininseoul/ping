#if PING_UI_SMOKE
using System.Runtime.InteropServices.WindowsRuntime;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Ping.Windows.App.Capture;
using Ping.Windows.App.History;
using Ping.Windows.App.Hotkeys;
using Ping.Windows.App.Setup;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using global::Windows.Graphics.Imaging;
using global::Windows.Storage;

namespace Ping.Windows.App.Diagnostics;

internal static partial class UiSmokeRunner
{
    public static string? OutputDirectory { get; set; }
    public static bool ConversationOnly { get; set; }
    private static readonly List<string> Checks = [];
    private static bool failureWritten;
    private static void Step(string text) => File.AppendAllText(Path.Combine(OutputDirectory!, "phases.txt"), text + Environment.NewLine);
    private static void Check(bool condition, string label)
    {
        if (!condition) throw new InvalidOperationException(label);
        Checks.Add(label);
        Step("PASS " + label);
    }

    public static async Task RunAsync(App app)
    {
        Directory.CreateDirectory(OutputDirectory!);
        app.UnhandledException += (_, args) =>
        {
            WriteFailure(args.Exception);
            args.Handled = true;
            app.Exit();
        };
        MainWindow? window = null;
        try
        {
            if (ConversationOnly)
            {
                await VerifyConversationTextAsync();
                File.WriteAllText(Path.Combine(OutputDirectory!, "result.json"), JsonSerializer.Serialize(new { Success = true, Checks }));
                app.Exit();
                return;
            }
            Step("Creating isolated fixture services — no production backend, user files, tray or camera. Pairing uses owned files and fake HTTP only.");
            var rpc = new FixtureRpc();
            var storage = new FixtureStorage();
            var vm = new HistoryViewModel(new RoomService(rpc), new MessageService(rpc, storage), new ChatMessageService(rpc),
                new ReactionService(rpc), storage, () => "me", new FixtureLinks(), _ => rpc.AllowRead);
            window = new MainWindow();
            window.InitializeTrayWindowBehavior();
            TestDisplayPlacement.Verify(window, Check);
            var shell = new HistoryWindow(window, vm, (_, _) => throw new NotSupportedException("No camera/video fixture"),
                (_, _) => Task.CompletedTask, new MessageService(rpc, storage), loadOnStart: false, refreshInterval: TimeSpan.FromSeconds(5),
                roomServices: new(new(rpc), new(rpc), new(rpc), () => "me", () => "민", () => { }));
            window.AttachMessenger(shell);
            shell.SetDefaultRoom("디자인 이야기");
            window.ShowShell();
            Step("Main messenger created.");
            await shell.ReloadRoomsAsync();
            await Task.Delay(350);
            var root = (FrameworkElement)window.Content;
            TypographySmoke.Verify(root, Check);
            await VerifyConversationTextAsync();
            await VerifyChatImagePreviewAsync();
            await VerifyImageInputAsync();
            await VerifyInlineFaceAsync();
            Check(root.ActualWidth > 600 && root.ActualHeight > 500, "real compact main window has usable client area");
            Check(UI.WindowCaptureExclusion.IsApplied(window), "messenger declares exclusion from OS screen capture");
            Check(vm.Rooms.Count == 2 && vm.Timeline.Count == 4, "fixture rooms and mixed timeline loaded");
            Check(window.Content is ContentControl { Content: HistoryWindow }, "single main window hosts messenger control");
            var timelineScroll = Descendants((ListView)shell.FindName("VideosList")).OfType<ScrollViewer>().First();
            Step($"Initial timeline: offset={timelineScroll.VerticalOffset}, scrollable={timelineScroll.ScrollableHeight}, viewport={timelineScroll.ViewportHeight}");
            Check(timelineScroll.ScrollableHeight == 0 || timelineScroll.VerticalOffset >= timelineScroll.ScrollableHeight - 2,
                "opening a room shows its newest message");
            shell.RequestedTheme = ElementTheme.Light;
            await Task.Delay(180);
            await RenderAsync(root, "messenger-light.png");
            var bubbles = Descendants(root).OfType<UI.MessageBubble>().ToArray();
            Check(bubbles.Any(b => b.IsMine) && bubbles.Any(b => !b.IsMine)
                && bubbles.All(b => b.Background == (b.IsMine ? b.SentFill : b.ReceivedFill)
                    && b.Foreground == (b.IsMine ? b.SentText : b.ReceivedText)),
                "actual sent and received message bubbles use distinct Mac-style fills and text");
            shell.RequestedTheme = ElementTheme.Dark;
            await Task.Delay(180);
            await RenderAsync(root, "messenger-dark.png");
            var roomVm = new RoomManagerViewModel(new RoomService(rpc), new InvitationService(rpc), "민");
            var manager = new RoomManagerWindow(roomVm);
            try
            {
                await manager.FocusRoomAsync("b");
                manager.Activate();
                TestDisplayPlacement.Verify(manager, Check);
                await UntilAsync(() => roomVm.Rooms.Count == 2);
                Check(roomVm.SelectedRoom?.Id == "b", "invitation launcher focuses requested room after asynchronous load");
                await manager.FocusRoomAsync("a");
                roomVm.Rooms.Remove(roomVm.Rooms.Single(room => room.Id == "b"));
                await manager.FocusRoomAsync("b");
                Check(roomVm.SelectedRoom?.Id == "b", "already-open invitation manager reloads absent target instead of keeping another room");
                await manager.FocusRoomAsync("a");
                var managerRoot = (FrameworkElement)manager.Content;
                managerRoot.RequestedTheme = ElementTheme.Light;
                await Task.Delay(180);
                var managementTabs = Descendants(managerRoot).OfType<Pivot>().Single();
                Check(managementTabs.Items.Count == 3 && managementTabs.SelectedIndex == 0,
                    "room management presents one task at a time instead of the legacy form wall");
                Check(!Descendants(managerRoot).OfType<TextBox>().Any(t =>
                    t.Name is "NewRoomNameBox" or "RenameRoomBox" && t.ActualHeight > 0),
                    "room overview hides creation and rename forms until requested");
                await UntilAsync(() => Descendants(managerRoot).OfType<TextBlock>().Any(t => t.Text == "서연"));
                Check(Descendants(managerRoot).OfType<TextBlock>().Any(t => t.Text == "민"),
                    "room overview renders the actual selected room member nicknames");
                await RenderAsync(managerRoot, "rooms-management.png");
                var newRoomButton = (Button)managerRoot.FindName("NewRoomButton");
                ((IInvokeProvider)new ButtonAutomationPeer(newRoomButton).GetPattern(PatternInterface.Invoke)).Invoke();
                ContentDialog? roomDialog = null;
                await UntilAsync(() => (roomDialog = VisualTreeHelper.GetOpenPopupsForXamlRoot(managerRoot.XamlRoot)
                    .SelectMany(p => Descendants(p.Child).Append(p.Child)).OfType<ContentDialog>().FirstOrDefault()) is not null);
                var roomInput = Descendants(roomDialog!).OfType<TextBox>().Single();
                await RenderAsync(roomDialog!, "rooms-create-dialog.png");
                roomInput.Text = new string('가', 17);
                await InvokeDialogButtonAsync(managerRoot.XamlRoot, "만들기");
                Check(rpc.CreateAttempts == 0 && roomInput.Text.Length == 17,
                    "overlong room name stays editable without calling the backend");
                roomInput.Text = "함께 이야기";
                await InvokeDialogButtonAsync(managerRoot.XamlRoot, "만들기");
                Check(rpc.CreateAttempts == 1 && roomInput.Text == "함께 이야기" && roomInput.IsEnabled
                    && Descendants(roomDialog!).OfType<TextBlock>().Any(t => t.Text == "테스트 연결 실패"),
                    "failed room creation keeps dialog, input and retry controls");
                roomInput.Text = string.Concat(Enumerable.Repeat("🇰🇷", 13));
                await InvokeDialogButtonAsync(managerRoot.XamlRoot, "만들기");
                Check(rpc.CreateAttempts == 2, "13 flag emoji room name reaches the service as 13 graphemes");
                await InvokeDialogButtonAsync(managerRoot.XamlRoot, "취소");
                await Task.Delay(180);
                var renameRoomButton = (Button)managerRoot.FindName("RenameRoomButton");
                ((IInvokeProvider)new ButtonAutomationPeer(renameRoomButton).GetPattern(PatternInterface.Invoke)).Invoke();
                await UntilAsync(() => (roomDialog = VisualTreeHelper.GetOpenPopupsForXamlRoot(managerRoot.XamlRoot)
                    .SelectMany(p => Descendants(p.Child).Append(p.Child)).OfType<ContentDialog>().FirstOrDefault()) is not null);
                await UntilAsync(() => Descendants(roomDialog!).OfType<TextBox>().Count() == 1);
                roomInput = Descendants(roomDialog!).OfType<TextBox>().Single();
                Check(roomInput.Text == roomVm.SelectedRoomName, "rename dialog starts with the selected room name");
                roomInput.Text = "함께 이야기";
                await InvokeDialogButtonAsync(managerRoot.XamlRoot, "저장");
                Check(rpc.LastRename is { RoomUuid: "a", NewName: "함께 이야기" },
                    "native rename dialog submits to the selected room service");
                await Task.Delay(180);
                ((IInvokeProvider)new ButtonAutomationPeer(renameRoomButton).GetPattern(PatternInterface.Invoke)).Invoke();
                await UntilAsync(() => (roomDialog = VisualTreeHelper.GetOpenPopupsForXamlRoot(managerRoot.XamlRoot)
                    .SelectMany(p => Descendants(p.Child).Append(p.Child)).OfType<ContentDialog>().FirstOrDefault()) is not null);
                await UntilAsync(() => Descendants(roomDialog!).OfType<TextBox>().Count() == 1);
                roomInput = Descendants(roomDialog!).OfType<TextBox>().Single();
                roomInput.Text = "바뀌면 안 되는 이름";
                await manager.FocusRoomAsync("b");
                await InvokeDialogButtonAsync(managerRoot.XamlRoot, "저장");
                Check(rpc.LastRename is { RoomUuid: "a", NewName: "함께 이야기" }
                    && Descendants(roomDialog!).OfType<TextBlock>().Any(t => t.Text.Contains("바뀌었어요", StringComparison.Ordinal)),
                    "rename never submits to another room selected while its dialog is open");
                await InvokeDialogButtonAsync(managerRoot.XamlRoot, "취소");
                await manager.FocusRoomAsync("a");
                ((IInvokeProvider)new ButtonAutomationPeer((Button)managerRoot.FindName("LeaveRoomButton")).GetPattern(PatternInterface.Invoke)).Invoke();
                await UntilAsync(() => VisualTreeHelper.GetOpenPopupsForXamlRoot(managerRoot.XamlRoot).Count > 0);
                await manager.FocusRoomAsync("b");
                await InvokeDialogButtonAsync(managerRoot.XamlRoot, "나가기");
                Check(rpc.LeaveAttempts == 0, "leave confirmation never removes a room selected after the dialog opened");
                await manager.FocusRoomAsync("a");
                var targetRow = Descendants(managerRoot).OfType<Grid>().Single(g => g.ContextFlyout is MenuFlyout && g.DataContext is Room { Id: "b" });
                ((MenuFlyout)targetRow.ContextFlyout).ShowAt(targetRow);
                MenuFlyoutItem? moveItem = null;
                await UntilAsync(() => (moveItem = VisualTreeHelper.GetOpenPopupsForXamlRoot(managerRoot.XamlRoot)
                    .SelectMany(p => Descendants(p.Child)).OfType<MenuFlyoutItem>().FirstOrDefault(i => i.Text == "위로 이동")) is not null);
                ((IInvokeProvider)new MenuFlyoutItemAutomationPeer(moveItem!).GetPattern(PatternInterface.Invoke)).Invoke();
                await UntilAsync(() => roomVm.Rooms[0].Id == "b");
                Check(roomVm.SelectedRoom?.Id == "b", "context reorder moves the clicked row even when another room was selected");
                managementTabs.SelectedIndex = 1;
                await Task.Delay(800);
                Check(Descendants(managerRoot).OfType<TextBox>().Any(t => t.Name == "SearchBox" && t.ActualWidth > 100),
                    "room search tab exposes its actual bound search control");
                await RenderAsync(managerRoot, "rooms-search.png");
                managementTabs.SelectedIndex = 2;
                await Task.Delay(800);
                Check(Descendants(managerRoot).OfType<TextBox>().Any(t => t.Name == "UserSearchBox" && t.ActualWidth > 100),
                    "invitation tab exposes nickname search without raw user identity entry");
                await RenderAsync(managerRoot, "rooms-invitations.png");
            }
            finally { manager.Close(); window.ShowShell(); }

            var chatBox = (TextBox)shell.FindName("ChatBox");
            var roomsList = (ListView)shell.FindName("RoomsList");
            chatBox.Text = "보존할 초안 A";
            await Task.Delay(50);
            Check(vm.DraftText == chatBox.Text, "text binding updates real composer state");
            roomsList.SelectedItem = vm.Rooms.Single(room => room.Id == "b");
            await Task.Delay(150);
            Check(vm.SelectedRoom?.Id == "b" && vm.Timeline.Count == 0, "real room selection switches to empty room");
            Check(((FrameworkElement)shell.FindName("EmptyState")).Visibility == Visibility.Visible
                && ((FrameworkElement)shell.FindName("VideosList")).Visibility == Visibility.Collapsed, "empty room CTA is not covered by timeline");
            chatBox.Text = "새 초안 B";
            roomsList.SelectedItem = vm.Rooms.Single(room => room.Id == "a");
            await Task.Delay(150);
            Check(chatBox.Text == "보존할 초안 A", "real binding restores room A draft after switching back");

            var timeline = (ListView)shell.FindName("VideosList");
            var chatRow = vm.Timeline.Last(row => row.Chat is not null);
            timeline.ScrollIntoView(chatRow);
            await Task.Delay(150);
            var menuOwner = Descendants(timeline).OfType<StackPanel>()
                .First(panel => ReferenceEquals(panel.DataContext, chatRow) && panel.Visibility == Visibility.Visible && panel.ContextFlyout is MenuFlyout);
            var menu = (MenuFlyout)menuOwner.ContextFlyout;
            menu.ShowAt(menuOwner);
            await Task.Delay(100);
            var reply = menu.Items.OfType<MenuFlyoutItem>().Single(item => item.Text == "답장");
            Check(ReferenceEquals(reply.DataContext, chatRow), "context flyout keeps actual message identity");
            ((IInvokeProvider)new MenuFlyoutItemAutomationPeer(reply).GetPattern(PatternInterface.Invoke)).Invoke();
            await Task.Delay(100);
            Check(vm.ReplyTarget?.ChatId == chatRow.Chat!.Message.Id, "context reply invokes real event handler");
            menu.Hide();

            chatBox.Text = "스모크 전송";
            var sendButton = (Button)shell.FindName("SendButton");
            Check(sendButton.IsEnabled, "nonempty bound draft enables actual send button");
            ((IInvokeProvider)new ButtonAutomationPeer(sendButton).GetPattern(PatternInterface.Invoke)).Invoke();
            await UntilAsync(() => rpc.Sent == 1 && !vm.IsSending);
            Check(chatBox.Text == "" && vm.ReplyTarget is null && rpc.Sent == 1, "successful send updates visible composer without duplicate RPC");
            await UntilAsync(() => timelineScroll.VerticalOffset >= timelineScroll.ScrollableHeight - 2);
            Check(timelineScroll.VerticalOffset >= timelineScroll.ScrollableHeight - 2, "sending keeps the newest message visible");
            var readingOffset = Math.Min(35, timelineScroll.ScrollableHeight);
            timelineScroll.ChangeView(null, readingOffset, null, true);
            await Task.Delay(80);
            await shell.RefreshNowAsync();
            await Task.Delay(120);
            Check(Math.Abs(timelineScroll.VerticalOffset - readingOffset) < 2, "refresh preserves a scrolled conversation viewport");
            Check(Descendants(roomsList).OfType<TextBlock>().Count(text => text.Text == "2명") == 2, "room member counts are visible in actual bindings");

            window.ReportStatus("오프라인입니다. 다시 연결하는 중…", true);
            await RenderAsync(root, "messenger-offline.png");
            Check(((FrameworkElement)shell.FindName("RetryButton")).Visibility == Visibility.Visible, "connection failure preserves conversation and exposes retry");
            window.ReportStatus(null);

            Step("Creating real secondary settings window.");
            shell.RequestedTheme = ElementTheme.Default;
            ScreenFaceQuickSendSettings? savedSettings = null;
            var fixtureMicrophone = new Ping.Windows.Core.Capture.CaptureMicrophoneDevice("fixture-winrt-mic", "fixture-endpoint-mic");
            var fixtureDevices = new CaptureDeviceCatalog([new("fixture-camera", "Fixture camera")], [new(fixtureMicrophone, "Fixture microphone")]);
            IReadOnlyList<StoredAccountSummary> fixtureAccounts = [new("me", "민", DateTimeOffset.UtcNow, true), new("second", "둘째", DateTimeOffset.UtcNow, false)];
            var accountChanges = 0;
            var updateCheckFails = true; var updateInstalls = 0;
            var fixtureUpdates = new UpdateSettingsViewModel("0.3.46.0", _ => updateCheckFails ? throw new IOException("fixture-only")
                : Task.FromResult<Ping.Windows.Core.Updates.WindowsUpdateCandidate?>(new(new(0, 3, 80, 0), "x64",
                    new("https://0minping.vercel.app/downloads/windows/Ping-Windows-v0.3.80-x64.msix"))),
                (_, _, _) => { updateInstalls++; return Task.CompletedTask; });
            var settingsVm = new SettingsWindowViewModel("민", HotkeyBinding.Defaults(), ScreenFaceQuickSendSettings.Default,
                value => { savedSettings = value; UI.PingAppearance.Apply(value.AppearanceMode); }, () => { }, new FixtureStartup(), archiveRootPath: OutputDirectory,
                ensureArchiveFolders: () => { }, deleteExpiredArchiveFiles: () => { }, openArchiveFolder: _ => Task.FromResult(false),
                deviceCatalog: _ => Task.FromResult(fixtureDevices),
                pairingGenerator: token => DevicePairingSmoke.CreateAsync(OutputDirectory!, token), pairingUid: () => "me",
                loadAccounts: _ => Task.FromResult(fixtureAccounts),
                changeAccount: (change, _) =>
                {
                    accountChanges++;
                    if (change.Kind == AccountChangeKind.Switch)
                        fixtureAccounts = fixtureAccounts.Select(row => row with { IsActive = row.UserId == change.UserId }).ToArray();
                    else if (change.Kind == AccountChangeKind.Create)
                        fixtureAccounts = fixtureAccounts.Select(row => row with { IsActive = false }).Append(new("created", "새 계정", DateTimeOffset.UtcNow, true)).ToArray();
                    else fixtureAccounts = fixtureAccounts.Where(row => row.UserId != change.UserId).ToArray();
                    return Task.CompletedTask;
                }, updates: fixtureUpdates);
            var settings = new SettingsWindow(settingsVm);
            TestDisplayPlacement.Verify(settings, Check);
            settings.Activate();
            Check(UI.WindowCaptureExclusion.IsApplied(settings), "settings declares exclusion from OS screen capture");
            await Task.Delay(250);
            var autoPlayToggle = (ToggleSwitch)((Grid)settings.Content).FindName("AutoPlayIncomingToggle");
            Check(autoPlayToggle.IsOn, "real autoplay control defaults on");
            autoPlayToggle.IsOn = false;
            await Task.Delay(50);
            Check(savedSettings is { AutoPlayIncoming: false } && !settingsVm.AutoPlayIncoming, "real autoplay binding persists off");
            var settingsRoot = (Grid)settings.Content;
            var accountCombo = (ComboBox)settingsRoot.FindName("AccountsComboBox");
            var switchAccount = (Button)settingsRoot.FindName("SwitchAccountButton");
            await UntilAsync(() => accountCombo.IsLoaded && accountCombo.Items.Count == 2 && !settingsVm.Accounts.IsBusy);
            Check(!switchAccount.IsEnabled && ((AccountSettingRow)accountCombo.SelectedItem).UserId == "me", "actual account list selects active identity and disables redundant switch");
            accountCombo.SelectedIndex = 1;
            await Task.Delay(60);
            Check(switchAccount.IsEnabled && settingsVm.Accounts.SelectedAccount?.UserId == "second", "account selection binding enables explicit switch");
            ((IInvokeProvider)new ButtonAutomationPeer(switchAccount).GetPattern(PatternInterface.Invoke)).Invoke();
            await UntilAsync(() => accountChanges == 1 && !settingsVm.Accounts.IsBusy);
            Check(settingsVm.Accounts.Accounts.Single(row => row.IsActive).UserId == "second", "real switch handler changes selected fixture identity");
            var createAccount = (Button)settingsRoot.FindName("CreateAccountButton");
            ((IInvokeProvider)new ButtonAutomationPeer(createAccount).GetPattern(PatternInterface.Invoke)).Invoke();
            await InvokeDialogButtonAsync(settingsRoot.XamlRoot, "취소");
            Check(accountChanges == 1 && fixtureAccounts.Count == 2, "cancelling new-account confirmation preserves existing identities");
            ((IInvokeProvider)new ButtonAutomationPeer(createAccount).GetPattern(PatternInterface.Invoke)).Invoke();
            await InvokeDialogButtonAsync(settingsRoot.XamlRoot, "추가");
            await UntilAsync(() => accountChanges == 2 && accountCombo.Items.Count == 3 && !settingsVm.Accounts.IsBusy);
            Check(settingsVm.Accounts.Accounts.Single(row => row.IsActive).UserId == "created", "confirmed new-account handler adds fixture identity");
            var removeAccount = (Button)settingsRoot.FindName("RemoveAccountButton");
            ((IInvokeProvider)new ButtonAutomationPeer(removeAccount).GetPattern(PatternInterface.Invoke)).Invoke();
            await InvokeDialogButtonAsync(settingsRoot.XamlRoot, "취소");
            Check(accountChanges == 2 && fixtureAccounts.Count == 3, "cancelling local account deletion preserves identity");
            ((IInvokeProvider)new ButtonAutomationPeer(removeAccount).GetPattern(PatternInterface.Invoke)).Invoke();
            await InvokeDialogButtonAsync(settingsRoot.XamlRoot, "삭제");
            await UntilAsync(() => accountChanges == 3 && accountCombo.Items.Count == 2 && !settingsVm.Accounts.IsBusy);
            Check(fixtureAccounts.All(row => row.UserId != "created"), "confirmed deletion invokes selected identity removal");
            await RenderAsync(settingsRoot, "settings-accounts.png");
            var infoTabs = (TabView)settingsRoot.FindName("SettingsTabs");
            infoTabs.SelectedIndex = (int)SettingsSection.Info;
            await UntilAsync(() => (settingsRoot.FindName("CheckUpdateButton") as Button)?.IsLoaded == true);
            var updateCheck = (Button)settingsRoot.FindName("CheckUpdateButton");
            var updateInstall = (Button)settingsRoot.FindName("InstallUpdateButton");
            await UntilAsync(() => updateCheck.IsLoaded);
            Check(((TextBlock)settingsRoot.FindName("InstalledVersionText")).Text == "0.3.46.0", "info tab binds current Windows package version");
            ((IInvokeProvider)new ButtonAutomationPeer(updateCheck).GetPattern(PatternInterface.Invoke)).Invoke();
            await UntilAsync(() => !fixtureUpdates.IsBusy && fixtureUpdates.Status.Contains("다시"));
            Check(!updateInstall.IsEnabled && updateCheck.IsEnabled, "failed update check exposes retry and prevents installation");
            updateCheckFails = false;
            ((IInvokeProvider)new ButtonAutomationPeer(updateCheck).GetPattern(PatternInterface.Invoke)).Invoke();
            await UntilAsync(() => updateInstall.IsEnabled);
            ((IInvokeProvider)new ButtonAutomationPeer(updateInstall).GetPattern(PatternInterface.Invoke)).Invoke();
            await InvokeDialogButtonAsync(settingsRoot.XamlRoot, "취소");
            Check(updateInstalls == 0, "update confirmation cancellation never invokes installation");
            ((IInvokeProvider)new ButtonAutomationPeer(updateInstall).GetPattern(PatternInterface.Invoke)).Invoke();
            await InvokeDialogButtonAsync(settingsRoot.XamlRoot, "설치");
            await UntilAsync(() => updateInstalls == 1 && !fixtureUpdates.IsBusy);
            Check(true, "confirmed update invokes fixture installer without actual package registration");
            await RenderAsync(settingsRoot, "settings-updates.png");
            infoTabs.SelectedIndex = (int)SettingsSection.General;
            await UntilAsync(() => (settingsRoot.FindName("GeneralScroll") as ScrollViewer)?.IsLoaded == true);
            Check(Descendants(settingsRoot).OfType<TabViewItem>().All(tab => !tab.IsClosable), "settings sections cannot be accidentally closed");
            Check(settingsRoot.ActualWidth >= 400 && settingsRoot.ActualHeight >= 300, "settings client geometry provides usable layout");
            var generalScroll = (ScrollViewer)settingsRoot.FindName("GeneralScroll");
            settings.AppWindow.ResizeClient(new(560, 420));
            await Task.Delay(120);
            Check(generalScroll.ScrollableHeight > 0 && generalScroll.ScrollableWidth == 0, "small settings window scrolls vertically without horizontal overflow");
            generalScroll.ChangeView(null, generalScroll.ScrollableHeight, null, true);
            await Task.Delay(120);
            Check(generalScroll.VerticalOffset > 0, "bottom preferences remain reachable in a small client area");
            var soundToggle = (ToggleSwitch)settingsRoot.FindName("NotificationSoundToggle");
            soundToggle.IsOn = false;
            await Task.Delay(50);
            Check(savedSettings is { NotificationSoundEnabled: false, AutoPlayIncoming: false }, "real sound binding persists without changing autoplay");
            var appearance = (ComboBox)settingsRoot.FindName("AppearanceComboBox");
            appearance.SelectedIndex = 1;
            await Task.Delay(120);
            Check(savedSettings?.AppearanceMode == PingAppearanceMode.Light && settingsRoot.ActualTheme == ElementTheme.Light
                && root.ActualTheme == ElementTheme.Light, "light preference updates settings and existing messenger");
            var lightBackground = ((SolidColorBrush)settingsRoot.Background).Color;
            generalScroll.ChangeView(null, 0, null, true);
            await Task.Delay(80);
            await RenderAsync(settingsRoot, "settings-light.png");
            appearance.SelectedIndex = 2;
            await Task.Delay(120);
            Check(settingsRoot.ActualTheme == ElementTheme.Dark && root.ActualTheme == ElementTheme.Dark
                && ((SolidColorBrush)settingsRoot.Background).Color != lightBackground, "dark preference updates live theme resources");
            var futureSettings = new SettingsWindow(settingsVm);
            Check(((FrameworkElement)futureSettings.Content).RequestedTheme == ElementTheme.Dark, "new windows inherit selected appearance");
            futureSettings.Close();
            await RenderAsync(settingsRoot, "settings-dark.png");
            appearance.SelectedIndex = 0;
            await Task.Delay(50);
            Check(settingsRoot.RequestedTheme == ElementTheme.Default && root.RequestedTheme == ElementTheme.Default,
                "system preference restores Windows theme tracking");
            var tabs = (TabView)settingsRoot.FindName("SettingsTabs");
            tabs.SelectedIndex = (int)SettingsSection.Hotkeys;
            await UntilAsync(() => (settingsRoot.FindName("HotkeysScroll") as ScrollViewer)?.IsLoaded == true);
            var hotkeysScroll = (ScrollViewer)settingsRoot.FindName("HotkeysScroll");
            var editors = Descendants(hotkeysScroll).OfType<Expander>().ToArray();
            Check(editors.Length == 4 && hotkeysScroll.ScrollableWidth == 0, "four shortcut rows fit compact settings width");
            await RenderAsync(settingsRoot, "settings-hotkeys.png");
            editors[0].IsExpanded = true;
            await Task.Delay(120);
            var controlModifier = Descendants(editors[0]).OfType<CheckBox>().Single(box => box.Content?.ToString() == "Ctrl");
            controlModifier.IsChecked = true;
            await Task.Delay(50);
            Check(settingsVm.HotkeyRows[0].DisplayShortcut == "Ctrl+Alt+P"
                && Descendants(editors[0]).OfType<TextBlock>().Any(text => text.Text == "Ctrl+Alt+P"),
                "shortcut header reflects actual modifier edits");
            Check(hotkeysScroll.ScrollableWidth == 0, "expanded shortcut editor fits without horizontal scrolling");
            await RenderAsync(settingsRoot, "settings-hotkey-editor.png");
            settingsVm.HotkeyRows[0].ApplyBinding(HotkeyBinding.Alt("P"));
            tabs.SelectedIndex = (int)SettingsSection.Devices;
            await UntilAsync(() => settingsVm.Devices.Cameras.Count == 2 && !settingsVm.Devices.IsLoading);
            var cameraCombo = (ComboBox)settingsRoot.FindName("CameraSelectionCombo");
            var microphoneCombo = (ComboBox)settingsRoot.FindName("MicrophoneSelectionCombo");
            Step($"Device controls before load: camera items={cameraCombo.Items.Count}, microphone items={microphoneCombo.Items.Count}");
            await UntilAsync(() => cameraCombo.IsLoaded && microphoneCombo.IsLoaded && cameraCombo.Items.Count == 2 && microphoneCombo.Items.Count == 2);
            cameraCombo.SelectedIndex = 1;
            microphoneCombo.SelectedIndex = 1;
            await Task.Delay(80);
            Step($"Device binding: camera items={cameraCombo.Items.Count}, selected={cameraCombo.SelectedIndex}, model={settingsVm.Devices.SelectedCamera?.Id}, saved={savedSettings?.Devices.CameraId}; microphone items={microphoneCombo.Items.Count}, selected={microphoneCombo.SelectedIndex}, model={settingsVm.Devices.SelectedMicrophone?.Device?.EndpointId}, saved={savedSettings?.Devices.Microphone?.EndpointId}");
            Check(savedSettings?.Devices.CameraId == "fixture-camera" && savedSettings.Devices.Microphone == fixtureMicrophone,
                "real device bindings save camera and matched microphone identities");
            Check(savedSettings is { AutoPlayIncoming: false, NotificationSoundEnabled: false }, "device selection preserves presentation preferences");
            fixtureDevices = new([], []);
            await settingsVm.Devices.RefreshAsync();
            await Task.Delay(80);
            Check(((CameraChoice)cameraCombo.SelectedItem).Id == "fixture-camera"
                && ((MicrophoneChoice)microphoneCombo.SelectedItem).Device == fixtureMicrophone,
                "disconnected devices remain selected without switching to default");
            await RenderAsync(settingsRoot, "settings-devices.png");
            UI.SettingsWindowGeometry.Fit(settings, 560, 440);
            var qrImage = (Image)settingsRoot.FindName("PairingImage");
            await UntilAsync(() => qrImage.Source is not null);
            var devicesScroll = (ScrollViewer)settingsRoot.FindName("DevicesScroll");
            await Task.Delay(100);
            devicesScroll.ChangeView(null, devicesScroll.ScrollableHeight, null, true);
            await Task.Delay(100);
            await RenderAsync(settingsRoot, "settings-pairing-synthetic.png");
            await RenderAsync(qrImage, "pairing-image-synthetic.png");
            await DevicePairingSmoke.VerifyAsync(qrImage, settingsVm.Pairing.Image!.Png, Check);
            tabs.SelectedIndex = (int)SettingsSection.General;
            await Task.Delay(80);
            Check(qrImage.Source is null && settingsVm.Pairing.Image is null && !settingsVm.Pairing.IsActive,
                "leaving devices clears pairing pixels and session image state");
            tabs.SelectedIndex = (int)SettingsSection.Devices;
            await UntilAsync(() => qrImage.Source is not null);
            settings.Close();
            Check(qrImage.Source is null && settingsVm.Pairing.Image is null, "closing settings clears pairing image");
            Check(true, "real settings window created, rendered and closed without crash");
            Step("Verifying guided first-use setup with owned fake services and no devices.");
            await MessengerRoomsSmoke.RunAsync(Check, RenderAsync);
            await GuidedSetupSmoke.RunAsync(Check, RenderAsync);
            Step("Verifying owned native playback with a synthetic clip.");
            await PlaybackSmoke.RunAsync(window, OutputDirectory!, Check, RenderAsync);
            await AutoReplySmoke.RunAsync(window, Check, RenderAsync);
            await CaptureLifetimeSmoke.RunAsync(Check);
            await CaptureMirrorReviewSmoke.RunAsync(OutputDirectory!, Check, RenderAsync);
            await CaptureViewportInputSmoke.RunAsync(OutputDirectory!, Check, RenderAsync);
            await FaceVideoCropSmoke.RunAsync(OutputDirectory!, Check);

            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
            window.Close();
            await Task.Delay(100);
            Check(!window.AppWindow.IsVisible, "window close hides instead of disposing messenger");
            rpc.IncludeHiddenArrival = true;
            var verifiedRead = false;
            rpc.AllowRead = true;
            rpc.OnMarkRead = () =>
            {
                if (verifiedRead) return;
                Check(vm.Timeline.Any(row => row.SortId == "while-hidden"), "read acknowledgement follows displayed hidden arrival");
                verifiedRead = true;
            };
            window.ShowShell();
            await UntilAsync(() => vm.Timeline.Any(row => row.SortId == "while-hidden") && verifiedRead);
            Check(window.AppWindow.IsVisible && hwnd == WinRT.Interop.WindowNative.GetWindowHandle(window), "reopening reuses original window and HWND");
            Check(vm.Timeline.Any(row => row.SortId == "while-hidden"), "foreground return refreshes hidden arrivals before read acknowledgement");
            var readsBeforeTimer = rpc.TimelineReads;
            rpc.RequireUiThread = true;
            await UntilAsync(() => rpc.TimelineReads > readsBeforeTimer, 6);
            Check(true, "real refresh timer updates snapshots on UI thread");
            shell.RequestedTheme = ElementTheme.Light;
            var scale = shell.XamlRoot.RasterizationScale;
            window.AppWindow.Resize(new((int)(560 * scale), (int)(540 * scale)));
            await Task.Delay(180);
            Check(chatBox.ActualWidth >= 180 && sendButton.ActualWidth > 20 && roomsList.ActualWidth >= 150,
                "minimum window size keeps room list and composer usable");
            await RenderAsync(root, "messenger-minimum.png");
            await shell.DetachAsync();
            window.DetachMessenger();
            var freshVm = new HistoryViewModel(new RoomService(rpc), new MessageService(rpc, storage), new ChatMessageService(rpc),
                new ReactionService(rpc), storage, () => "me", new FixtureLinks());
            var freshShell = new HistoryWindow(window, freshVm, (_, _) => throw new NotSupportedException(), (_, _) => Task.CompletedTask,
                new MessageService(rpc, storage), loadOnStart: false);
            window.AttachMessenger(freshShell); await freshShell.ReloadRoomsAsync();
            Check(!shell.IsEnabled && window.Content is ContentControl { Content: HistoryWindow attached } && ReferenceEquals(attached, freshShell)
                && hwnd == WinRT.Interop.WindowNative.GetWindowHandle(window), "runtime replacement detaches old messenger and keeps the main HWND");
            Check(((TextBox)freshShell.FindName("ChatBox")).Text == "", "runtime replacement creates a fresh composer without old drafts");
            File.WriteAllText(Path.Combine(OutputDirectory!, "result.json"), JsonSerializer.Serialize(new { Success = true, Checks, FixtureOnly = true }, new JsonSerializerOptions { WriteIndented = true }));
            Step("DONE");
        }
        catch (Exception error) { WriteFailure(error); }
        finally { window?.CloseForQuit(); app.Exit(); }
    }

    private static void WriteFailure(Exception error)
    {
        Directory.CreateDirectory(OutputDirectory!);
        if (failureWritten) return;
        failureWritten = true;
        File.WriteAllText(Path.Combine(OutputDirectory!, "result.json"), JsonSerializer.Serialize(new { Success = false, Error = error.ToString(), Checks }, new JsonSerializerOptions { WriteIndented = true }));
        Step("FAILED " + error.GetType().Name);
    }

    private static async Task UntilAsync(Func<bool> condition, int timeoutSeconds = 3)
    {
        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
        while (!condition())
        {
            if (DateTime.UtcNow >= deadline) throw new TimeoutException("UI fixture action did not settle.");
            await Task.Delay(25);
        }
    }

    private static async Task InvokeDialogButtonAsync(XamlRoot root, string label)
    {
        Button? button = null;
        await UntilAsync(() =>
        {
            button = VisualTreeHelper.GetOpenPopupsForXamlRoot(root).SelectMany(popup => Descendants(popup.Child)).OfType<Button>()
                .FirstOrDefault(candidate => candidate.Content?.ToString() == label && candidate.IsEnabled);
            return button is not null;
        });
        ((IInvokeProvider)new ButtonAutomationPeer(button!).GetPattern(PatternInterface.Invoke)).Invoke();
        await Task.Delay(150);
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            yield return child;
            foreach (var descendant in Descendants(child)) yield return descendant;
        }
    }

    private static async Task RenderAsync(FrameworkElement root, string name)
    {
        root.UpdateLayout();
        var bitmap = new RenderTargetBitmap();
        await bitmap.RenderAsync(root);
        Check(bitmap.PixelWidth > 0 && bitmap.PixelHeight > 0, "render " + name);
        var pixels = (await bitmap.GetPixelsAsync()).ToArray();
        var path = Path.Combine(OutputDirectory!, name);
        File.WriteAllBytes(path, []);
        var file = await StorageFile.GetFileFromPathAsync(path);
        using var stream = await file.OpenAsync(FileAccessMode.ReadWrite);
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, (uint)bitmap.PixelWidth, (uint)bitmap.PixelHeight, 96, 96, pixels);
        await encoder.FlushAsync();
    }

    private sealed class FixtureRpc : ISupabaseRpcClient
    {
        public int CreateAttempts { get; private set; }
        public RenameRoomRpcBody? LastRename { get; private set; }
        public int LeaveAttempts { get; private set; }
        public int Sent;
        public bool FailSend;
        public int MemberCount = 2;
        public string OwnChatBody = "응, 대화하면서 3초 얼굴 영상도 바로 보낼 수 있어.";
        public IReadOnlyDictionary<string, object?>? LastChatBody;
        public int TimelineReads;
        public bool IncludeHiddenArrival;
        public bool IncludePhoto;
        public CaptureMode VideoMode = CaptureMode.FaceOnly;
        public int SeenCalls;
        public TaskCompletionSource? SeenGate;
        public bool RequireUiThread;
        public bool AllowRead;
        public Action? OnMarkRead;
        public Task<IReadOnlyList<T>> RpcArrayAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            if (function == "ping_create_room") { CreateAttempts++; throw new InvalidOperationException("테스트 연결 실패"); }
            if (RequireUiThread && Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread() is null)
                throw new InvalidOperationException("Fixture RPC was invoked outside the owning UI thread.");
            if (function == "ping_room_chat_messages") Interlocked.Increment(ref TimelineReads);
            var room = body is RoomChatMessagesRpcBody chat ? chat.RoomUuid : body is RoomMessagesRpcBody video ? video.RoomUuid : "a";
            object result = function switch
            {
                "ping_my_rooms" => new[] { Room("a", "디자인 이야기", 3), Room("b", "오늘의 작은 순간", 0) },
                "ping_incoming_invitations" => Array.Empty<Invitation>(),
                "ping_room_messages" => room == "a" ? new[] { Video() with { CaptureMode = VideoMode } } : Array.Empty<VideoMessage>(),
                "ping_room_chat_messages" => room == "a" ? new[]
                {
                    Chat("c1", "peer", "안녕! Windows에서도 이제 가볍게 핑을 보낼 수 있겠네 😊", -3),
                    Chat("c2", "me", OwnChatBody, -2),
                    Chat("c3", "peer", "좋아. 자세한 이야기는 여기에서 이어가자!", -1)
                }.Concat(IncludeHiddenArrival ? new[] { Chat("while-hidden", "peer", "다시 열면 바로 보여야 하는 메시지", 0) } : Array.Empty<ChatMessage>())
                .Concat(IncludePhoto ? new[] { Chat("photo", "peer", "함께 본 순간", 0) with { MediaPath = "peer/owned.png", MediaFileName = "공유한 사진.png", MediaWidth = 960, MediaHeight = 640 } } : Array.Empty<ChatMessage>()).ToArray() : Array.Empty<ChatMessage>(),
                "ping_message_reactions" => Array.Empty<MessageReaction>(),
                _ => throw new NotSupportedException(function)
            };
            return Task.FromResult((IReadOnlyList<T>)result);
        }
        public Task<T> RpcValueAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            if (function != "ping_send_chat") throw new NotSupportedException(function);
            Sent++;
            LastChatBody = body as IReadOnlyDictionary<string, object?>;
            if (FailSend) throw new InvalidOperationException("테스트 전송 실패");
            return Task.FromResult((T)(object)"fixture-sent-chat");
        }
        public Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            if (function == "ping_rename_room") LastRename = (RenameRoomRpcBody?)body;
            if (function == "ping_leave_room") LeaveAttempts++;
            if (function == "ping_mark_room_read") OnMarkRead?.Invoke();
            if (function == "ping_mark_message_seen") { SeenCalls++; return SeenGate?.Task ?? Task.CompletedTask; }
            return Task.CompletedTask;
        }
        private Room Room(string id, string name, int unread) => new(id, name, name, "me", MemberCount >= 3 ? ["me", "peer", "third"] : ["me", "peer"], new Dictionary<string, string> { ["me"] = "민", ["peer"] = "서연", ["third"] = "지민" }, RoomStatus.Open, UnreadCount: unread);
        private static ChatMessage Chat(string id, string sender, string text, int minutes) => new()
        { Id = id, RoomId = "a", SenderUid = sender, SenderNickname = sender == "me" ? "민" : "서연", Body = text, CreatedAt = DateTimeOffset.UtcNow.AddMinutes(minutes) };
        private static VideoMessage Video() => new()
        { Id = "v1", RoomId = "a", SenderUid = "peer", ReceiverUid = "me", SenderNickname = "서연", VideoId = "fixture", VideoUrl = "peer/fixture.mp4", DurationMs = 3000, MirrorPosition = new(0.5, 0.5), Status = MessageStatus.Uploaded, CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-4), ExpiresAt = DateTimeOffset.UtcNow.AddDays(1) };
    }
    private sealed class FixtureStorage : IStorageService, IChatMediaStorageService
    {
        public string? PhotoPath;
        public int ImageUploads;
        public int DeletedImages;
        public byte[]? LastUploadedImage;
        public Task<string> UploadVideoAsync(string localVideoPath, string senderUid, string videoId, IReadOnlyCollection<string> authorizedReceiverUids, DateTimeOffset expiresAt, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task DeleteVideoAsync(string remotePath, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task<ChatImageUpload> UploadChatImageAsync(string localImagePath, string senderUid, string messageId, CancellationToken cancellationToken = default)
        {
            ImageUploads++; LastUploadedImage = File.ReadAllBytes(localImagePath);
            return Task.FromResult(new ChatImageUpload($"{senderUid}/chat-images/{messageId}.png", "image/png", 960, 640, Path.GetFileName(localImagePath)));
        }
        public Task<string> DownloadChatMediaAsync(string remotePath, string fileExtension, CancellationToken cancellationToken = default) => PhotoPath is { } path ? Task.FromResult(path) : throw new NotSupportedException();
        public Task DeleteChatMediaAsync(string remotePath, CancellationToken cancellationToken = default) { DeletedImages++; return Task.CompletedTask; }
    }
    private sealed class FixtureLinks : ILinkPreviewService
    {
        public Task<LinkPreviewMetadata> MetadataAsync(Uri url, CancellationToken cancellationToken = default) => Task.FromResult(LinkPreviewMetadata.Fallback(url));
    }
    private sealed class FixtureStartup : IStartupTaskController
    {
        public Task<PingStartupTaskStatus> GetStatusAsync(CancellationToken cancellationToken = default) => Task.FromResult(new PingStartupTaskStatus(PingStartupTaskState.Disabled, "Fixture startup disabled"));
        public Task<PingStartupTaskStatus> SetEnabledAsync(bool isEnabled, CancellationToken cancellationToken = default) => GetStatusAsync(cancellationToken);
    }
}
#endif
