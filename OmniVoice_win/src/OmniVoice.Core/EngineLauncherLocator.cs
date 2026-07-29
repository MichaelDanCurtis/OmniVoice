namespace OmniVoice.Core;

/// <summary>
/// Decides how the desktop app should start the local engine.
///
/// A packaged install bundles the PyInstaller-frozen engine
/// (<see cref="BundledEngineFileName"/>) inside the single-file OmniSpeak.exe;
/// .NET extracts it next to the app at first run, and launching that binary
/// directly needs no Python, no venv, and no scripts. A source checkout has no
/// bundled engine, so development falls back to the launcher scripts.
/// </summary>
public static class EngineLauncherLocator
{
    public const string BundledEngineFileName = "omnispeak-engine.exe";

    /// <summary>
    /// Returns the path to launch: the bundled engine exe when present in
    /// <paramref name="appBaseDirectory"/>, else the first dev launcher script
    /// under <paramref name="repoRoot"/>/scripts, else null.
    /// </summary>
    public static string? Resolve(string appBaseDirectory, string repoRoot)
    {
        var bundled = Path.Combine(appBaseDirectory, BundledEngineFileName);
        if (File.Exists(bundled))
            return bundled;

        var candidates = new[]
        {
            Path.Combine(repoRoot, "scripts", "run-engine.ps1"),
            Path.Combine(repoRoot, "scripts", "run-engine.bat"),
        };
        return candidates.FirstOrDefault(File.Exists);
    }
}
