<#
.SYNOPSIS
    Load a scenario's cast into PDC's Keycloak, from Windows.

.DESCRIPTION
    Creates the scenario's users in the 'pdc' realm and maps each to the PDC
    roles the roster names, so the whole cast can log in and the RBAC workshops
    work without hand-creating users in the Keycloak console.

    This is the Windows counterpart to load-pdc-users.sh. The bash version runs
    ON the lab VM and drives kcadm.sh inside the Keycloak container; that is not
    reachable from a Windows host, so this one talks to Keycloak's Admin REST
    API over HTTPS instead. Same roster, same role matching, same options - no
    Docker, no SSH, no shell on the VM.

    Idempotent: an existing user is kept, with password and roles re-applied.

.PARAMETER Scenario
    CSCU / RETAIL / HEALTH / MFG, or ALL for every vertical.

.PARAMETER BaseUrl
    PDC server root, e.g. https://pentaho.io  (NOT the Keycloak realm URL - the
    script appends /keycloak itself). Use the vhost, not a bare IP: PDC's proxy
    routes by hostname.

.PARAMETER AdminPassword
    Keycloak master-realm admin password. Prompted for securely if omitted.

.PARAMETER Password
    Override every user's password with this one value.

.PARAMETER DryRun
    Show the plan; change nothing.

.PARAMETER ListRoles
    Dump the realm's roles and groups, then exit. Use this when a roster role
    does not match, and extend $RoleAliases below.

.PARAMETER FixPolicy
    Relax the realm password policy to length(8) first. LAB ONLY - policies such
    as specialChars(1) reject the simple training passwords.

.PARAMETER SkipTlsCheck
    Accept the lab VM's self-signed certificate.

.EXAMPLE
    .\load-pdc-users.ps1 -Scenario CSCU
.EXAMPLE
    .\load-pdc-users.ps1 -Scenario ALL -BaseUrl https://pentaho.io -SkipTlsCheck
.EXAMPLE
    .\load-pdc-users.ps1 -Scenario CSCU -DryRun
.EXAMPLE
    .\load-pdc-users.ps1 -ListRoles
#>
[CmdletBinding()]
param(
    [string] $Scenario,
    [string] $BaseUrl = 'https://pentaho.io',
    [string] $Realm = 'pdc',
    [string] $AdminUser = 'admin',
    [System.Security.SecureString] $AdminPassword,
    [string] $Password,
    [string] $RosterPath,
    [switch] $DryRun,
    [switch] $ListRoles,
    [switch] $FixPolicy,
    [switch] $SkipTlsCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

# Windows PowerShell 5.1 defaults to TLS 1.0 for some stacks; Keycloak wants 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------- output ----
function Write-Ok   { param($m) Write-Host ("  [ok] " + $m) -ForegroundColor Green }
function Write-Warn { param($m) Write-Host ("  [!]  " + $m) -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host ("  [x]  " + $m) -ForegroundColor Red }
function Stop-Now   { param($m) Write-Err $m; exit 1 }

# Six named checkpoints, so a run that fails tells you WHERE it stopped and what
# that stage proves. Each prints what it is about to do and, on the way out, what
# to try if it did not work - the failures here are nearly always environmental
# (wrong base URL, self-signed cert, realm password policy) rather than code.
$script:CheckpointTotal = 6
function Write-Checkpoint {
    param([int] $Number, [string] $Title, [string] $Note)
    Write-Host ""
    Write-Host ("  == CHECKPOINT $Number/$script:CheckpointTotal : $Title ==") -ForegroundColor Cyan
    if ($Note) { Write-Host ("     " + $Note) -ForegroundColor DarkGray }
}
function Write-Hint {
    param([string] $m)
    Write-Host ("     hint: " + $m) -ForegroundColor DarkGray
}

# Training lab defaults. Fictional scenarios; never production values.
$DefaultPassword = @{
    CSCU = 'copperstate'; RETAIL = 'canyontrail'
    HEALTH = 'lakeshore'; MFG = 'cascade'
}

# Roster display-name -> realm role, when snake_casing alone is not enough.
# Left side is the NORMALIZED roster name, right side the realm role to try.
$RoleAliases = @{
    catalog_admin        = 'admin'
    administrator        = 'admin'
    system_administrator = 'admin'
}

function ConvertTo-NormalName {
    # "Data Steward" -> data_steward. Matches the bash version's normalization.
    param([string] $Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $s = $Text.ToLowerInvariant()
    $s = [regex]::Replace($s, '[^a-z0-9]+', '_')
    return $s.Trim('_')
}

# ------------------------------------------------------------- transport ----
if ($SkipTlsCheck) {
    # Lab VMs use self-signed certs. PS7 has -SkipCertificateCheck; 5.1 does not,
    # so fall back to a process-wide callback. Scoped to this process only.
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        Add-Type -TypeDefinition @'
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class PdcCertPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate c, WebRequest r, int p) { return true; }
}
'@ -ErrorAction SilentlyContinue
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object PdcCertPolicy
    }
}

