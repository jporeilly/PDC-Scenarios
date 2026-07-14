<#
  PDC-Demo - the ONE bootstrap (Windows host edition)

  The standard topology runs the APPS on the Windows host (Ollama lives
  here) and the lab + PDC on the Ubuntu VM. This script stands up (or
  updates) the complete host-side checkout:
    - the Glossary Generator (the PDC-Demo checkout itself)
    - the Policy Generator   (sparse: the app only)
    - PDC-Scenarios          (sparse: ONLY the selected vertical)
  and installs the vertical's domain pack + roster into the Glossary app.
  Re-runs update all three; the vertical is remembered (pass an ID to
  select or switch). The lab itself runs on the VM:
      curl -fsSL https://raw.githubusercontent.com/jporeilly/PDC-Scenarios/main/install-pdc-demo.sh | bash -s -- CSCU
      cd ~/PDC-Demo/PDC-Scenarios && make scenario ID=CSCU

  Installs to C:\PDC-Demo by default - keeping the test/delivery
  environment separate from any dev checkouts (e.g. C:\Projects).

  One-liner (PowerShell):
    iex "& { $(irm https://raw.githubusercontent.com/jporeilly/PDC-Scenarios/main/install-pdc-demo.ps1) } CSCU"

  Or from a checkout:
    .\install-pdc-demo.ps1 CSCU
    .\install-pdc-demo.ps1 -DemoDir D:\PDC-Demo -Vertical RETAIL
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Vertical,
    [string]$DemoDir
)
$ErrorActionPreference = 'Stop'

$GlossUrl  = if ($env:GLOSSARY_REPO_URL)  { $env:GLOSSARY_REPO_URL }  else { 'https://github.com/jporeilly/PDC-Glossary-Generator.git' }
$PolicyUrl = if ($env:POLICY_REPO_URL)    { $env:POLICY_REPO_URL }    else { 'https://github.com/jporeilly/PDC-Policy-Generator.git' }
$ScenUrl   = if ($env:SCENARIOS_REPO_URL) { $env:SCENARIOS_REPO_URL } else { 'https://github.com/jporeilly/PDC-Scenarios.git' }
if (-not $DemoDir) { $DemoDir = if ($env:PDC_DEMO_DIR) { $env:PDC_DEMO_DIR } else { 'C:\PDC-Demo' } }
if ($Vertical) { $Vertical = $Vertical.ToUpper() }

