# install-dsh.ps1
# One-click installer for DeepSeek Harness (dsh).
# Strategy: portable Node.js (no admin) + China npm mirror (no GitHub).
# Safe to re-run; already-done steps are skipped and the UI just launches.

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtime   = Join-Path $scriptDir 'dsh-runtime'
$nodeDir   = Join-Path $runtime 'node'
$nodeExe   = Join-Path $nodeDir 'node.exe'
$npmCmd    = Join-Path $nodeDir 'npm.cmd'
$dshCmd    = Join-Path $nodeDir 'dsh.cmd'

$npmRegistry = 'https://registry.npmmirror.com'
$nodeMirror  = 'https://npmmirror.com/mirrors/node'
$nodeMirror2 = 'https://cdn.npmmirror.com/binaries/node'

function Log($m) { Write-Host ("[install] " + $m) -ForegroundColor Cyan }
function Step($m) { Write-Host ""; Write-Host ("==> " + $m) -ForegroundColor Green }

function Download-File($url, $dest) {
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path $curl) {
        & $curl -L --fail --retry 3 --connect-timeout 20 -sS -o $dest $url
        if ($LASTEXITCODE -eq 0) { return }
    }
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

# ---- 1) Portable Node.js ----
if (Test-Path $nodeExe) {
    Step "Portable Node.js already present - skip download."
} else {
    Step "Downloading portable Node.js (no admin needed)..."

    if ([Environment]::Is64BitOperatingSystem) {
        if ($env:PROCESSOR_ARCHITECTURE -match 'ARM') { $arch = 'arm64' } else { $arch = 'x64' }
    } else {
        $arch = 'x86'
    }

    # Prefer the newest LTS (Node 24+, satisfies dsh engine ^22.19 || >=24).
    $ver = $null
    try {
        $index = Invoke-RestMethod -Uri "$nodeMirror/index.json" -TimeoutSec 30
        $lts = $index | Where-Object { $_.lts } | Select-Object -First 1
        if ($lts) { $ver = $lts.version }
    } catch {}
    if (-not $ver) { $ver = 'v24.20.0' }
    Log "Node version: $ver ($arch)"

    $zipName = "node-$ver-win-$arch.zip"
    $zipPath = Join-Path $runtime $zipName
    New-Item -ItemType Directory -Force -Path $runtime | Out-Null

    $ok = $false
    foreach ($u in @("$nodeMirror/$ver/$zipName", "$nodeMirror2/$ver/$zipName")) {
        try { Log "Downloading $u"; Download-File $u $zipPath; $ok = $true; break }
        catch { Log ("failed: " + $_.Exception.Message) }
    }
    if (-not $ok) { throw "Could not download Node.js. Check network / try again." }

    Step "Extracting Node.js..."
    Expand-Archive -Path $zipPath -DestinationPath $runtime -Force
    Remove-Item $zipPath -ErrorAction SilentlyContinue

    $extracted = Get-ChildItem -Directory $runtime | Where-Object { $_.Name -like 'node-v*' } | Select-Object -First 1
    if (-not $extracted) { throw "Extract failed." }
    if (Test-Path $nodeDir) { Remove-Item $nodeDir -Recurse -Force }
    Rename-Item -Path $extracted.FullName -NewName 'node'
}

# ---- 2) npm registry -> China mirror ----
Step "Configuring npm registry: $npmRegistry"
& $npmCmd config set registry $npmRegistry
Log ("Node " + (& $nodeExe --version))
Log ("npm  " + (& $npmCmd --version))

# ---- 3) Install dsh ----
Step "Installing @deepseek-ai/dsh (first time downloads many packages; please wait)..."
& $npmCmd install -g @deepseek-ai/dsh --no-fund --no-audit

if (-not (Test-Path $dshCmd)) {
    $alt = Get-ChildItem -Path $nodeDir -Recurse -Filter 'dsh.cmd' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($alt) { $dshCmd = $alt.FullName }
}
if (-not (Test-Path $dshCmd)) { throw "Install finished but dsh.cmd not found." }

# ---- 4) Launch ----
Step "Starting DeepSeek Harness Web UI -> http://127.0.0.1:3080"
& $dshCmd web
