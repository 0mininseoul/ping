using System.Xml.Linq;
using Ping.Windows.App.Capture;
using Ping.Windows.App.Hotkeys;
using Ping.Windows.App.Notifications;
using Ping.Windows.App.Setup;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class PresentationPreferencesTests
{
    [Fact]
    public void OldSettingsPreserveCapturePreferencesAndNewPreferencesRoundTrip()
    {
        var root = Path.Combine(Path.GetTempPath(), "PingPresentationTests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var path = Path.Combine(root, "settings.json");
            File.WriteAllText(path, """{"DefaultRoomId":"room","AutoPlayIncoming":false,"Preferences":{"SaveSentCopy":true}}""");
            var store = new ScreenFaceQuickSendSettingsStore(path);
            var old = store.Load();
            Assert.True(old.NotificationSoundEnabled);
            Assert.Equal(PingAppearanceMode.System, old.AppearanceMode);
            store.Save(old with { NotificationSoundEnabled = false, AppearanceMode = PingAppearanceMode.Light });
            var saved = store.Load();
            Assert.False(saved.NotificationSoundEnabled);
            Assert.Equal(PingAppearanceMode.Light, saved.AppearanceMode);
            Assert.Equal("room", saved.DefaultRoomId);
            Assert.True(saved.Preferences.SaveSentCopy);
            Assert.False(saved.AutoPlayIncoming);
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact]
    public void ViewModelSavesPresentationChangesWithoutLosingExistingPreferences()
    {
        ScreenFaceQuickSendSettings? saved = null;
        var old = ScreenFaceQuickSendSettings.Default with { DefaultRoomId = "room", AutoPlayIncoming = false };
        var model = new SettingsWindowViewModel("나", HotkeyBinding.Defaults(), old, value => saved = value, () => { });
        model.NotificationSoundEnabled = false;
        model.AppearanceSelection = 2;
        Assert.NotNull(saved);
        Assert.False(saved.NotificationSoundEnabled);
        Assert.Equal(PingAppearanceMode.Dark, saved.AppearanceMode);
        Assert.Equal("room", saved.DefaultRoomId);
        Assert.False(saved.AutoPlayIncoming);
        model.ApplySettings(old);
        Assert.Equal(0, model.AppearanceSelection);
        Assert.True(model.NotificationSoundEnabled);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void ActualVideoAndChatToastXmlRespectCurrentSoundPreference(bool enabled)
    {
        var sound = enabled;
        var xml = new List<XDocument>();
        using var controller = new NotificationController((_, _) => Task.CompletedTask,
            registry: NotifiedMessageRegistry.InMemory(), chatRegistry: NotifiedChatRegistry.InMemory(),
            showNotificationXml: value => xml.Add(XDocument.Parse(value)), soundEnabled: () => sound);
        Assert.Equal(NotificationShowResult.Shown, controller.ShowIncoming(new VideoMessage
            { Id = "video", SenderNickname = "나", SenderUid = "me", ReceiverUid = "peer", RoomId = "room",
                VideoId = "fixture", VideoUrl = "fixture.mp4", DurationMs = 3000, MirrorPosition = new(.5, .5),
                Status = MessageStatus.Uploaded, ExpiresAt = DateTimeOffset.UtcNow.AddDays(1) }));
        sound = !enabled;
        Assert.Equal(NotificationShowResult.Shown, controller.ShowIncomingChat(new IncomingChatNotification(
            new ChatMessage { Id = "chat", RoomId = "room", SenderUid = "me", SenderNickname = "나", Body = "안녕" }, "방", 1)));
        Assert.Equal(enabled ? null : "true", xml[0].Root!.Element("audio")?.Attribute("silent")?.Value);
        Assert.Equal(!enabled ? null : "true", xml[1].Root!.Element("audio")?.Attribute("silent")?.Value);
        Assert.All(xml, toast => Assert.NotNull(toast.Root!.Attribute("launch")));
    }
}
