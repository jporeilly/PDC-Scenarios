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

.PARAMETER RosterPath
    Use a roster from anywhere instead of the repo's - e.g. course files on a
    mapped drive. Give an ABSOLUTE path: the script sets its working directory to
    its own folder, so a relative path would resolve against the repo rather than
    your shell. Quote it if it contains spaces.

    Any CSV works. Username and Lab_Password are used when present; otherwise the
    username is derived from the email and the password comes from -Password or
    the scenario default. A Scenario column is only used for filtering when it
    exists, so a single-vertical roster needs no such column.

.PARAMETER DryRun
    Show the plan; change nothing.

.PARAMETER ExportPeople
    Write the realm's users to this path as the Glossary Generator's people.json
    and exit. Read-only: no users are created or modified. Needs the same admin
    credentials as a load, because the Admin REST API is bearer-token only - you
    will be prompted for the Keycloak admin password exactly as you are for a
    load. Persona fields (stakeholder_role, community, owns, expertise) in an
    existing file at that path are merged forward by email.

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
.EXAMPLE
    # Build the Glossary Generator's steward roster from the realm. Read-only.
    .\load-pdc-users.ps1 -ExportPeople .\people.json -SkipTlsCheck
.EXAMPLE
    # A roster outside the repo. Absolute path, quoted - it has spaces.
    .\load-pdc-users.ps1 -Scenario AWC -SkipTlsCheck -RosterPath "P:\Arizona Water\course files\Workshop-00-Preflight\assets\users.csv"
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
    [string] $ExportPeople,
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
    AWC  = 'arizonawater'          # Arizona Water Company course files
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

function ConvertTo-NamedList {
    # Keycloak returns [] for an empty collection, which Invoke-RestMethod can
    # surface as an empty string rather than an empty array - and ForEach-Object
    # then iterates it ONCE, so $_.name throws under Set-StrictMode. A realm with
    # no groups was enough to break -ListRoles, and would have crashed the group
    # fallback mid-load the first time a role did not match. Coerce to an array
    # and keep only entries that actually carry a name.
    #
    # The leading comma is load-bearing. A function's output is ENUMERATED on the
    # way out, so plain `return @(...)` hands back a scalar for one match and
    # NOTHING for none - and $realmGroups.Count then throws under StrictMode.
    # `,@(...)` wraps the array so the unrolling gives it back intact. Do not
    # "tidy" it away; the whole point of this function is that callers get a real
    # list they can .Count and index without guarding.
    param($Response)
    return ,@(@($Response) | Where-Object {
        $_ -and ($_.PSObject.Properties.Name -contains 'name')
    })
}

