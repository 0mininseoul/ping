using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Setup;

internal sealed class RoomDialogs(FrameworkElement root, RoomManagerViewModel model, Func<string?>? selectedRoomId = null)
{
    private string? CurrentRoomId => selectedRoomId is null ? model.SelectedRoom?.Id : selectedRoomId();

    public async Task<bool> ShowRoomNameDialogAsync(bool create, CancellationToken token = default)
    {
        token.ThrowIfCancellationRequested();
        var openingRoomId = model.SelectedRoom?.Id;
        if (!create && openingRoomId is null) return false;
        var input = new TextBox { Text = create ? "" : model.SelectedRoomName, PlaceholderText = "룸 이름", CornerRadius = new(8) };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(input, create ? "새 룸 이름" : "룸 이름 변경");
        var error = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(new TextBlock { Text = "룸 이름을 16자 이내로 입력하세요.", TextWrapping = TextWrapping.Wrap });
        content.Children.Add(input); content.Children.Add(error);
        var dialog = new ContentDialog
        {
            XamlRoot = root.XamlRoot, RequestedTheme = root.ActualTheme,
            Title = create ? "새 룸 만들기" : "룸 이름 변경", Content = content,
            PrimaryButtonText = create ? "만들기" : "저장", CloseButtonText = "취소", DefaultButton = ContentDialogButton.Primary
        };
        var submitting = false;
        var cancelled = false;
        var dispatcher = root.DispatcherQueue;
        dialog.Closing += (_, args) => args.Cancel = submitting && !cancelled;
        using var registration = token.Register(() => dispatcher.TryEnqueue(() => { cancelled = true; dialog.Hide(); }));
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            if (!create && CurrentRoomId != openingRoomId)
            { args.Cancel = true; error.Text = "선택한 룸이 바뀌었어요. 창을 닫고 다시 시도하세요."; return; }
            var name = DisplayText.NormalizeWhitespace(input.Text);
            if (string.IsNullOrWhiteSpace(name) || System.Globalization.StringInfo.ParseCombiningCharacters(name).Length > 16)
            { args.Cancel = true; error.Text = "룸 이름을 1~16자로 입력하세요."; return; }
            var deferral = args.GetDeferral();
            submitting = true; dialog.IsPrimaryButtonEnabled = false; dialog.CloseButtonText = ""; input.IsEnabled = false;
            try
            {
                token.ThrowIfCancellationRequested();
                if (create) await model.CreateRoomAsync(name, token);
                else await model.RenameSelectedRoomAsync(name, token);
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { args.Cancel = true; cancelled = true; dialog.Hide(); }
            catch (Exception ex) { args.Cancel = true; error.Text = ex.Message; model.ReportError(ex); }
            finally
            {
                submitting = false; dialog.IsPrimaryButtonEnabled = true; dialog.CloseButtonText = "취소";
                input.IsEnabled = true; deferral.Complete();
            }
        };
        dialog.Opened += (_, _) => { input.Focus(FocusState.Programmatic); input.SelectAll(); };
        return await dialog.ShowAsync() == ContentDialogResult.Primary && !token.IsCancellationRequested;
    }

    public async Task<bool> ShowLeaveDialogAsync(CancellationToken token = default)
    {
        token.ThrowIfCancellationRequested();
        if (model.SelectedRoom is not { Id: { } openingRoomId } room) return false;
        var dialog = new ContentDialog
        {
            XamlRoot = root.XamlRoot, RequestedTheme = root.ActualTheme, Title = "룸 나가기",
            Content = $"‘{room.Name}’ 룸에서 나갑니다. 계속하시겠습니까?",
            PrimaryButtonText = "나가기", CloseButtonText = "취소", DefaultButton = ContentDialogButton.Close
        };
        var submitting = false; var cancelled = false; var accepted = false;
        var dispatcher = root.DispatcherQueue;
        dialog.Closing += (_, args) => args.Cancel = submitting && !cancelled;
        using var registration = token.Register(() => dispatcher.TryEnqueue(() => { cancelled = true; dialog.Hide(); }));
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            // Decide the target when the user confirms, before the closing animation.
            if (CurrentRoomId != openingRoomId || token.IsCancellationRequested) return;
            var deferral = args.GetDeferral();
            submitting = true; dialog.IsPrimaryButtonEnabled = false; dialog.CloseButtonText = "";
            try { await model.LeaveSelectedRoomAsync(token); accepted = true; }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { cancelled = true; dialog.Hide(); }
            catch (Exception ex) { args.Cancel = true; model.ReportError(ex); dialog.Content = ex.Message; }
            finally { submitting = false; dialog.IsPrimaryButtonEnabled = true; dialog.CloseButtonText = "취소"; deferral.Complete(); }
        };
        await dialog.ShowAsync();
        return accepted && !token.IsCancellationRequested;
    }
}
