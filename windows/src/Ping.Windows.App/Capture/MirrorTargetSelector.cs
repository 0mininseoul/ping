using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Capture;

internal sealed class MirrorTargetSelector
{
    private readonly IReadOnlyList<Room> rooms;
    private readonly string fallbackLabel;
    private bool isAllSelected;
    private int selectedIndex;

    public MirrorTargetSelector(IReadOnlyCollection<Room> rooms, string fallbackLabel)
    {
        this.rooms = rooms.ToArray();
        this.fallbackLabel = string.IsNullOrWhiteSpace(fallbackLabel) ? "No partner" : fallbackLabel;
        isAllSelected = this.rooms.Count > 1;
    }

    public string Label
    {
        get
        {
            if (rooms.Count == 0)
            {
                return fallbackLabel;
            }

            if (isAllSelected)
            {
                return "All rooms";
            }

            return rooms.Count == 1 ? fallbackLabel : rooms[selectedIndex].Name;
        }
    }

    public bool IsAllSelected => rooms.Count > 1 && isAllSelected;

    public IReadOnlyCollection<Room> SelectedRooms
    {
        get
        {
            if (rooms.Count == 0)
            {
                return [];
            }

            return isAllSelected ? rooms : [rooms[selectedIndex]];
        }
    }

    public bool SelectNext()
    {
        if (rooms.Count <= 1)
        {
            return false;
        }

        if (isAllSelected)
        {
            isAllSelected = false;
            selectedIndex = 0;
            return true;
        }

        if (selectedIndex < rooms.Count - 1)
        {
            selectedIndex += 1;
            return true;
        }

        isAllSelected = true;
        return true;
    }

    public bool SelectAll()
    {
        if (rooms.Count <= 1 || isAllSelected)
        {
            return false;
        }

        isAllSelected = true;
        return true;
    }

    public bool SelectIndex(int index)
    {
        if (index < 0 || index >= rooms.Count)
        {
            return false;
        }

        if (!isAllSelected && selectedIndex == index)
        {
            return false;
        }

        isAllSelected = false;
        selectedIndex = index;
        return true;
    }
}
