using System.Diagnostics;
using System.IO;
using OmniVoice.Core;

namespace OmniVoice.App.Services;

public sealed class DictationCommandExecutor
{
    public sealed class ExecutionException(string message) : Exception(message);

    public void Execute(DictationCommand command)
    {
        if (command.Kind != DictationCommandActionKind.OpenApplication || command.AppName is null)
            return;

        if (!TryResolveExecutable(command.AppName, out var executable))
            throw new ExecutionException($"Could not find {command.AppName}.");

        Process.Start(new ProcessStartInfo(executable) { UseShellExecute = true });
    }

    internal static bool TryResolveExecutable(string name, out string executable)
    {
        executable = "";
        var normalized = NormalizeName(name);

        if (KnownExecutables.TryGetValue(normalized, out var known) && File.Exists(known))
        {
            executable = known;
            return true;
        }

        foreach (var candidate in PathCandidates(name))
        {
            if (File.Exists(candidate))
            {
                executable = candidate;
                return true;
            }
        }

        if (TryWhereExe(name, out var fromPath))
        {
            executable = fromPath;
            return true;
        }

        return false;
    }

    private static IEnumerable<string> PathCandidates(string name)
    {
        var displayName = name.Trim();
        if (displayName.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
            displayName = displayName[..^4];

        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

        yield return Path.Combine(programFiles, displayName, $"{displayName}.exe");
        yield return Path.Combine(programFilesX86, displayName, $"{displayName}.exe");
        yield return Path.Combine(localAppData, "Microsoft", "WindowsApps", $"{displayName}.exe");
        yield return Path.Combine(programFiles, "Google", "Chrome", "Application", "chrome.exe");
        yield return Path.Combine(programFilesX86, "Google", "Chrome", "Application", "chrome.exe");
        yield return Path.Combine(localAppData, "Programs", "Microsoft VS Code", "Code.exe");
        yield return Path.Combine(programFiles, "Microsoft VS Code", "Code.exe");
    }

    private static bool TryWhereExe(string name, out string executable)
    {
        executable = "";
        try
        {
            var psi = new ProcessStartInfo("where.exe", $"\"{name}\"")
            {
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var process = Process.Start(psi);
            if (process is null)
                return false;

            var output = process.StandardOutput.ReadToEnd().Trim();
            process.WaitForExit(2000);
            if (process.ExitCode != 0 || string.IsNullOrWhiteSpace(output))
                return false;

            executable = output.Split(Environment.NewLine, StringSplitOptions.RemoveEmptyEntries)[0].Trim();
            return File.Exists(executable);
        }
        catch
        {
            return false;
        }
    }

    private static string NormalizeName(string name)
    {
        var normalized = name.Trim().ToLowerInvariant();
        if (normalized.EndsWith(".exe"))
            normalized = normalized[..^4];
        if (normalized.EndsWith(" app"))
            normalized = normalized[..^4];
        return normalized;
    }

    private static readonly Dictionary<string, string> KnownExecutables = new(StringComparer.OrdinalIgnoreCase)
    {
        ["notepad"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "notepad.exe"),
        ["calculator"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "calc.exe"),
        ["calc"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "calc.exe"),
        ["explorer"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe"),
        ["cmd"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "cmd.exe"),
        ["powershell"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe"),
        ["chrome"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Google", "Chrome", "Application", "chrome.exe"),
        ["google chrome"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Google", "Chrome", "Application", "chrome.exe"),
        ["visual studio code"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Microsoft VS Code", "Code.exe"),
        ["vs code"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Microsoft VS Code", "Code.exe"),
        ["code"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Microsoft VS Code", "Code.exe"),
        ["outlook"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Microsoft Office", "root", "Office16", "OUTLOOK.EXE"),
        ["word"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Microsoft Office", "root", "Office16", "WINWORD.EXE"),
        ["slack"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "slack", "slack.exe"),
        ["terminal"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "WindowsApps", "wt.exe"),
        ["windows terminal"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "WindowsApps", "wt.exe"),
    };
}