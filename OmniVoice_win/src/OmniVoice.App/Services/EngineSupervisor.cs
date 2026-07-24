using System.Diagnostics;
using System.IO;
using OmniVoice.Core;

namespace OmniVoice.App.Services;

public sealed class EngineSupervisor
{
    public static EngineSupervisor Shared { get; } = new();

    private readonly EngineClient _client = new();
    private Process? _process;
    private bool _didAttemptStart;

    /// <summary>
    /// Execution device handed to the engine on launch. Set from preferences
    /// before starting; the engine still falls back to CPU if CUDA can't load.
    /// </summary>
    public AsrDeviceKind AsrDevice { get; set; } = AsrDeviceKind.Auto;

    public async Task<EngineStartResult> StartIfNeededAsync(CancellationToken ct = default)
    {
        if (await IsHealthyAsync(ct))
            return EngineStartResult.AlreadyOnline;

        if (_process is { HasExited: false })
            return await WaitForHealthAsync(ct);

        if (_didAttemptStart)
            return EngineStartResult.Unavailable("Engine is offline. Check engine.log in %LOCALAPPDATA%\\OmniSpeak.");

        _didAttemptStart = true;
        var launcher = FindLauncher();
        if (launcher is null)
            return EngineStartResult.Unavailable("Engine launcher script was not found.");

        try
        {
            LaunchEngine(launcher);
        }
        catch (Exception ex)
        {
            return EngineStartResult.Failed($"Engine launch failed: {ex.Message}");
        }

        return await WaitForHealthAsync(ct);
    }

    public async Task<EngineStartResult> RestartAsync(CancellationToken ct = default)
    {
        _didAttemptStart = false;
        if (_process is { HasExited: false })
        {
            _process.Kill(entireProcessTree: true);
            await _process.WaitForExitAsync(ct);
        }

        _process = null;
        return await StartIfNeededAsync(ct);
    }

    public void StopStartedProcess()
    {
        if (_process is { HasExited: false })
            _process.Kill(entireProcessTree: true);
        _process = null;
    }

    private void LaunchEngine(string launcherPath)
    {
        var supportDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OmniSpeak");
        Directory.CreateDirectory(supportDir);

        var modelRoot = Path.Combine(supportDir, "models");
        var dataDir = Path.Combine(supportDir, "engine-data");
        var logPath = Path.Combine(supportDir, "engine.log");
        Directory.CreateDirectory(modelRoot);
        Directory.CreateDirectory(dataDir);
        File.AppendAllText(logPath, $"\n--- OmniSpeak engine launch {DateTime.Now:u} ---\n");

        var repoRoot = FindRepoRoot();
        var startInfo = new ProcessStartInfo
        {
            FileName = launcherPath.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase) ? "powershell" : launcherPath,
            Arguments = launcherPath.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase)
                ? $"-ExecutionPolicy Bypass -File \"{launcherPath}\""
                : "",
            WorkingDirectory = repoRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };

        startInfo.Environment["OMNIVOICE_APP_SUPPORT_DIR"] = supportDir;
        startInfo.Environment["OMNIVOICE_MODEL_ROOT"] = modelRoot;
        startInfo.Environment["OMNIVOICE_PARAKEET_MODEL_DIR"] = Path.Combine(modelRoot, "parakeet-tdt");
        startInfo.Environment["OMNIVOICE_MOONSHINE_MODEL_DIR"] = Path.Combine(modelRoot, "moonshine-base-en");
        startInfo.Environment["OMNIVOICE_CANARY_MODEL_DIR"] = Path.Combine(modelRoot, "canary-qwen-2.5b");
        startInfo.Environment["OMNIVOICE_SENSEVOICE_MODEL_DIR"] = Path.Combine(modelRoot, "sensevoice-small-funasr");
        startInfo.Environment["OMNIVOICE_WHISPERX_PYANNOTE_DIR"] = Path.Combine(modelRoot, "whisperx-pyannote");
        startInfo.Environment["OMNIVOICE_ASR_DEVICE"] =
            Environment.GetEnvironmentVariable("OMNIVOICE_ASR_DEVICE") ?? AsrDevice.WireValue();
        startInfo.Environment["OMNIVOICE_ENGINE_DATA_DIR"] = dataDir;
        startInfo.Environment["OMNIVOICE_DESKTOP_APP_PATH"] = Environment.ProcessPath ?? "";
        startInfo.Environment["OMNIVOICE_INSTALL_ASR"] = Environment.GetEnvironmentVariable("OMNIVOICE_INSTALL_ASR") ?? "1";

        _process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        _process.OutputDataReceived += (_, e) => { if (e.Data is not null) File.AppendAllText(logPath, e.Data + Environment.NewLine); };
        _process.ErrorDataReceived += (_, e) => { if (e.Data is not null) File.AppendAllText(logPath, e.Data + Environment.NewLine); };
        _process.Start();
        _process.BeginOutputReadLine();
        _process.BeginErrorReadLine();
    }

    private async Task<EngineStartResult> WaitForHealthAsync(CancellationToken ct)
    {
        for (var i = 0; i < 120; i++)
        {
            if (await IsHealthyAsync(ct))
                return EngineStartResult.Started;
            await Task.Delay(500, ct);
        }

        var logPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OmniSpeak",
            "engine.log");
        return EngineStartResult.StillStarting(logPath);
    }

    private async Task<bool> IsHealthyAsync(CancellationToken ct)
    {
        try
        {
            await _client.HealthAsync(ct);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static string? FindLauncher()
    {
        var repoRoot = FindRepoRoot();
        var candidates = new[]
        {
            Path.Combine(repoRoot, "scripts", "run-engine.ps1"),
            Path.Combine(repoRoot, "scripts", "run-engine.bat"),
        };

        return candidates.FirstOrDefault(File.Exists);
    }

    private static string FindRepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            if (Directory.Exists(Path.Combine(dir.FullName, "engine")))
                return dir.FullName;
            dir = dir.Parent;
        }

        return Directory.GetCurrentDirectory();
    }
}

public enum EngineStartResultKind
{
    AlreadyOnline,
    Started,
    StillStarting,
    Unavailable,
    Failed,
}

public sealed record EngineStartResult(EngineStartResultKind Kind, string Detail)
{
    public static EngineStartResult AlreadyOnline => new(EngineStartResultKind.AlreadyOnline, "Engine online");
    public static EngineStartResult Started => new(EngineStartResultKind.Started, "Engine started");
    public static EngineStartResult StillStarting(string logPath) => new(EngineStartResultKind.StillStarting, $"Engine is starting. Log: {logPath}");
    public static EngineStartResult Unavailable(string message) => new(EngineStartResultKind.Unavailable, message);
    public static EngineStartResult Failed(string message) => new(EngineStartResultKind.Failed, message);
}