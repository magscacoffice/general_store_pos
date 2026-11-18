using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace KhanBabaPos.Wpf.Services;

/// <summary>
/// Offline Windows-only staff authentication. Credentials are PBKDF2-hashed and
/// the complete local store is protected with DPAPI CurrentUser. No DB schema
/// or Android/Firebase authentication is changed.
/// </summary>
public sealed class AccessService
{
    private static AccessService? _processAccess;

    public static void RegisterProcess(AccessService access) =>
        Interlocked.Exchange(ref _processAccess, access ?? throw new ArgumentNullException(nameof(access)));

    public static void ClearProcess(AccessService access) =>
        Interlocked.CompareExchange(ref _processAccess, null, access);

    public static void RequireCurrentAdmin() => RequireCurrentRole(AccessRole.Admin);

    public static void RequireCurrentRole(params AccessRole[] roles)
    {
        var access = Volatile.Read(ref _processAccess)
            ?? throw new UnauthorizedAccessException("Windows access session is not initialized. Login required.");
        access.RequireRole(roles);
    }

    private const int CurrentHashVersion = 1;
    private const int Iterations = 310_000;
    private const int SaltBytes = 16;
    private const int HashBytes = 32;
    private const int MaxFailedAttempts = 5;
    private static readonly TimeSpan LockoutDuration = TimeSpan.FromSeconds(30);
    private readonly TimeSpan _sessionLifetime;
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("KhanBabaPOS.Windows.LocalAccess.v1");
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false,
        Converters = { new JsonStringEnumConverter() }
    };

    private readonly string _storePath;
    private readonly object _gate = new();
    private LocalAccessStore? _store;
    private AccessSession? _session;

    public AccessService(string? storePath = null, TimeSpan? sessionLifetime = null)
    {
        _sessionLifetime = sessionLifetime ?? TimeSpan.FromMinutes(30);
        if (_sessionLifetime <= TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(sessionLifetime));
        _storePath = storePath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "KhanBabaPOS", "Security", "users.dat");
    }

    public bool RequiresFirstRunSetup => ReadStore().Users.Count == 0;
    public AccessSession? CurrentSession
    {
        get
        {
            lock (_gate)
            {
                if (_session is null || _session.ExpiresAtUtc <= DateTimeOffset.UtcNow)
                {
                    _session = null;
                    return null;
                }
                return _session;
            }
        }
    }

    public AccessSession ProvisionFirstAdmin(string username, string displayName, string password)
    {
        ValidateIdentity(username, displayName);
        ValidatePassword(password);
        lock (_gate)
        {
            var store = ReadStore();
            if (store.Users.Count != 0)
                throw new InvalidOperationException("Admin pehle se provision hai. Login karein.");
            var user = NewUser(username, displayName, AccessRole.Admin, password);
            store.Users.Add(user);
            AddAudit(store, user.Id, user.Username, "first_admin_provisioned");
            WriteStore(store);
            return _session = CreateSession(user);
        }
    }

    public AccessSession Authenticate(string username, string password)
    {
        if (string.IsNullOrWhiteSpace(username) || password is null)
            throw new UnauthorizedAccessException("Username ya password durust nahi.");
        lock (_gate)
        {
            var store = ReadStore();
            var user = store.Users.FirstOrDefault(x =>
                string.Equals(x.Username, username.Trim(), StringComparison.OrdinalIgnoreCase));
            var now = DateTimeOffset.UtcNow;
            if (user is null || !user.Enabled)
            {
                AddAudit(store, user?.Id ?? "", username.Trim(), "login_denied");
                WriteStore(store);
                throw new UnauthorizedAccessException("Username ya password durust nahi.");
            }
            if (user.LockedUntilUtc is { } until && until > now)
                throw new UnauthorizedAccessException($"Account temporarily locked. {Math.Ceiling((until - now).TotalSeconds)} seconds baad dobara koshish karein.");

            if (user.HashVersion != CurrentHashVersion || user.Iterations < 100_000 || user.Iterations > 2_000_000)
                throw new InvalidDataException("Credential hash version ya parameters supported nahi hain. Admin se password reset karwayein.");
            var supplied = Derive(password, Convert.FromBase64String(user.Salt), user.Iterations);
            var expected = Convert.FromBase64String(user.PasswordHash);
            if (!CryptographicOperations.FixedTimeEquals(supplied, expected))
            {
                user.FailedAttempts++;
                if (user.FailedAttempts >= MaxFailedAttempts)
                {
                    user.FailedAttempts = 0;
                    user.LockedUntilUtc = now.Add(LockoutDuration);
                }
                AddAudit(store, user.Id, user.Username, "login_failed");
                WriteStore(store);
                throw new UnauthorizedAccessException("Username ya password durust nahi.");
            }

            user.FailedAttempts = 0;
            user.LockedUntilUtc = null;
            user.LastLoginUtc = now;
            AddAudit(store, user.Id, user.Username, "login_succeeded");
            WriteStore(store);
            return _session = CreateSession(user);
        }
    }

    public IReadOnlyList<StaffAccount> ListStaff()
    {
        RequireAdmin();
        return ReadStore().Users
            .OrderBy(x => x.Username, StringComparer.OrdinalIgnoreCase)
            .Select(ToPublic)
            .ToArray();
    }

    public StaffAccount CreateStaff(string username, string displayName, string password, AccessRole role)
    {
        RequireAdmin();
        if (role is not (AccessRole.Admin or AccessRole.Salesman))
            throw new ArgumentOutOfRangeException(nameof(role));
        ValidateIdentity(username, displayName);
        ValidatePassword(password);
        lock (_gate)
        {
            var store = ReadStore();
            if (store.Users.Any(x => string.Equals(x.Username, username.Trim(), StringComparison.OrdinalIgnoreCase)))
                throw new InvalidOperationException("Yeh username pehle se mojood hai.");
            var user = NewUser(username, displayName, role, password);
            store.Users.Add(user);
            AddAudit(store, CurrentSession!.UserId, CurrentSession.Username, "staff_created:" + user.Username);
            WriteStore(store);
            return ToPublic(user);
        }
    }

    public void ResetPassword(string userId, string newPassword)
    {
        RequireAdmin();
        ValidatePassword(newPassword);
        lock (_gate)
        {
            var store = ReadStore();
            var user = store.Users.SingleOrDefault(x => x.Id == userId)
                ?? throw new InvalidOperationException("Staff account nahi mila.");
            SetPassword(user, newPassword);
            user.FailedAttempts = 0;
            user.LockedUntilUtc = null;
            AddAudit(store, CurrentSession!.UserId, CurrentSession.Username, "password_reset:" + user.Username);
            WriteStore(store);
        }
    }

    public void SetEnabled(string userId, bool enabled)
    {
        RequireAdmin();
        lock (_gate)
        {
            var store = ReadStore();
            var user = store.Users.SingleOrDefault(x => x.Id == userId)
                ?? throw new InvalidOperationException("Staff account nahi mila.");
            if (!enabled && user.Role == AccessRole.Admin && user.Enabled &&
                store.Users.Count(x => x.Enabled && x.Role == AccessRole.Admin) <= 1)
                throw new InvalidOperationException("Aakhri active Admin ko disable nahi kiya ja sakta.");
            if (user.Id == CurrentSession!.UserId && !enabled)
                throw new InvalidOperationException("Apna active account disable nahi kar sakte.");
            user.Enabled = enabled;
            if (!enabled) { user.FailedAttempts = 0; user.LockedUntilUtc = null; }
            AddAudit(store, CurrentSession.UserId, CurrentSession.Username,
                (enabled ? "staff_enabled:" : "staff_disabled:") + user.Username);
            WriteStore(store);
        }
    }

    public void RequireAdmin() => RequireRole(AccessRole.Admin);

    public void RequireRole(params AccessRole[] allowedRoles)
    {
        lock (_gate)
        {
            var session = CurrentSession;
            if (session is null)
                throw new UnauthorizedAccessException("Session expire ho gaya. Dobara login karein.");
            if (!allowedRoles.Contains(session.Role))
                throw new UnauthorizedAccessException("Is action ke liye Admin permission zaroori hai.");
            session.LastActivityUtc = DateTimeOffset.UtcNow;
            session.ExpiresAtUtc = session.LastActivityUtc.Add(_sessionLifetime);
        }
    }

    public void Logout()
    {
        lock (_gate)
        {
            if (_session is not null)
            {
                var store = ReadStore();
                AddAudit(store, _session.UserId, _session.Username, "logout");
                WriteStore(store);
            }
            _session = null;
        }
    }

    private LocalAccessStore ReadStore()
    {
        lock (_gate)
        {
            if (_store is not null) return _store;
            if (!File.Exists(_storePath)) return _store = new LocalAccessStore();
            var encrypted = File.ReadAllBytes(_storePath);
            var clear = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
            _store = JsonSerializer.Deserialize<LocalAccessStore>(clear, JsonOptions)
                ?? throw new InvalidDataException("Local access store corrupt hai.");
            return _store;
        }
    }

    private void WriteStore(LocalAccessStore store)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_storePath)!);
        var clear = JsonSerializer.SerializeToUtf8Bytes(store, JsonOptions);
        var encrypted = ProtectedData.Protect(clear, Entropy, DataProtectionScope.CurrentUser);
        var temp = _storePath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        File.WriteAllBytes(temp, encrypted);
        File.Move(temp, _storePath, true);
        _store = store;
    }

    private static LocalUser NewUser(string username, string displayName, AccessRole role, string password)
    {
        var user = new LocalUser
        {
            Id = Guid.NewGuid().ToString("N"),
            Username = username.Trim(),
            DisplayName = displayName.Trim(),
            Role = role,
            Enabled = true,
            CreatedAtUtc = DateTimeOffset.UtcNow
        };
        SetPassword(user, password);
        return user;
    }

    private static void SetPassword(LocalUser user, string password)
    {
        var salt = RandomNumberGenerator.GetBytes(SaltBytes);
        user.HashVersion = CurrentHashVersion;
        user.Iterations = Iterations;
        user.Salt = Convert.ToBase64String(salt);
        user.PasswordHash = Convert.ToBase64String(Derive(password, salt, Iterations));
    }

    private static byte[] Derive(string password, byte[] salt, int iterations) =>
        Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, HashBytes);

    private AccessSession CreateSession(LocalUser user)
    {
        var now = DateTimeOffset.UtcNow;
        return new AccessSession(user.Id, user.Username, user.DisplayName, user.Role,
            now, now, now.Add(_sessionLifetime));
    }

    private static StaffAccount ToPublic(LocalUser user) =>
        new(user.Id, user.Username, user.DisplayName, user.Role, user.Enabled, user.CreatedAtUtc, user.LastLoginUtc);

    private static void ValidateIdentity(string username, string displayName)
    {
        if (string.IsNullOrWhiteSpace(username) || username.Trim().Length > 64 ||
            username.Any(char.IsControl))
            throw new ArgumentException("Username 1 se 64 characters ka hona chahiye.");
        if (string.IsNullOrWhiteSpace(displayName) || displayName.Trim().Length > 100)
            throw new ArgumentException("Staff ka naam 1 se 100 characters ka hona chahiye.");
    }

    private static void ValidatePassword(string password)
    {
        if (password is null || password.Length < 10 || password.Length > 256)
            throw new ArgumentException("Password kam az kam 10 aur zyada se zyada 256 characters ka hona chahiye.");
    }

    private static void AddAudit(LocalAccessStore store, string userId, string username, string action)
    {
        store.Audit.Add(new AccessAuditEvent(DateTimeOffset.UtcNow, userId, username, action));
        if (store.Audit.Count > 500) store.Audit.RemoveRange(0, store.Audit.Count - 500);
    }

    private sealed class LocalAccessStore
    {
        public List<LocalUser> Users { get; set; } = [];
        public List<AccessAuditEvent> Audit { get; set; } = [];
    }

    private sealed class LocalUser
    {
        public string Id { get; set; } = "";
        public string Username { get; set; } = "";
        public string DisplayName { get; set; } = "";
        public AccessRole Role { get; set; }
        public bool Enabled { get; set; }
        public int HashVersion { get; set; }
        public int Iterations { get; set; }
        public string Salt { get; set; } = "";
        public string PasswordHash { get; set; } = "";
        public int FailedAttempts { get; set; }
        public DateTimeOffset? LockedUntilUtc { get; set; }
        public DateTimeOffset CreatedAtUtc { get; set; }
        public DateTimeOffset? LastLoginUtc { get; set; }
    }
}

public enum AccessRole { Admin, Salesman }

public sealed class AccessSession(
    string userId, string username, string displayName, AccessRole role,
    DateTimeOffset createdAtUtc, DateTimeOffset lastActivityUtc, DateTimeOffset expiresAtUtc)
{
    public string UserId { get; } = userId;
    public string Username { get; } = username;
    public string DisplayName { get; } = displayName;
    public AccessRole Role { get; } = role;
    public DateTimeOffset CreatedAtUtc { get; } = createdAtUtc;
    public DateTimeOffset LastActivityUtc { get; internal set; } = lastActivityUtc;
    public DateTimeOffset ExpiresAtUtc { get; internal set; } = expiresAtUtc;
}

public sealed record StaffAccount(
    string Id, string Username, string DisplayName, AccessRole Role, bool Enabled,
    DateTimeOffset CreatedAtUtc, DateTimeOffset? LastLoginUtc);

public sealed record AccessAuditEvent(
    DateTimeOffset AtUtc, string UserId, string Username, string Action);
