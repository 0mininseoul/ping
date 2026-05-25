namespace Ping.Windows.Core.Backend;

public sealed class SupabaseSessionExpiredException : Exception
{
    public SupabaseSessionExpiredException(string userId, Exception innerException)
        : base($"Supabase anonymous session expired for user {userId}.", innerException)
    {
        UserId = userId;
    }

    public string UserId { get; }
}
