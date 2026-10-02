using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Onboarding;

public enum GuidedSetupStep { Welcome, Permissions, Nickname, ConnectionChoice, CreateRoom, JoinRoom, Done }
public sealed record GuidedSetupActions(
    Func<string, CancellationToken, Task<string>> SaveNickname,
    Func<string, string, CancellationToken, Task> CreateRoom,
    Func<string, CancellationToken, Task<IReadOnlyList<Room>>> SearchRooms,
    Func<string, string, CancellationToken, Task> JoinRoom,
    Func<string?> CurrentUid);

public sealed class GuidedSetupViewModel(GuidedSetupActions actions) : INotifyPropertyChanged, IDisposable
{
    private readonly CancellationTokenSource lifetime = new();
    private bool disposed;
    private bool startedLater;
    public GuidedSetupStep? CompletedFrom { get; private set; }
    private string nickname = "", roomName = "", searchText = "";
    private Room? selectedRoom;
    public event PropertyChangedEventHandler? PropertyChanged;
    public GuidedSetupStep Step { get; private set; }
    public string Nickname { get => nickname; set => Set(ref nickname, value); }
    public string RoomName
    {
        get => roomName;
        set
        {
            var elements = StringInfo.ParseCombiningCharacters(value);
            Set(ref roomName, elements.Length > 16 ? value[..elements[16]] : value);
        }
    }
    public string SearchText { get => searchText; set => Set(ref searchText, value); }
    public string Error { get; private set; } = "";
    public bool IsBusy { get; private set; }
    public bool CanContinue => !disposed && !IsBusy && Step switch
    {
        GuidedSetupStep.Nickname => ValidNickname,
        GuidedSetupStep.CreateRoom => ValidRoomName,
        GuidedSetupStep.JoinRoom => SelectedRoom?.Id is { } id && SearchResults.Any(room => room.Id == id),
        GuidedSetupStep.ConnectionChoice => false,
        _ => true
    };
    public bool CanEdit => !disposed && !IsBusy;
    public bool CanGoBack => CanEdit && Step is not (GuidedSetupStep.Welcome or GuidedSetupStep.Done);
    public string ContinueLabel => Step switch
    {
        GuidedSetupStep.Welcome => "시작하기", GuidedSetupStep.Permissions => "계속", GuidedSetupStep.CreateRoom => "룸 만들기",
        GuidedSetupStep.JoinRoom => "룸 참여하기", GuidedSetupStep.Done when CompletedFrom == GuidedSetupStep.CreateRoom => "초대 화면 열기",
        GuidedSetupStep.Done => "Ping 시작하기", _ => "다음"
    };
    private int StepNumber => Step switch
    {
        GuidedSetupStep.Welcome => 1, GuidedSetupStep.Permissions => 2, GuidedSetupStep.Nickname => 3,
        GuidedSetupStep.ConnectionChoice => 4, GuidedSetupStep.Done => startedLater ? 5 : 6, _ => 5
    };
    public double Progress => 100d * StepNumber / (startedLater ? 5 : 6);
    public string ProgressLabel => $"{StepNumber} / {(startedLater ? 5 : 6)}";
    public string NicknameHint => ValidNickname ? "룸 검색과 초대 알림에 표시됩니다." : "닉네임을 24자 이내로 입력하세요.";
    public string NicknameCount => $"{StringInfo.ParseCombiningCharacters(NormalizedNickname).Length}/24";
    public string RoomNameCount => $"{StringInfo.ParseCombiningCharacters(DisplayText.NormalizeWhitespace(RoomName)).Length}/16";
    public string DoneSubtitle => CompletedFrom switch
    {
        GuidedSetupStep.CreateRoom => "룸을 만들었어요. 초대 화면에서 상대를 연결하세요.",
        GuidedSetupStep.JoinRoom => "선택한 룸에 참여했어요. 이제 메신저에서 사용할 수 있습니다.",
        _ => "트레이의 내 룸에서 언제든 룸을 만들거나 참여할 수 있습니다."
    };
    public Room? SelectedRoom { get => selectedRoom; set => Set(ref selectedRoom, value); }
    public ObservableCollection<Room> SearchResults { get; } = [];
    private string NormalizedNickname => DisplayText.NormalizeWhitespace(Nickname);
    private bool ValidNickname => StringInfo.ParseCombiningCharacters(NormalizedNickname).Length is >= 1 and <= 24;
    private bool ValidRoomName => StringInfo.ParseCombiningCharacters(DisplayText.NormalizeWhitespace(RoomName)).Length is >= 1 and <= 16;

