namespace Ping.Windows.Core.Models;

public static class DisplayText
{
    public static string NormalizeWhitespace(string value) =>
        string.Join(" ", (value ?? string.Empty).Split(WhitespaceSeparators, StringSplitOptions.RemoveEmptyEntries));

    private static readonly char[] WhitespaceSeparators =
    [
        ' ',
        '\t',
        '\r',
        '\n',
        '\f',
        '\v'
    ];
}
