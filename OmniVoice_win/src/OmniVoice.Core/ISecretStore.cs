namespace OmniVoice.Core;

public interface ISecretStore
{
    string? GetString(string account);
    void SetString(string account, string value);
    void DeleteString(string account);
}

public static class SecretAccounts
{
    public const string OpenAiCompatibleApiKey = "openai-compatible-api-key";
}

public static class SecretStoreFactory
{
    public static ISecretStore Create() =>
        OperatingSystem.IsWindows()
            ? new DpapiSecretStore()
            : new FileSecretStore();
}

internal sealed class FileSecretStore : ISecretStore
{
    private readonly string _directory;

    public FileSecretStore(string? directory = null)
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        _directory = directory ?? Path.Combine(appData, "OmniSpeak", "secrets");
        Directory.CreateDirectory(_directory);
    }

    public string? GetString(string account)
    {
        var path = PathFor(account);
        return File.Exists(path) ? File.ReadAllText(path) : null;
    }

    public void SetString(string account, string value) =>
        File.WriteAllText(PathFor(account), value);

    public void DeleteString(string account)
    {
        var path = PathFor(account);
        if (File.Exists(path))
            File.Delete(path);
    }

    private string PathFor(string account) =>
        Path.Combine(_directory, $"{Sanitize(account)}.secret");
    
    private static string Sanitize(string account) =>
        string.Concat(account.Select(c => Path.GetInvalidFileNameChars().Contains(c) ? '_' : c));
}

[System.Runtime.Versioning.SupportedOSPlatform("windows")]
internal sealed class DpapiSecretStore : ISecretStore
{
    private readonly string _directory;

    public DpapiSecretStore(string? directory = null)
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        _directory = directory ?? Path.Combine(appData, "OmniSpeak", "secrets");
        Directory.CreateDirectory(_directory);
    }

    public string? GetString(string account)
    {
        var path = PathFor(account);
        if (!File.Exists(path))
            return null;

        var protectedBytes = File.ReadAllBytes(path);
        var bytes = System.Security.Cryptography.ProtectedData.Unprotect(
            protectedBytes,
            null,
            System.Security.Cryptography.DataProtectionScope.CurrentUser);
        return System.Text.Encoding.UTF8.GetString(bytes);
    }

    public void SetString(string account, string value)
    {
        var bytes = System.Text.Encoding.UTF8.GetBytes(value);
        var protectedBytes = System.Security.Cryptography.ProtectedData.Protect(
            bytes,
            null,
            System.Security.Cryptography.DataProtectionScope.CurrentUser);
        File.WriteAllBytes(PathFor(account), protectedBytes);
    }

    public void DeleteString(string account)
    {
        var path = PathFor(account);
        if (File.Exists(path))
            File.Delete(path);
    }

    private string PathFor(string account) =>
        Path.Combine(_directory, $"{Sanitize(account)}.dpapi");

    private static string Sanitize(string account) =>
        string.Concat(account.Select(c => Path.GetInvalidFileNameChars().Contains(c) ? '_' : c));
}