function Invoke-Kc {
    # Thin wrapper so every call carries the bearer token and TLS settings.
    param(
        [string] $Method = 'Get',
        # Relative to the realm admin API. EMPTY IS LEGAL and means the realm
        # itself (GET/PUT on /admin/realms/{realm}) - Mandatory alone rejects an
        # empty string, which is what broke the password-policy checkpoint.
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Path,
        $Body,
        [switch] $Raw                            # return $null instead of throwing on 404
    )
    $uri = if ($Path -match '^https?://') { $Path } else { "$AdminApi$Path" }
    $args = @{ Method = $Method; Uri = $uri; Headers = @{ Authorization = "Bearer $script:Token" } }
    if ($null -ne $Body) {
        # -InputObject, NOT the pipeline. Piping UNROLLS the array, so a
        # single-element array serializes as a bare object - and the
        # role-mappings endpoint requires an array, so every user with exactly
        # one role would have been rejected.
        $args['Body'] = (ConvertTo-Json -InputObject $Body -Depth 10 -Compress)
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
    $r = ConvertTo-NamedList (Invoke-Kc -Path '/roles')
    if ($r.Count -eq 0) { Write-Host "    (none)" } else { $r | ForEach-Object { Write-Host ("    " + $_.name) } }
    Write-Host ("  Realm '$Realm' groups:") -ForegroundColor Cyan
    $g = ConvertTo-NamedList (Invoke-Kc -Path '/groups')
    if ($g.Count -eq 0) { Write-Host "    (none - role matching will have no group fallback)" }
    else { $g | ForEach-Object { Write-Host ("    " + $_.name) } }
    Write-Host ""
    exit 0
}

# --------------------------------------------------------- export people ----
# Build the Glossary Generator's people.json from the realm.
#
# The point is the ACCOUNT ID. Names, emails and roles can be typed by hand; the
# Keycloak UUID cannot, and without it a glossary term cannot be bound to a real
# steward - the app keeps such a person visible but will not offer them as a
# binding. This is the same shape build_roster.py produces from two CSVs, minus
# the hand-authored persona columns.
#
# Reads only. Writing users is the -Scenario path and is not involved here.
if ($ExportPeople) {
    Write-Checkpoint 2 "Export the realm as a steward roster" ("Reads every enabled user and its realm " +
        "roles. Nothing in Keycloak is modified.")

    $existing = @{}
    if (Test-Path -LiteralPath $ExportPeople) {
        # Persona detail - stakeholder_role, community, owns, expertise - is
        # authored by a human and Keycloak knows nothing about it. Overwriting it
        # on every refresh would quietly discard the curation that makes the
        # roster worth reading, so it is merged forward by email.
        try {
            $prev = Get-Content -LiteralPath $ExportPeople -Raw | ConvertFrom-Json
            foreach ($p in @($prev.people)) {
                if ($p -and $p.email) { $existing[("" + $p.email).ToLowerInvariant()] = $p }
            }
            Write-Ok ("merging persona detail from " + $existing.Count + " existing entries")
        } catch {
            Write-Warn "existing people.json could not be read - writing a fresh roster"
        }
    }

    $users = @(Invoke-Kc -Path '/users?max=1000' -Raw)
    $people = @()
    foreach ($u in $users) {
        if (-not $u -or -not ($u.PSObject.Properties.Name -contains 'id')) { continue }
        if (($u.PSObject.Properties.Name -contains 'enabled') -and (-not $u.enabled)) { continue }

        $roles = @()
        try {
            $rm = ConvertTo-NamedList (Invoke-Kc -Path ("/users/" + $u.id + "/role-mappings/realm") -Raw)
            # default-roles-* is Keycloak plumbing, not a governance role, and
            # listing it makes every steward look identically privileged.
            $roles = @($rm | ForEach-Object { $_.name } | Where-Object { $_ -notlike 'default-roles-*' })
        } catch {}

        $first = ''; $last = ''
        if ($u.PSObject.Properties.Name -contains 'firstName') { $first = "" + $u.firstName }
        if ($u.PSObject.Properties.Name -contains 'lastName')  { $last  = "" + $u.lastName }
        $display = ($first + " " + $last).Trim()
        if (-not $display) { $display = "" + $u.username }

        $email = ''
        if ($u.PSObject.Properties.Name -contains 'email') { $email = "" + $u.email }

        # Mirrors build_roster.py's mapping so a roster built either way agrees.
        $stakeholder = 'Steward'
        if ($roles.Count -gt 0 -and ($roles[0] -notmatch '(?i)steward')) { $stakeholder = $roles[0] }

        $entry = [ordered]@{
            name             = "" + $u.username
            display_name     = $display
            email            = $email
            id               = "" + $u.id
            roles            = $roles
            stakeholder_role = $stakeholder
            community        = ''
            owns             = ''
            expertise        = ''
        }
        $key = $email.ToLowerInvariant()
        if ($key -and $existing.ContainsKey($key)) {
            foreach ($f in @('stakeholder_role', 'community', 'owns', 'expertise')) {
                $was = $existing[$key].$f
                if ($was) { $entry[$f] = $was }
            }
        }
        $people += [pscustomobject]$entry
    }

    if ($people.Count -eq 0) { Stop-Now "No enabled users found in realm '$Realm' - nothing written." }

    $outDir = Split-Path -Parent $ExportPeople
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    # -Depth matters: the default of 2 flattens the roles array into type names.
    @{ people = $people } | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $ExportPeople -Encoding UTF8

    Write-Ok ("wrote " + $people.Count + " people to " + $ExportPeople)
    $noEmail = @($people | Where-Object { -not $_.email }).Count
    if ($noEmail -gt 0) {
        Write-Warn ("" + $noEmail + " account(s) have no email - they cannot be merged with persona detail on a re-run")
    }
    Write-Hint "copy it to the Glossary Generator's state directory as people.json (its /config endpoint prints the path)"
    Write-Host ""
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Scenario)) {
    Stop-Now "Pass -Scenario (CSCU/RETAIL/HEALTH/MFG), -Scenario ALL, -ListRoles or -ExportPeople."
}
$Scenario = $Scenario.ToUpperInvariant()

