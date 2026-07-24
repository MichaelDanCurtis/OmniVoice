using OmniVoice.Core;

namespace OmniVoice.Core.Tests;

public class EngineLauncherLocatorTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("omnispeak-locator-").FullName;

    public void Dispose() => Directory.Delete(_root, recursive: true);

    private string MakeDir(string name)
    {
        var path = Path.Combine(_root, name);
        Directory.CreateDirectory(path);
        return path;
    }

    [Fact]
    public void PrefersBundledEngineExeNextToTheApp()
    {
        var appDir = MakeDir("app");
        var bundled = Path.Combine(appDir, EngineLauncherLocator.BundledEngineFileName);
        File.WriteAllText(bundled, "exe");
        var repoRoot = MakeDir("repo");
        Directory.CreateDirectory(Path.Combine(repoRoot, "scripts"));
        File.WriteAllText(Path.Combine(repoRoot, "scripts", "run-engine.ps1"), "dev");

        var resolved = EngineLauncherLocator.Resolve(appDir, repoRoot);

        Assert.Equal(bundled, resolved);
    }

    [Fact]
    public void FallsBackToDevLauncherScriptsInOrder()
    {
        var appDir = MakeDir("app");
        var repoRoot = MakeDir("repo");
        Directory.CreateDirectory(Path.Combine(repoRoot, "scripts"));
        var ps1 = Path.Combine(repoRoot, "scripts", "run-engine.ps1");
        File.WriteAllText(ps1, "dev");

        Assert.Equal(ps1, EngineLauncherLocator.Resolve(appDir, repoRoot));
    }

    [Fact]
    public void FallsBackToBatWhenNoPs1()
    {
        var appDir = MakeDir("app");
        var repoRoot = MakeDir("repo");
        Directory.CreateDirectory(Path.Combine(repoRoot, "scripts"));
        var bat = Path.Combine(repoRoot, "scripts", "run-engine.bat");
        File.WriteAllText(bat, "dev");

        Assert.Equal(bat, EngineLauncherLocator.Resolve(appDir, repoRoot));
    }

    [Fact]
    public void ReturnsNullWhenNothingIsAvailable()
    {
        Assert.Null(EngineLauncherLocator.Resolve(MakeDir("app"), MakeDir("repo")));
    }
}
