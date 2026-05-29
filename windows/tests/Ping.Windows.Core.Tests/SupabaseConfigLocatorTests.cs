using Ping.Windows.Core.Backend;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class SupabaseConfigLocatorTests
{
    private const string UserPath = @"C:\Users\ping\AppData\Local\Ping\Supabase.json";
    private const string BundledPath = @"C:\Program Files\WindowsApps\Ping\Supabase.json";

    [Fact]
    public void Prefers_user_override_when_it_exists()
    {
        var resolved = SupabaseConfigLocator.Resolve(UserPath, BundledPath, _ => true);

        Assert.Equal(UserPath, resolved);
    }

    [Fact]
    public void Falls_back_to_bundled_config_when_user_override_is_missing()
    {
        var resolved = SupabaseConfigLocator.Resolve(UserPath, BundledPath, path => path == BundledPath);

        Assert.Equal(BundledPath, resolved);
    }

    [Fact]
    public void Returns_user_path_when_no_config_exists_yet()
    {
        var resolved = SupabaseConfigLocator.Resolve(UserPath, BundledPath, _ => false);

        Assert.Equal(UserPath, resolved);
    }

    [Fact]
    public void Default_candidate_paths_point_at_ping_local_dir_and_app_base()
    {
        Assert.EndsWith(Path.Combine("Ping", "Supabase.json"), SupabaseConfigLocator.UserConfigPath());
        Assert.Equal(
            Path.Combine(AppContext.BaseDirectory, "Supabase.json"),
            SupabaseConfigLocator.BundledConfigPath());
    }
}