# ----------------------------------------------------------------- roster ---
# courseware\PDC-Users-All-Scenarios.csv is AUTHORITATIVE. It carries every
# vertical with an explicit Username and per-user Lab_Password, and it survives a
# sparse checkout because cone mode retains top-level courseware/ files. The
# per-workshop users.csv files are course MATERIAL - they carry First/Last,
# Community and Notes for teaching - and are not the loader's source of truth.
#
# -RosterPath still overrides, for a roster that lives outside the repo, but if
# the authoritative file already has rows for this scenario the override is
# SHADOWING them: edits made to the other file would look applied and would not
# be. Say so rather than let the two drift apart silently.
$consolidated = 'courseware\PDC-Users-All-Scenarios.csv'
if ($RosterPath) {
    $csvPath = $RosterPath
    if ((Test-Path -LiteralPath $consolidated) -and
        ((Resolve-Path -LiteralPath $RosterPath -ErrorAction SilentlyContinue).Path -ne
         (Resolve-Path -LiteralPath $consolidated -ErrorAction SilentlyContinue).Path)) {
        $inAuth = @(Import-Csv -LiteralPath $consolidated |
                    Where-Object { $_.PSObject.Properties.Name -contains 'Scenario' -and
                                   ('' + $_.Scenario).Trim().ToUpperInvariant() -eq $Scenario })
        if ($inAuth.Count -gt 0) {
            Write-Warn ("-RosterPath is SHADOWING the authoritative roster, which already has " +
                        $inAuth.Count + " row(s) for $Scenario")
            Write-Hint "authoritative: $consolidated"
            Write-Hint "drop -RosterPath to use it, or update it so the two cannot drift"
        }
    }
} elseif (Test-Path -LiteralPath $consolidated) {
    $csvPath = $consolidated
} elseif ($Scenario -ne 'ALL') {
    $csvPath = "courseware\$Scenario\Platform\Workshop-00-Preflight\assets\users.csv"
    Write-Warn "using a per-workshop roster - that is course material, not the authoritative list"
    Write-Hint "authoritative: $consolidated (missing from this checkout)"
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

# THE STANDARD ROSTER FORMAT
#
#   Scenario,Company,Username,Email,PDC_Roles,Tier,Lab_Password
#
# Only Email is strictly required; everything else is derived when missing, which
# is what lets a Workshop-00 roster (First_Name/Last_Name/Email/PDC_Roles) load
# unchanged. But deriving silently is how a roster ends up half-working - a
# missing Lab_Password creates users who cannot log in, a missing Scenario means
# no filtering happens at all - so the shape is reported before anything is read.
$StandardColumns = @('Scenario', 'Company', 'Username', 'Email', 'PDC_Roles', 'Tier', 'Lab_Password')
$header = @()
$firstRow = Import-Csv -LiteralPath $csvPath | Select-Object -First 1
if ($firstRow) { $header = $firstRow.PSObject.Properties.Name }
if ($header -notcontains 'Email') {
    Write-Hint "the standard format is: $($StandardColumns -join ',')"
    Stop-Now "Roster has no Email column - that is the one field nothing can be derived from."
}
$missing = @($StandardColumns | Where-Object { $header -notcontains $_ })
if ($missing.Count -eq 0) {
    Write-Ok "roster matches the standard format"
} else {
    Write-Warn ("non-standard roster - missing: " + ($missing -join ', '))
    foreach ($m in $missing) {
        switch ($m) {
            'Username'     { Write-Hint "Username     -> derived from the email local-part" }
            'Lab_Password' { Write-Hint "Lab_Password -> falls back to -Password or the scenario default" }
            'Scenario'     { Write-Hint "Scenario     -> no filtering; EVERY row in this file will be loaded" }
            'Company'      { Write-Hint "Company      -> not used by the loader (documentation only)" }
            'Tier'         { Write-Hint "Tier         -> not used by the loader (documentation only)" }
            'PDC_Roles'    { Write-Hint "PDC_Roles    -> users are created with NO roles" }
        }
    }
}

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

# Catch an unloadable roster HERE, while nothing has been written, rather than
# as one warning per user after the accounts already exist. A roster with no
# Lab_Password column, for a scenario with no default, and no -Password, would
# create every user WITHOUT a way to log in - which looks like success.
$withPw = @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Password) }).Count
if ((-not $Password) -and $withPw -eq 0 -and [string]::IsNullOrWhiteSpace($defPass)) {
    Write-Warn ("this roster has no Lab_Password column, and '$Scenario' has no built-in default")
    Write-Hint "pass -Password '<value>' to set one for every user"
    Write-Hint "or add a Lab_Password column to the CSV for per-user passwords"
    Write-Hint ("or add '$Scenario' to the `$DefaultPassword table at the top of this script")
    Stop-Now "No password could be resolved for any user - nothing written."
}
if ($withPw -lt $rows.Count -and (-not $Password) -and [string]::IsNullOrWhiteSpace($defPass)) {
    Write-Warn ("" + ($rows.Count - $withPw) + " of " + $rows.Count +
                " row(s) have no Lab_Password and there is no default - those users will have no login")
}

