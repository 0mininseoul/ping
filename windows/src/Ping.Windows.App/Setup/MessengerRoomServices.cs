using Ping.Windows.Core.Backend;

namespace Ping.Windows.App.Setup;

public sealed record MessengerRoomServices(
    RoomService Rooms, InvitationService Invitations, UserService Users,
    Func<string?> CurrentUid, Func<string> Nickname, Action RoomsChanged, IClipboardWriter? Clipboard = null);
