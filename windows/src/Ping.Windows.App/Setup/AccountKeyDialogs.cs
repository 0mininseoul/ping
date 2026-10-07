using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Ping.Windows.Core.Backend;

namespace Ping.Windows.App.Setup;

internal static class AccountKeyDialogs
{
    public static async Task ConnectAsync(FrameworkElement root, CancellationToken token)
    {
        var app = (App)Application.Current;
        var nickname = new TextBox { PlaceholderText = "기존 계정의 현재 닉네임", MaxLength = 256 };
        var key = new PasswordBox { PlaceholderText = "설정에서 직접 만든 비밀키", MaxLength = 128 };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(nickname, "기존 계정 닉네임");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(key, "기존 계정 비밀키");
        var content = Panel();
        content.Children.Add(Detail("기존 기기의 설정에서 비밀키를 만든 경우에만 연결할 수 있어요."));
        content.Children.Add(nickname); content.Children.Add(key);
        content.Children.Add(Detail("이 PC에 로그인 상태가 저장됩니다."));
        var error = Detail(""); content.Children.Add(error);
        var dialog = Dialog(root, "기존 계정 연결", "연결", content);
        ConnectedPingAccount? account = null;
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(token);
        bool submitting = false, closed = false;
        dialog.Closing += (_, args) => { if (submitting && !linked.IsCancellationRequested) args.Cancel = true; };
        using var registration = token.Register(() => root.DispatcherQueue.TryEnqueue(() => { if (!closed) dialog.Hide(); }));
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            if (submitting) { args.Cancel = true; return; }
            if (string.IsNullOrWhiteSpace(nickname.Text)) { args.Cancel = true; error.Text = "닉네임을 입력해 주세요."; return; }
            var deferral = args.GetDeferral();
            submitting = true; dialog.IsPrimaryButtonEnabled = false; nickname.IsEnabled = key.IsEnabled = false;
            error.Text = "계정을 연결하고 있어요…";
            try
            {
                account = await app.AuthenticateAccountKeyAsync(nickname.Text, key.Password, linked.Token);
                args.Cancel = false;
            }
            catch (OperationCanceledException) { args.Cancel = true; }
            catch (AccountKeyException ex) { args.Cancel = true; error.Text = ex.Message; }
            catch { args.Cancel = true; error.Text = "계정을 연결하지 못했어요. 연결을 확인하고 다시 시도해 주세요."; }
            finally
            {
                submitting = false;
                if (!closed) { dialog.IsPrimaryButtonEnabled = true; nickname.IsEnabled = key.IsEnabled = true; }
                deferral.Complete();
            }
        };
        ContentDialogResult result;
        try { token.ThrowIfCancellationRequested(); result = await dialog.ShowAsync(); }
        finally { closed = true; linked.Cancel(); key.Password = ""; }
        if (result != ContentDialogResult.Primary || account is null) return;
        // The dialog is gone before the coordinator closes its parent window.
        try { await app.CompleteAccountConnectionAsync(account); }
        catch { /* The new/current Settings window owns the explicit persistence retry. */ }
    }

    public static async Task SetKeyAsync(FrameworkElement root, string nickname, AccountKeySettingsViewModel model, CancellationToken token)
    {
        var key = new PasswordBox { PlaceholderText = "직접 정할 비밀키 · 12~128자", MaxLength = 128 };
        var confirm = new PasswordBox { PlaceholderText = "비밀키 다시 입력", MaxLength = 128 };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(key, "새 비밀키");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(confirm, "새 비밀키 확인");
        var content = Panel();
        content.Children.Add(Detail($"다른 PC에서 ‘{nickname}’와 이 비밀키로 들어올 수 있어요."));
        content.Children.Add(key); content.Children.Add(confirm);
        content.Children.Add(Detail("공백과 대소문자를 구분해요. 키를 바꿔도 이미 연결된 기기는 유지됩니다. 모든 기기와 키를 잃으면 계정을 복구할 수 없어요."));
        var error = Detail(""); content.Children.Add(error);
        var dialog = Dialog(root, model.SetKeyLabel, "저장", content);
        bool submitting = false, closed = false;
        dialog.Closing += (_, args) => { if (submitting && !token.IsCancellationRequested) args.Cancel = true; };
        using var registration = token.Register(() => root.DispatcherQueue.TryEnqueue(() => { if (!closed) dialog.Hide(); }));
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            if (submitting) { args.Cancel = true; return; }
            if (key.Password.Length is < 12 or > 128) { args.Cancel = true; error.Text = "비밀키는 12~128자로 정해 주세요."; return; }
            if (key.Password != confirm.Password) { args.Cancel = true; error.Text = "입력한 비밀키가 서로 달라요."; return; }
            var deferral = args.GetDeferral();
            submitting = true; dialog.IsPrimaryButtonEnabled = false; key.IsEnabled = confirm.IsEnabled = false;
            error.Text = "비밀키를 저장하고 있어요…";
            try { await model.SaveAsync(key.Password, token); args.Cancel = false; }
            catch (OperationCanceledException) { args.Cancel = true; }
            catch (AccountKeyException ex) { args.Cancel = true; error.Text = ex.Message; }
            catch { args.Cancel = true; error.Text = "비밀키를 저장하지 못했어요. 다시 시도해 주세요."; }
            finally
            {
                submitting = false;
                if (!closed) { dialog.IsPrimaryButtonEnabled = true; key.IsEnabled = confirm.IsEnabled = true; }
                deferral.Complete();
            }
        };
        try { token.ThrowIfCancellationRequested(); await dialog.ShowAsync(); }
        finally { closed = true; key.Password = confirm.Password = ""; }
    }

    private static StackPanel Panel() => new() { Spacing = 12, MaxWidth = 360 };
    private static TextBlock Detail(string text) => new()
    {
        Text = text, FontSize = 13, TextWrapping = TextWrapping.WrapWholeWords,
        FontFamily = (FontFamily)Application.Current.Resources["PingFontFamily"],
        Foreground = (Brush)Application.Current.Resources["PingMutedBrush"]
    };
    private static ContentDialog Dialog(FrameworkElement root, string title, string action, object content) => new()
    {
        XamlRoot = root.XamlRoot, RequestedTheme = root.ActualTheme,
        Title = title, Content = content, PrimaryButtonText = action, CloseButtonText = "취소",
        DefaultButton = ContentDialogButton.Primary, FontFamily = (FontFamily)Application.Current.Resources["PingFontFamily"]
    };
}