function Ok   ($m) { Write-Host "  " -NoNewline; Write-Host "OK  " -ForegroundColor Green  -NoNewline; Write-Host $m }
function Warn ($m) { Write-Host "  " -NoNewline; Write-Host "!   " -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Die  ($m) { Write-Host "  X  $m" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "  PDC-Demo - one-command host install/update" -ForegroundColor Cyan
Write-Host "  Glossary Generator + Policy Generator + the selected vertical." -ForegroundColor DarkGray
Write-Host ""
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die "git is not installed (install Git for Windows)." }
Ok ("git " + ((git --version) -replace 'git version\s*',''))
Write-Host ""

# --- 1. the PDC-Demo checkout (Glossary Generator) ---------------------------
Write-Host "  1/3  Glossary Generator (the PDC-Demo checkout)"
if (Test-Path (Join-Path $DemoDir '.git')) {
    if (-not (Test-Path (Join-Path $DemoDir 'glossary_generator'))) { Die "$DemoDir is a git checkout but not the Glossary repo" }
    git -C $DemoDir pull -q --ff-only
    if ($LASTEXITCODE -ne 0) { Die "pull failed - local changes in $DemoDir? Commit/stash and re-run." }
    Ok ("Updated to " + (git -C $DemoDir rev-parse --short HEAD))
} elseif ((Test-Path $DemoDir) -and (Get-ChildItem $DemoDir -Force | Select-Object -First 1)) {
    Die "$DemoDir exists but is not a git checkout - move it aside and re-run."
} else {
    Write-Host "  cloning..." -ForegroundColor DarkGray
    git clone -q $GlossUrl $DemoDir
    if ($LASTEXITCODE -ne 0) { Die "clone failed" }
    Ok "Cloned to $DemoDir"
}
Ok ("Glossary app " + (Get-Content (Join-Path $DemoDir 'glossary_generator\VERSION') -Raw).Trim())
Write-Host ""

# --- 2. the Policy Generator (sparse: app only) -------------------------------
Write-Host "  2/3  Policy Generator"
$PT = Join-Path $DemoDir 'PDC-Policy-Generator'
if (Test-Path (Join-Path $PT '.git')) {
    git -C $PT pull -q --ff-only
    if ($LASTEXITCODE -ne 0) { Warn "Policy pull failed (local changes?)" } else { Ok ("Updated to " + (git -C $PT rev-parse --short HEAD)) }
} else {
    Write-Host "  cloning (sparse, app only)..." -ForegroundColor DarkGray
    git -C $DemoDir clone -q --filter=blob:none --sparse $PolicyUrl PDC-Policy-Generator
    if ($LASTEXITCODE -ne 0) { Die "Policy clone failed" }
    git -C $PT sparse-checkout set policy_generator
    Ok "Cloned (policy_generator/ only)"
}
Ok ("Policy app " + (Get-Content (Join-Path $PT 'policy_generator\VERSION') -Raw).Trim())
Write-Host ""

# --- 3. PDC-Scenarios (sparse: the selected vertical) -------------------------
Write-Host "  3/3  PDC-Scenarios (the vertical)"
$ST = Join-Path $DemoDir 'PDC-Scenarios'
if (-not (Test-Path (Join-Path $ST '.git')) -and $Vertical) {
    Write-Host "  cloning (sparse, $Vertical only)..." -ForegroundColor DarkGray
    git -C $DemoDir clone -q --filter=blob:none --no-checkout $ScenUrl PDC-Scenarios
    if ($LASTEXITCODE -ne 0) { Die "PDC-Scenarios clone failed" }
    git -C $ST sparse-checkout set "data_sources/lab" "data_sources/$Vertical" "courseware/$Vertical" "diagrams"
    git -C $ST checkout -q
}
if (Test-Path (Join-Path $ST '.git')) {
    git -C $ST pull -q --ff-only 2>$null
    $cur = (git -C $ST sparse-checkout list 2>$null) |
           ForEach-Object { if ($_ -match '^data_sources/(.+)$' -and $matches[1] -ne 'lab') { $matches[1] } } |
           Select-Object -First 1
    if (-not $Vertical) { $Vertical = $cur }
    if ($Vertical) {
        git -C $ST sparse-checkout set "data_sources/lab" "data_sources/$Vertical" "courseware/$Vertical" "diagrams"
        if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $ST "data_sources\$Vertical"))) {
            Ok "Vertical $Vertical - data kit + domain pack + courseware"
        } else {
            Warn "vertical '$Vertical' not found - valid ids: CSCU RETAIL HEALTH MFG"
        }
    } else {
        Warn "No vertical selected - re-run with one: .\install-pdc-demo.ps1 CSCU"
    }
} else {
    Warn "Skipped - pass a vertical to set it up: .\install-pdc-demo.ps1 CSCU"
}
# keep the outer checkout's git status clean
$exclude = Join-Path $DemoDir '.git\info\exclude'
foreach ($d in @('PDC-Policy-Generator','PDC-Scenarios')) {
    if ((Test-Path (Join-Path $DemoDir $d)) -and -not (Select-String -Path $exclude -Pattern "^$d/$" -Quiet -ErrorAction SilentlyContinue)) {
        Add-Content -Path $exclude -Value "$d/"
    }
}
Write-Host ""

# --- 4. install the vertical's pack into the Glossary app --------------------
if ($Vertical -and (Test-Path (Join-Path $ST "data_sources\$Vertical"))) {
    Write-Host "  Domain pack -> Glossary app"
    $env:GLOSSARY_APP_DIR = Join-Path $DemoDir 'glossary_generator'
    Push-Location $ST
    try { & powershell -NoProfile -ExecutionPolicy Bypass -File .\install-scenario.ps1 $Vertical | ForEach-Object { "  $_" } }
    finally { Pop-Location; Remove-Item Env:GLOSSARY_APP_DIR -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "  Next" -ForegroundColor Cyan
Write-Host "  1. Lab (on the VM):  curl one-liner + make scenario ID=$Vertical   (see PDC-Scenarios README)"
Write-Host ("  2. Glossary app:     cd {0}\glossary_generator; .\run.ps1     -> http://127.0.0.1:5000" -f $DemoDir)
Write-Host ("  3. Policy app:       cd {0}\PDC-Policy-Generator\policy_generator; .\run.ps1  -> http://127.0.0.1:5001" -f $DemoDir)
Write-Host ""
