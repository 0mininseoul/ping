#if PING_UI_SMOKE
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Ping.Windows.App.Onboarding;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Diagnostics;

internal static class GuidedSetupSmoke
{
    internal static async Task RunAsync(Action<bool, string> check, Func<FrameworkElement, string, Task> render)
    {
        var saves = 0; var creates = 0; var joins = 0; var completes = 0; var probes = 0;
        string? joinedId = null;
        var openRoom = new Room("fixture-join", "친구와 나", "친구와 나", "other", ["other"], new Dictionary<string, string> { ["other"] = "지우" }, RoomStatus.Open);
        var sameNameRoom = new Room("fixture-join-2", "친구와 나", "친구와 나", "other-two", ["other-two"], new Dictionary<string, string> { ["other-two"] = "수진" }, RoomStatus.Open);
        GuidedSetupViewModel NewModel() => new(new(
            (name, _) => { saves++; return Task.FromResult(name); },
            (_, _, _) => { creates++; return Task.CompletedTask; },
            (_, _) => Task.FromResult<IReadOnlyList<Room>>([openRoom, sameNameRoom]),
            (id, _, _) => { joins++; joinedId = id; return Task.CompletedTask; }, () => "me"));
        Task<OnboardingEnvironmentState> Probe(CancellationToken token)
        {
            probes++; token.ThrowIfCancellationRequested();
            return Task.FromResult(OnboardingEnvironmentState.Ready() with
            { Camera = OnboardingProbeState.Blocked("fixture-only: no camera"), Microphone = OnboardingProbeState.Blocked("fixture-only: no microphone") });
        }
        var model = NewModel();
        var window = new GuidedSetupWindow(model, () => completes++, Probe);
        try
        {
            window.Activate(); await Task.Delay(180);
            TestDisplayPlacement.Verify(window, check);
            var root = (Grid)window.Content;
            check(UI.WindowCaptureExclusion.IsApplied(window), "guided setup retains screen capture exclusion");
            check(probes == 0 && model.Step == GuidedSetupStep.Welcome, "welcome performs no automatic camera or microphone probe");
            root.RequestedTheme = ElementTheme.Light; await Task.Delay(60); await render(root, "onboarding-welcome-light.png");
            root.RequestedTheme = ElementTheme.Dark; await Task.Delay(60); await render(root, "onboarding-welcome-dark.png");
            root.RequestedTheme = ElementTheme.Light;
            await Click(root, "NextButton");
            await Click(root, "CheckPermissionsButton");
            check(probes == 1 && ((TextBlock)root.FindName("CameraStatus")).Text.Contains("확인", StringComparison.Ordinal),
                "permission check shows missing fixture camera without touching devices");
            check(((Button)root.FindName("NextButton")).IsEnabled, "missing camera and microphone do not block setup continuation");
            var permissionsHint = (TextBlock)root.FindName("PermissionsHint");
            check(permissionsHint.Visibility == Visibility.Visible
                && permissionsHint.TransformToVisual(root).TransformPoint(new(0, 0)).Y + permissionsHint.ActualHeight < root.ActualHeight,
                "permission continuation guidance remains visible beside footer");
            await render(root, "onboarding-permissions.png");
            await Click(root, "NextButton");
            check(!((Button)root.FindName("NextButton")).IsEnabled, "empty nickname disables actual next control");
            ((TextBox)root.FindName("NicknameInput")).Text = "민지"; await Task.Delay(50);
            await render(root, "onboarding-nickname.png");
            await Click(root, "NextButton");
            check(saves == 1 && model.Step == GuidedSetupStep.ConnectionChoice, "nickname textbox and next save through the setup callback");
            await render(root, "onboarding-connection-choice.png");
            await Click(root, "CreateChoiceButton");
            ((TextBox)root.FindName("RoomNameInput")).Text = "친구와 나"; await Task.Delay(50);
            await render(root, "onboarding-create-room.png");
            await Click(root, "NextButton");
            check(creates == 1 && model.Step == GuidedSetupStep.Done, "create room control reaches completion only after service callback");
            await render(root, "onboarding-done.png");
            await Click(root, "NextButton");
            check(completes == 1, "done control completes setup and closes its window");
        }
        finally { if (completes == 0) window.Close(); }

        var joinModel = NewModel();
        var joinWindow = new GuidedSetupWindow(joinModel, () => completes++, Probe);
        try
        {
            joinWindow.Activate(); await Task.Delay(100);
            TestDisplayPlacement.Verify(joinWindow, check);
            var root = (Grid)joinWindow.Content;
            await Click(root, "NextButton"); await Click(root, "NextButton");
            ((TextBox)root.FindName("NicknameInput")).Text = "민지"; await Task.Delay(50);
            await Click(root, "NextButton"); await Click(root, "JoinChoiceButton");
            ((TextBox)root.FindName("RoomSearchInput")).Text = "친구";
            await Click(root, "SearchRoomsButton");
            var results = (ListView)root.FindName("JoinResults");
            check(results.Items.Count == 2 && !((Button)root.FindName("NextButton")).IsEnabled, "join search binds real result list and requires selection");
            check(Texts(results).Contains("방장: 지우") && Texts(results).Contains("방장: 수진"),
                "same-name room cards show distinct owner nicknames in actual templates");
            results.SelectedIndex = 1; await Task.Delay(50);
            check(joinModel.SelectedRoom?.Id == sameNameRoom.Id && ((Button)root.FindName("NextButton")).IsEnabled,
                "selecting an open room enables actual join control");
            await Task.Delay(180);
            await render(root, "onboarding-join-room.png");
            await Click(root, "NextButton");
            check(joins == 1 && joinedId == sameNameRoom.Id && creates == 1 && joinModel.Step == GuidedSetupStep.Done,
                "join action uses selected owner's room without creating a room");
        }
        finally { joinWindow.Close(); }
    }
    private static async Task Click(Grid root, string name)
    {
        var button = (ButtonBase)root.FindName(name);
        if (!button.IsEnabled) throw new InvalidOperationException($"Setup control is disabled: {name}");
        var peer = FrameworkElementAutomationPeer.CreatePeerForElement(button);
        ((IInvokeProvider)peer.GetPattern(PatternInterface.Invoke)).Invoke();
        await Task.Delay(80);
    }
    private static IEnumerable<string> Texts(DependencyObject root)
    {
        if (root is TextBlock text) yield return text.Text;
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
            foreach (var value in Texts(VisualTreeHelper.GetChild(root, index))) yield return value;
    }
}
#endif