# ------------------------------------------------------- password policy ----
Write-Checkpoint 3 "Check the realm password policy" ("Lab rosters use simple training passwords " +
    "(copperstate etc). A policy such as specialChars(1) rejects them, and the failure shows up later " +
    "as 'set-password failed' on every user.")
$realmCfg = Invoke-Kc -Path '' -Raw
$policy = ''
if ($realmCfg -and ($realmCfg.PSObject.Properties.Name -contains 'passwordPolicy')) {
    $policy = '' + $realmCfg.passwordPolicy
}
# Not every policy is a problem, and crying wolf here pushes the operator into
# relaxing a realm setting that was doing no harm. length(n) is fine as long as
# n is not longer than the shortest password we are about to set; anything else
# (specialChars, upperCase, digits, notUsername, passwordHistory) can reject a
# simple training password, so that is what we warn about.
$shortestPw = 0
$pwCandidates = @($rows | ForEach-Object { $_.Password }) + @($defPass, $Password) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
if (@($pwCandidates).Count -gt 0) {
    $shortestPw = (@($pwCandidates) | ForEach-Object { $_.Length } | Sort-Object)[0]
}
$blocking = @()
foreach ($clause in ($policy -split '\s+and\s+|;')) {
    $c = $clause.Trim()
    if ($c -eq '') { continue }
    $m = [regex]::Match($c, '^length\((\d+)\)$')
    if ($m.Success) {
        if ($shortestPw -gt 0 -and [int]$m.Groups[1].Value -le $shortestPw) { continue }
    }
    $blocking += $c
}
if ($blocking.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($policy)) {
    Write-Ok ("policy is '$policy' - harmless for these passwords (shortest is $shortestPw chars)")
    $policy = ''
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
        Write-Warn ("realm password policy is '$policy' - the restrictive part is: " +
                    ($blocking -join ', ') + "; simple lab passwords may be rejected. " +
                    "Re-run with -FixPolicy to relax it (lab only)")
    }
} else {
    Write-Ok "no password policy set - training passwords will be accepted"
}

# --------------------------------------------------- realm roles + groups ---
Write-Checkpoint 4 "Read the realm's ACTUAL roles and groups" ("Roster names are matched against what the " +
    "realm really has, never assumed. An unmatched role is reported loudly rather than silently skipped.")
$realmRoles  = ConvertTo-NamedList (Invoke-Kc -Path '/roles')
$realmGroups = ConvertTo-NamedList (Invoke-Kc -Path '/groups')
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

    # precedence: -Password override > the roster row's Lab_Password > scenario default
    $rowPass = $defPass
    if (-not [string]::IsNullOrWhiteSpace($u.Password)) { $rowPass = $u.Password }
    if (-not [string]::IsNullOrWhiteSpace($Password))   { $rowPass = $Password }

    if ($DryRun) {
        # A dry run that only echoed the roster proved nothing. Resolve the roles
        # for real - unmatched roles are the one failure that survives a load and
        # leaves a user who can log in but cannot see anything.
        if ([string]::IsNullOrWhiteSpace($rowPass)) {
            Write-Warn "no password (no -Password, roster blank, no scenario default) - would be skipped"
        }
        foreach ($r in ($u.Roles -split ';')) {
            $role = $r.Trim()
            if ([string]::IsNullOrWhiteSpace($role)) { continue }
            $realmRole = Resolve-RealmRole $role
            if ($realmRole) { Write-Ok ("role: " + $role + " -> " + $realmRole.name); continue }
            $grp = Resolve-RealmGroup $role
            if ($grp) { Write-Ok ("group: " + $role) }
            else {
                $unmatched += $role
                Write-Warn ("NO realm role or group matches '" + $role + "'")
            }
        }
        continue
    }

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
    if ($unmatched.Count -gt 0) {
        Write-Warn ("Unmatched roles: " + (($unmatched | Sort-Object -Unique) -join ', '))
        Write-Warn "Fix these BEFORE loading: run -ListRoles and extend `$RoleAliases at the top of this script."
    } else {
        Write-Ok "every roster role resolved - safe to re-run without -DryRun"
    }
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