    public async Task NextAsync()
    {
        if (!CanContinue) return;
        switch (Step)
        {
            case GuidedSetupStep.Welcome: Move(GuidedSetupStep.Permissions); break;
            case GuidedSetupStep.Permissions: Move(GuidedSetupStep.Nickname); break;
            case GuidedSetupStep.Nickname:
                await RunAsync(async token =>
                {
                    var saved = await actions.SaveNickname(NormalizedNickname, token);
                    token.ThrowIfCancellationRequested();
                    Nickname = saved; Move(GuidedSetupStep.ConnectionChoice);
                }, "닉네임을 저장하지 못했습니다. 연결을 확인하고 다시 시도해 주세요.");
                break;
            case GuidedSetupStep.CreateRoom:
                await RunAsync(async token =>
                {
                    await actions.CreateRoom(Ping.Windows.Core.Backend.RoomName.Normalize(RoomName), NormalizedNickname, token);
                    token.ThrowIfCancellationRequested(); Complete(GuidedSetupStep.CreateRoom);
                }, "룸을 만들지 못했습니다. 연결을 확인하고 다시 시도해 주세요.");
                break;
            case GuidedSetupStep.JoinRoom:
                var id = SelectedRoom!.Id!;
                await RunAsync(async token =>
                {
                    await actions.JoinRoom(id, NormalizedNickname, token);
                    token.ThrowIfCancellationRequested(); Complete(GuidedSetupStep.JoinRoom);
                }, "룸에 참여하지 못했습니다. 아직 열린 룸인지 확인하고 다시 시도해 주세요.");
                break;
        }
    }
    public async Task SearchAsync()
    {
        if (!CanEdit || Step != GuidedSetupStep.JoinRoom) return;
        SearchResults.Clear(); SelectedRoom = null;
        var query = DisplayText.NormalizeWhitespace(SearchText);
        if (query.Length == 0) return;
        await RunAsync(async token =>
        {
            var results = await actions.SearchRooms(query, token);
            token.ThrowIfCancellationRequested();
            var uid = actions.CurrentUid();
            foreach (var room in results.Where(room => room.Id is not null && room.Status == RoomStatus.Open
                && room.MemberUids.Count < 2 && room.OwnerUid != uid && !room.MemberUids.Contains(uid ?? ""))) SearchResults.Add(room);
            if (SearchResults.Count == 0) Error = "열린 룸이 없습니다. 룸 이름을 확인해 주세요.";
        }, "룸을 검색하지 못했습니다. 연결을 확인하고 다시 시도해 주세요.");
    }
    public void ChooseCreateRoom() { if (CanEdit && Step == GuidedSetupStep.ConnectionChoice) Move(GuidedSetupStep.CreateRoom); }
    public void ChooseJoinRoom() { if (CanEdit && Step == GuidedSetupStep.ConnectionChoice) Move(GuidedSetupStep.JoinRoom); }
    public void StartLater() { if (CanEdit && Step == GuidedSetupStep.ConnectionChoice) { startedLater = true; Complete(GuidedSetupStep.ConnectionChoice); } }
    public void Back()
    {
        if (!CanGoBack) return;
        Move(Step switch
        {
            GuidedSetupStep.Permissions => GuidedSetupStep.Welcome,
            GuidedSetupStep.Nickname => GuidedSetupStep.Permissions,
            GuidedSetupStep.ConnectionChoice => GuidedSetupStep.Nickname,
            _ => GuidedSetupStep.ConnectionChoice
        });
    }
    private async Task RunAsync(Func<CancellationToken, Task> operation, string error)
    {
        if (!CanEdit) return;
        var token = lifetime.Token;
        IsBusy = true; Error = ""; Notify();
        try { await operation(token); }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        catch (Exception) { if (!disposed) Error = error; }
        finally { IsBusy = false; Notify(); }
    }
    private void Move(GuidedSetupStep step) { Step = step; Error = ""; Notify(); }
    private void Complete(GuidedSetupStep from) { CompletedFrom = from; Move(GuidedSetupStep.Done); }
    private void Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value; PropertyChanged?.Invoke(this, new(name)); Notify();
    }
    private void Notify() => PropertyChanged?.Invoke(this, new(null));
    public void Dispose()
    {
        if (disposed) return;
        disposed = true; lifetime.Cancel(); lifetime.Dispose(); Notify();
    }
}