$script:CommonArgs = @{}
if ($SkipTlsCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
    $script:CommonArgs['SkipCertificateCheck'] = $true
}

# The app appends /keycloak and /api/public itself, and so do we: callers give
# the SERVER ROOT. Tolerate someone pasting the full realm URL by trimming back.
$root = $BaseUrl.TrimEnd('/')
$root = [regex]::Replace($root, '/keycloak(/realms/[^/]+)?/?$', '')
$KcBase = "$root/keycloak"
$AdminApi = "$KcBase/admin/realms/$Realm"

function Get-AdminToken {
    param([string] $User, [System.Security.SecureString] $Secret)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret))
    $body = @{
        client_id  = 'admin-cli'
        grant_type = 'password'
        username   = $User
        password   = $plain
    }
    try {
        $r = Invoke-RestMethod -Method Post -Uri "$KcBase/realms/master/protocol/openid-connect/token" `
                               -Body $body -ContentType 'application/x-www-form-urlencoded' @script:CommonArgs
        return $r.access_token
    } catch {
        Stop-Now ("Could not get an admin token from $KcBase. " +
                  "Check the base URL (use the vhost, not an IP), the admin account, " +
                  "and -SkipTlsCheck for a self-signed cert. Detail: " + $_.Exception.Message)
    }
}

function Invoke-Kc {
    # Thin wrapper so every call carries the bearer token and TLS settings.
    param(
        [string] $Method = 'Get',
        [Parameter(Mandatory)] [string] $Path,   # relative to the realm admin API
        $Body,
        [switch] $Raw                            # return $null instead of throwing on 404
    )
    $uri = if ($Path -match '^https?://') { $Path } else { "$AdminApi$Path" }
    $args = @{ Method = $Method; Uri = $uri; Headers = @{ Authorization = "Bearer $script:Token" } }
    if ($null -ne $Body) {
        $args['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress)
        $args['ContentType'] = 'application/json'
    }
    try {
        return Invoke-RestMethod @args @script:CommonArgs
    } catch {
        if ($Raw) { return $null }
        throw
    }
}

# ------------------------------------------------------------ credentials ---
Write-Checkpoint 1 "Connect to Keycloak" ("Proves the base URL, the admin account and TLS are all good " +
    "BEFORE anything is written. Nothing is changed by this step.")
Write-Host ("     server: $KcBase")
if (-not $AdminPassword) {
    $AdminPassword = Read-Host -AsSecureString ("Keycloak admin password for '$AdminUser' (master realm)")
}
$script:Token = Get-AdminToken -User $AdminUser -Secret $AdminPassword
Write-Ok "admin token obtained"
Write-Hint "if this fails: use the VHOST not an IP, add -SkipTlsCheck for a self-signed cert, check -AdminUser" 

# ------------------------------------------------------------- list-roles ---
if ($ListRoles) {
    Write-Host ""
    Write-Host ("  Realm '$Realm' roles:") -ForegroundColor Cyan
    Invoke-Kc -Path '/roles' | ForEach-Object { Write-Host ("    " + $_.name) }
    Write-Host ("  Realm '$Realm' groups:") -ForegroundColor Cyan
    Invoke-Kc -Path '/groups' | ForEach-Object { Write-Host ("    " + $_.name) }
    Write-Host ""
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Scenario)) {
    Stop-Now "Pass -Scenario (CSCU/RETAIL/HEALTH/MFG), -Scenario ALL, or -ListRoles."
}
$Scenario = $Scenario.ToUpperInvariant()

# ----------------------------------------------------------------- roster ---
# Preferred: the consolidated CSV (explicit Username + per-user Lab_Password,
# all four verticals) - kept even in a sparse checkout, because cone mode
# retains top-level courseware/ files. Fallback: the Workshop-00 roster.
$consolidated = 'courseware\PDC-Users-All-Scenarios.csv'
if ($RosterPath) {
    $csvPath = $RosterPath
} elseif (Test-Path -LiteralPath $consolidated) {
    $csvPath = $consolidated
} elseif ($Scenario -ne 'ALL') {
    $csvPath = "courseware\$Scenario\Platform\Workshop-00-Preflight\assets\users.csv"
} else {
    Stop-Now "ALL needs the consolidated roster: $consolidated"
}
if (-not (Test-Path -LiteralPath $csvPath)) {
    Stop-Now "Roster not found: $csvPath (is the $Scenario vertical checked out?)"
}

$defPass = ''
if ($DefaultPassword.ContainsKey($Scenario)) { $defPass = $DefaultPassword[$Scenario] }

Write-Checkpoint 2 "Read the roster" ("The cast list is the source of truth for usernames, roles and " +
    "per-user lab passwords. Still no writes.")
Write-Host ("     roster: $csvPath")
if ($DryRun) { Write-Warn "DRY RUN - nothing will be changed" }

# Import-Csv handles quoted commas natively, so no hand-rolled parsing.
$rows = @()
foreach ($row in (Import-Csv -LiteralPath $csvPath)) {
    $cols  = $row.PSObject.Properties.Name
    $email = ''
    if ($cols -contains 'Email') { $email = ('' + $row.Email).Trim() }
    if ([string]::IsNullOrWhiteSpace($email)) { continue }

    if (($cols -contains 'Scenario') -and $Scenario -ne 'ALL') {
        if (('' + $row.Scenario).Trim().ToUpperInvariant() -ne $Scenario) { continue }
    }

    $user = ''
    if ($cols -contains 'Username') { $user = ('' + $row.Username).Trim().ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($user)) { $user = $email.Split('@')[0].ToLowerInvariant() }

    $first = ''
    if ($cols -contains 'First_Name') { $first = ('' + $row.First_Name).Trim() }
    if ([string]::IsNullOrWhiteSpace($first)) {
        $first = (Get-Culture).TextInfo.ToTitleCase($user.Split('.')[0])
    }
    $last = ''
    if ($cols -contains 'Last_Name') { $last = ('' + $row.Last_Name).Trim() }
    if ([string]::IsNullOrWhiteSpace($last) -and $user.Contains('.')) {
        $last = (Get-Culture).TextInfo.ToTitleCase($user.Split('.')[1])
    }
    $roles = ''
    if ($cols -contains 'PDC_Roles') { $roles = ('' + $row.PDC_Roles).Trim() }
    $pw = ''
    if ($cols -contains 'Lab_Password') { $pw = ('' + $row.Lab_Password).Trim() }

    $rows += [pscustomobject]@{
        Username = $user; Email = $email; First = $first
        Last = $last; Roles = $roles; Password = $pw
    }
}

if ($rows.Count -eq 0) {
    Write-Hint "a consolidated roster filters on a 'Scenario' column - check the id matches (CSCU/RETAIL/HEALTH/MFG)"
    Stop-Now "No users matched scenario '$Scenario' in $csvPath"
}
Write-Ok ("" + $rows.Count + " user(s) to load")

# ------------------------------------------------------- password policy ----
Write-Checkpoint 3 "Check the realm password policy" ("Lab rosters use simple training passwords " +
    "(copperstate etc). A policy such as specialChars(1) rejects them, and the failure shows up later " +
    "as 'set-password failed' on every user.")
$realmCfg = Invoke-Kc -Path '' -Raw
$policy = ''
if ($realmCfg -and ($realmCfg.PSObject.Properties.Name -contains 'passwordPolicy')) {
    $policy = '' + $realmCfg.passwordPolicy
}
if (-not [string]::IsNullOrWhiteSpace($policy)) {
    if ($FixPolicy) {
        Write-Warn ("relaxing realm password policy (was: $policy -> length(8)) - training lab only")
        if (-not $DryRun) {
            try {
                Invoke-Kc -Method Put -Path '' -Body @{ passwordPolicy = 'length(8)' } | Out-Null
                Write-Ok "password policy relaxed"
            } catch {
                Write-Warn "policy update failed - set it in the Keycloak console"
            }
        }
    } else {
        Write-Warn ("realm password policy is '$policy' - simple lab passwords may be rejected; " +
                    "re-run with -FixPolicy to relax it (lab only)")
    }
} else {
    Write-Ok "no password policy set - training passwords will be accepted"
}

# --------------------------------------------------- realm roles + groups ---
Write-Checkpoint 4 "Read the realm's ACTUAL roles and groups" ("Roster names are matched against what the " +
    "realm really has, never assumed. An unmatched role is reported loudly rather than silently skipped.")
$realmRoles  = @(Invoke-Kc -Path '/roles')
$realmGroups = @(Invoke-Kc -Path '/groups')
Write-Ok ("" + $realmRoles.Count + " realm role(s), " + $realmGroups.Count + " group(s) available")

function Resolve-RealmRole {
    # Display name -> the realm's ACTUAL role name, or $null.
    # Case-insensitive: the realm capitalizes (Data_Steward), rosters do not.
    param([string] $Display)
    $norm = ConvertTo-NormalName $Display
    if ($norm -eq '') { return $null }
    $candidates = @($norm)
    if ($RoleAliases.ContainsKey($norm)) { $candidates += $RoleAliases[$norm] }
    foreach ($c in $candidates) {
        $hit = $realmRoles | Where-Object { $_.name.ToLowerInvariant() -eq $c } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

function Resolve-RealmGroup {
    param([string] $Display)
    $norm = ConvertTo-NormalName $Display
    if ($norm -eq '') { return $null }
    return ($realmGroups | Where-Object { (ConvertTo-NormalName $_.name) -eq $norm } | Select-Object -First 1)
}

# ------------------------------------------------------------------ load ----
Write-Checkpoint 5 "Create users, set passwords, map roles" ("THE ONLY STAGE THAT WRITES. Idempotent: an " +
    "existing user is kept and has its password and roles re-applied, so re-running is safe.")
$created = 0; $kept = 0; $failed = 0; $unmatched = @()

foreach ($u in $rows) {
    Write-Host ("  " + $u.Username + "  (" + $u.Roles + ")") -ForegroundColor White
    if ($DryRun) { continue }

    # create-or-keep. emailVerified so the direct grant works at once.
    $existing = @(Invoke-Kc -Path ("/users?username=" + [uri]::EscapeDataString($u.Username) + "&exact=true") -Raw)
    $userId = $null
    if ($existing -and $existing.Count -gt 0 -and $existing[0]) {
        $userId = $existing[0].id
        $kept++
        Write-Ok "exists - keeping (password + roles re-applied)"
    } else {
        try {
            Invoke-Kc -Method Post -Path '/users' -Body @{
                username = $u.Username; email = $u.Email
                firstName = $u.First;   lastName = $u.Last
                enabled = $true;        emailVerified = $true
            } | Out-Null
            $lookup = @(Invoke-Kc -Path ("/users?username=" + [uri]::EscapeDataString($u.Username) + "&exact=true") -Raw)
            if ($lookup -and $lookup.Count -gt 0) { $userId = $lookup[0].id }
            $created++
            Write-Ok "created"
        } catch {
            $failed++
            Write-Warn ("create failed - skipping (" + $_.Exception.Message + ")")
            continue
        }
    }
    if (-not $userId) { Write-Warn "could not resolve the user id - skipping"; continue }

    # precedence: -Password override > the roster row's Lab_Password > scenario default
    $rowPass = $defPass
    if (-not [string]::IsNullOrWhiteSpace($u.Password)) { $rowPass = $u.Password }
    if (-not [string]::IsNullOrWhiteSpace($Password))   { $rowPass = $Password }

    if (-not [string]::IsNullOrWhiteSpace($rowPass)) {
        try {
            Invoke-Kc -Method Put -Path "/users/$userId/reset-password" -Body @{
                type = 'password'; value = $rowPass; temporary = $false
            } | Out-Null
            Write-Ok "password set"
        } catch {
            Write-Warn "set-password failed (realm password policy? re-run with -FixPolicy)"
        }
    } else {
        Write-Warn ("no password for " + $u.Username +
                    " (no -Password, roster blank, no scenario default) - skipped")
    }

    # map each roster role -> realm role; fall back to a same-named group
    foreach ($r in ($u.Roles -split ';')) {
        $role = $r.Trim()
        if ([string]::IsNullOrWhiteSpace($role)) { continue }

        $realmRole = Resolve-RealmRole $role
        if ($realmRole) {
            try {
                # role-mappings takes an ARRAY of full role representations
                Invoke-Kc -Method Post -Path "/users/$userId/role-mappings/realm" `
                          -Body @(@{ id = $realmRole.id; name = $realmRole.name }) | Out-Null
                Write-Ok ("role: " + $role + " -> " + $realmRole.name)
            } catch {
                Write-Warn ("role assign failed: " + $realmRole.name)
            }
            continue
        }

        $grp = Resolve-RealmGroup $role
        if ($grp) {
            try {
                Invoke-Kc -Method Put -Path "/users/$userId/groups/$($grp.id)" | Out-Null
                Write-Ok ("group: " + $role)
            } catch {
                Write-Warn ("group join failed: " + $role)
            }
        } else {
            $unmatched += $role
            Write-Warn ("NO realm role or group matches '" + $role +
                        "' - run: .\load-pdc-users.ps1 -ListRoles  (then extend `$RoleAliases)")
        }
    }
}

# ---------------------------------------------------------------- summary ---
Write-Checkpoint 6 "Verify" "A user that cannot get a token cannot do the workshop - check one before you teach."
if ($DryRun) {
    Write-Ok ("Dry run complete - " + $rows.Count + " user(s) would be processed.")
} else {
    Write-Ok ("Done. created=$created kept=$kept failed=$failed")
    if ($unmatched.Count -gt 0) {
        Write-Warn ("Unmatched roles: " + (($unmatched | Sort-Object -Unique) -join ', '))
        Write-Warn "Run -ListRoles and extend `$RoleAliases at the top of this script."
    }
    Write-Host ""
    Write-Host "  Verify a login:" -ForegroundColor Cyan
    Write-Host ("    Invoke-RestMethod -Method Post -Uri '$KcBase/realms/$Realm/protocol/openid-connect/token' ``")
    Write-Host "      -Body @{ client_id='pdc-client'; grant_type='password'; username='<user>'; password='<pass>' }"
}
Write-Host ""
