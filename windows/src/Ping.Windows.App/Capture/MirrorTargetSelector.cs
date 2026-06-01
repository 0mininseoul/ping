using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Capture;

public sealed record MirrorTargetOption(
    int Index,
    string Label,
    bool IsAll,
    bool IsSelected);

internal sealed class MirrorTargetSelector
{
    private readonly IReadOnlyList<Room> rooms;
    private readonly string fallbackLabel;
    private readonly HashSet<int> selectedIndexes = [];

    public MirrorTargetSelector(IReadOnlyCollection<Room> rooms, string fallbackLabel)
    {
        this.rooms = rooms.ToArray();
        this.fallbackLabel = string.IsNullOrWhiteSpace(fallbackLabel) ? "No partner" : fallbackLabel;
        if (this.rooms.Count > 1)
        {
            selectedIndexes.UnionWith(Enumerable.Range(0, this.rooms.Count));
        }
        else if (this.rooms.Count == 1)
        {
            selectedIndexes.Add(0);
        }
    }

    public string Label
    {
        get
        {
            if (rooms.Count == 0)
            {
                return fallbackLabel;
            }

            if (selectedIndexes.Count == 0)
            {
                return "No partner";
            }

            if (IsAllSelected)
            {
                return rooms.Count == 1 ? fallbackLabel : $"All rooms ({rooms.Count})";
            }

            if (selectedIndexes.Count == 1)
            {
                return rooms[selectedIndexes.Min()].Name;
            }

            return $"{selectedIndexes.Count} rooms";
        }
    }

    public bool IsAllSelected => rooms.Count > 1 && selectedIndexes.Count == rooms.Count;

    public bool HasMultipleTargets => rooms.Count > 1;

    public IReadOnlyList<MirrorTargetOption> Options
    {
        get
        {
            if (!HasMultipleTargets)
            {
                return [];
            }

            var options = new List<MirrorTargetOption>(rooms.Count + 1)
            {
                new(-1, $"All rooms ({rooms.Count})", IsAll: true, IsSelected: IsAllSelected)
            };
            for (var index = 0; index < rooms.Count; index += 1)
            {
                options.Add(new MirrorTargetOption(index, rooms[index].Name, IsAll: false, selectedIndexes.Contains(index)));
            }

            return options;
        }
    }

    public IReadOnlyCollection<Room> SelectedRooms
    {
        get
        {
            if (rooms.Count == 0 || selectedIndexes.Count == 0)
            {
                return [];
            }

            return selectedIndexes.Order().Select(index => rooms[index]).ToArray();
        }
    }

    public bool SelectNext()
    {
        if (rooms.Count <= 1)
        {
            return false;
        }

        if (selectedIndexes.Count != 1)
        {
            selectedIndexes.Clear();
            selectedIndexes.Add(0);
            return true;
        }

        var selectedIndex = selectedIndexes.First();
        selectedIndexes.Clear();
        if (selectedIndex < rooms.Count - 1)
        {
            selectedIndexes.Add(selectedIndex + 1);
        }
        else
        {
            selectedIndexes.UnionWith(Enumerable.Range(0, rooms.Count));
        }

        return true;
    }

    public bool SelectAll()
    {
        if (rooms.Count <= 1 || IsAllSelected)
        {
            return false;
        }

        selectedIndexes.Clear();
        selectedIndexes.UnionWith(Enumerable.Range(0, rooms.Count));
        return true;
    }

    public bool SelectIndex(int index)
    {
        if (index < 0 || index >= rooms.Count)
        {
            return false;
        }

        if (selectedIndexes.Count == 1 && selectedIndexes.Contains(index))
        {
            return false;
        }

        selectedIndexes.Clear();
        selectedIndexes.Add(index);
        return true;
    }

    public bool SelectOption(MirrorTargetOption option) =>
        option.IsAll ? ToggleAll() : ToggleIndex(option.Index);

    private bool ToggleAll()
    {
        if (rooms.Count <= 1)
        {
            return false;
        }

        if (IsAllSelected)
        {
            selectedIndexes.Clear();
        }
        else
        {
            selectedIndexes.Clear();
            selectedIndexes.UnionWith(Enumerable.Range(0, rooms.Count));
        }

        return true;
    }

    private bool ToggleIndex(int index)
    {
        if (index < 0 || index >= rooms.Count)
        {
            return false;
        }

        if (!selectedIndexes.Add(index))
        {
            selectedIndexes.Remove(index);
        }

        return true;
    }
}
