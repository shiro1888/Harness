@echo off
setlocal EnableExtensions
title DeepSeek Harness
set "DSH_SETUP_FILE=%~f0"
set "DSH_SETUP_BAD_ARG="

:parse_arguments
if "%~1"=="" goto run_installer
if /I "%~1"=="--install-only" (
    set "DSH_SETUP_INSTALL_ONLY=1"
    shift
    goto parse_arguments
)
if /I "%~1"=="--no-pause" (
    set "DSH_SETUP_NONINTERACTIVE=1"
    shift
    goto parse_arguments
)
if /I "%~1"=="--no-open" (
    set "DSH_SETUP_NO_OPEN=1"
    shift
    goto parse_arguments
)
if /I "%~1"=="--port" goto parse_port
set "DSH_SETUP_BAD_ARG=%~1"
goto run_installer

:parse_port
if "%~2"=="" (
    set "DSH_SETUP_BAD_ARG=--port missing value"
    goto run_installer
)
set "DSH_SETUP_PORT=%~2"
shift
shift
goto parse_arguments

:run_installer
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$raw=[IO.File]::ReadAllText($env:DSH_SETUP_FILE,[Text.Encoding]::UTF8);$marker='# POWERSHELL_START';$offset=$raw.LastIndexOf($marker,[StringComparison]::Ordinal);if($offset -lt 0){throw 'PowerShell payload is missing.'};&([ScriptBlock]::Create($raw.Substring($offset)))"
exit /b %ERRORLEVEL%

# POWERSHELL_START
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

try {
    $Host.UI.RawUI.WindowTitle = 'DeepSeek Harness ?????'
} catch {
    # ?????????????????????
}

$SetupPath = [IO.Path]::GetFullPath($env:DSH_SETUP_FILE)
$SetupRoot = Split-Path -Parent $SetupPath
$RuntimeRoot = Join-Path $SetupRoot 'dsh-runtime'
$NodeRoot = Join-Path $RuntimeRoot 'node'
$NodeExe = Join-Path $NodeRoot 'node.exe'
$NpmCmd = Join-Path $NodeRoot 'npm.cmd'
$DshCmd = Join-Path $NodeRoot 'dsh.cmd'
$DshManifest = Join-Path $NodeRoot 'node_modules\@deepseek-ai\dsh\package.json'
$NpmConfig = Join-Path $RuntimeRoot 'installer.npmrc'
$NpmCache = Join-Path $RuntimeRoot 'npm-cache'
$FallbackNodeVersion = 'v24.20.0'
$AllowedInstallScripts = '@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs'

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Text)
    Write-Host ("  [??] {0}" -f $Text) -ForegroundColor Green
}

function Write-Notice {
    param([string]$Text)
    Write-Host ("  [??] {0}" -f $Text) -ForegroundColor Yellow
}

function Wait-ForClose {
    param([string]$Text)
    if ($env:DSH_SETUP_NONINTERACTIVE -eq '1') {
        return
    }
    Write-Host ''
    try {
        [void](Read-Host $Text)
    } catch {
        # ????????????
    }
}

function Get-MachineArchitecture {
    $value = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = $env:PROCESSOR_ARCHITECTURE
    }

    switch ($value.ToUpperInvariant()) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        default { throw "????? Windows ???$value??? 64 ? x64 ? ARM64?" }
    }
}

function Invoke-RegistryMetadata {
    param(
        [string]$Registry,
        [string]$Name
    )

    $uri = "$Registry/@deepseek-ai%2Fdsh"
    try {
        $headers = @{
            Accept = 'application/vnd.npm.install-v1+json'
            'User-Agent' = 'deepseek-harness-windows-installer'
        }
        $metadata = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 15
        $latest = [string]$metadata.'dist-tags'.latest
        if ([string]::IsNullOrWhiteSpace($latest)) {
            throw '???? latest ??'
        }
        if ($metadata.versions.PSObject.Properties.Name -notcontains $latest) {
            throw "latest ????? $latest ????????"
        }
        return [pscustomobject]@{
            Name = $Name
            Registry = $Registry
            Latest = $latest
        }
    } catch {
        Write-Notice ("????{0}?{1}" -f $Name, $_.Exception.Message)
        return $null
    }
}

function Get-LatestDshRelease {
    $official = Invoke-RegistryMetadata -Registry 'https://registry.npmjs.org' -Name 'npm ????'
    $mirror = Invoke-RegistryMetadata -Registry 'https://registry.npmmirror.com' -Name '?? npm ??'

    if ($null -ne $official) {
        $installRegistry = $official.Registry
        $installSource = $official.Name
        if ($null -ne $mirror -and $mirror.Latest -eq $official.Latest) {
            $installRegistry = $mirror.Registry
            $installSource = $mirror.Name
        } elseif ($null -ne $mirror) {
            Write-Notice ("??????? {0}??? latest ? {1}??????????" -f $mirror.Latest, $official.Latest)
        }

        return [pscustomobject]@{
            Latest = $official.Latest
            Registry = $installRegistry
            Source = $installSource
            FallbackRegistry = $official.Registry
        }
    }

    if ($null -ne $mirror) {
        Write-Notice '?????? npm ???????????? latest ???'
        return [pscustomobject]@{
            Latest = $mirror.Latest
            Registry = $mirror.Registry
            Source = $mirror.Name
            FallbackRegistry = $null
        }
    }

    return $null
}

function Get-InstalledDshVersion {
    if (-not (Test-Path -LiteralPath $DshManifest -PathType Leaf)) {
        return $null
    }

    try {
        $manifest = Get-Content -LiteralPath $DshManifest -Raw -Encoding UTF8 | ConvertFrom-Json
        return [string]$manifest.version
    } catch {
        Write-Notice '?? dsh ????????????????'
        return $null
    }
}

function Get-LatestNodeRelease {
    param([string]$Architecture)

    $requiredFile = "win-$Architecture-zip"
    $sources = @(
        [pscustomobject]@{
            Name = 'Node.js ????'
            Index = 'https://npmmirror.com/mirrors/node/index.json'
        },
        [pscustomobject]@{
            Name = 'Node.js ???'
            Index = 'https://nodejs.org/dist/index.json'
        }
    )

    foreach ($source in $sources) {
        try {
            $releases = Invoke-RestMethod -Uri $source.Index -TimeoutSec 20 -Headers @{ 'User-Agent' = 'deepseek-harness-windows-installer' }
            $release = $null
            foreach ($candidate in $releases) {
                if ($candidate.lts -and ($candidate.files -contains $requiredFile)) {
                    $release = $candidate
                    break
                }
            }
            if ($null -ne $release) {
                return [pscustomobject]@{
                    Version = [string]$release.version
                    Name = $source.Name
                }
            }
        } catch {
            Write-Notice ("????{0}?????{1}" -f $source.Name, $_.Exception.Message)
        }
    }

    Write-Notice ("?????? Node.js ?? LTS?????????????? {0}?" -f $FallbackNodeVersion)
    return [pscustomobject]@{
        Version = $FallbackNodeVersion
        Name = '???????'
    }
}

function Invoke-FileDownload {
    param(
        [string[]]$Uris,
        [string]$Destination
    )

    foreach ($uri in ($Uris | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Force
        }

        Write-Host ("  ???{0}" -f $uri)
        try {
            $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
            if ($null -ne $curl) {
                & $curl.Source --location --fail --silent --show-error --retry 3 --connect-timeout 20 --ssl-revoke-best-effort --output $Destination $uri
                if ($LASTEXITCODE -ne 0) {
                    throw "curl ??? $LASTEXITCODE"
                }
            } else {
                Invoke-WebRequest -Uri $uri -OutFile $Destination -UseBasicParsing -TimeoutSec 120
            }

            $file = Get-Item -LiteralPath $Destination
            if ($file.Length -le 0) {
                throw '????????'
            }
            return
        } catch {
            Write-Notice ("?????????{0}" -f $_.Exception.Message)
        }
    }

    throw '?? Node.js ??????????????????'
}

function Install-PortableNode {
    param([string]$Architecture)

    $release = Get-LatestNodeRelease -Architecture $Architecture
    $version = $release.Version
    $archiveName = "node-$version-win-$Architecture.zip"
    $archivePath = Join-Path $RuntimeRoot (".$archiveName.download")
    $stagingRoot = Join-Path $RuntimeRoot (".node-install-{0}" -f $PID)
    $backupRoot = Join-Path $RuntimeRoot (".node-backup-{0}" -f $PID)
    $expandedNode = Join-Path $stagingRoot "node-$version-win-$Architecture"
    $downloadUris = @(
        "https://npmmirror.com/mirrors/node/$version/$archiveName",
        "https://nodejs.org/dist/$version/$archiveName"
    )

    Write-Step ("[1/3] ???? Node.js {0}?{1}?" -f $version, $Architecture)
    New-Item -ItemType Directory -Path $RuntimeRoot -Force | Out-Null

    try {
        Invoke-FileDownload -Uris $downloadUris -Destination $archivePath
        if (Test-Path -LiteralPath $stagingRoot) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force
        }
        New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
        Expand-Archive -LiteralPath $archivePath -DestinationPath $stagingRoot -Force

        $stagedNode = Join-Path $expandedNode 'node.exe'
        $stagedNpm = Join-Path $expandedNode 'npm.cmd'
        if (-not (Test-Path -LiteralPath $stagedNode -PathType Leaf) -or -not (Test-Path -LiteralPath $stagedNpm -PathType Leaf)) {
            throw 'Node.js ???????? node.exe ? npm.cmd'
        }

        $reportedVersion = (& $stagedNode --version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $reportedVersion -ne $version) {
            throw "Node.js ??????? $version????? $reportedVersion"
        }

        if (Test-Path -LiteralPath $backupRoot) {
            Remove-Item -LiteralPath $backupRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $NodeRoot) {
            Move-Item -LiteralPath $NodeRoot -Destination $backupRoot
        }

        try {
            Move-Item -LiteralPath $expandedNode -Destination $NodeRoot
        } catch {
            if (-not (Test-Path -LiteralPath $NodeRoot) -and (Test-Path -LiteralPath $backupRoot)) {
                Move-Item -LiteralPath $backupRoot -Destination $NodeRoot
            }
            throw
        }

        if (Test-Path -LiteralPath $backupRoot) {
            Remove-Item -LiteralPath $backupRoot -Recurse -Force
        }
        Write-Ok ("Node.js {0} ???????????{1}" -f $version, $release.Name)
    } finally {
        if (Test-Path -LiteralPath $archivePath) {
            Remove-Item -LiteralPath $archivePath -Force
        }
        if (Test-Path -LiteralPath $stagingRoot) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force
        }
    }
}

function Ensure-PortableNode {
    $architecture = Get-MachineArchitecture
    if ((Test-Path -LiteralPath $NodeExe -PathType Leaf) -and (Test-Path -LiteralPath $NpmCmd -PathType Leaf)) {
        try {
            $version = (& $NodeExe --version 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -eq 0 -and $version -match '^v\d+\.\d+\.\d+$') {
                Write-Step '[1/3] ???? Node.js'
                Write-Ok ("??? {0}?????????????" -f $version)
                return
            }
        } catch {
            Write-Notice '???? Node.js ???????????'
        }
    }

    Install-PortableNode -Architecture $architecture
}

function Invoke-NpmWithOutput {
    param([string[]]$Arguments)

    $savedErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $NpmCmd @Arguments 2>&1 | ForEach-Object { Write-Host $_ }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorAction
    }
    return [int]$code
}

function Invoke-DshInstall {
    param(
        [string]$Version,
        [string]$Registry
    )

    $package = "@deepseek-ai/dsh@$Version"
    $arguments = @(
        '--userconfig', $NpmConfig,
        '--cache', $NpmCache,
        'install', '--global', $package,
        '--prefix', $NodeRoot,
        "--registry=$Registry",
        '--prefer-online',
        "--allow-scripts=$AllowedInstallScripts",
        '--strict-allow-scripts=true',
        '--no-fund',
        '--no-audit'
    )

    return (Invoke-NpmWithOutput -Arguments $arguments)
}

function Invoke-DshRebuild {
    $arguments = @(
        '--userconfig', $NpmConfig,
        '--cache', $NpmCache,
        'rebuild', '--global', '@deepseek-ai/dsh',
        '--prefix', $NodeRoot,
        "--allow-scripts=$AllowedInstallScripts",
        '--strict-allow-scripts=true',
        '--no-fund',
        '--no-audit'
    )

    return (Invoke-NpmWithOutput -Arguments $arguments)
}

function Invoke-NodeProbe {
    param(
        [string]$JavaScript,
        [string]$Argument
    )

    $savedErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = (& $NodeExe -e $JavaScript $Argument 2>&1 | Out-String).Trim()
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorAction
    }

    return [pscustomobject]@{
        ExitCode = [int]$code
        Output = $output
    }
}

function Find-DshDependencyDirectory {
    param([string]$Name)

    $dshPackageRoot = Split-Path -Parent $DshManifest
    $candidates = @(
        (Join-Path (Join-Path $dshPackageRoot 'node_modules') $Name),
        (Join-Path (Join-Path $NodeRoot 'node_modules') $Name)
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'package.json') -PathType Leaf) {
            return $candidate
        }
    }

    throw "???? dsh ?????$Name"
}

function Test-DshRuntimeDependencies {
    try {
        $koffiRoot = Find-DshDependencyDirectory -Name 'koffi'
        $koffiProbe = Invoke-NodeProbe -JavaScript "require(process.argv[1]); process.stdout.write('ok')" -Argument $koffiRoot
        if ($koffiProbe.ExitCode -ne 0) {
            return [pscustomobject]@{ Ok = $false; Message = "Koffi ?????$($koffiProbe.Output)" }
        }

        $ptyRoot = Find-DshDependencyDirectory -Name 'node-pty'
        $ptyScript = "const p=require(process.argv[1]);const c=p.spawn(process.env.ComSpec||'cmd.exe',['/d','/c','echo DSH_PTY_PROBE'],{name:'xterm',cols:80,rows:24,cwd:process.cwd(),env:process.env});let out='';const t=setTimeout(()=>process.exit(21),5000);c.onData(d=>out+=d);c.onExit(e=>{clearTimeout(t);process.exit(e.exitCode===0&&out.includes('DSH_PTY_PROBE')?0:22)});"
        $ptyProbe = Invoke-NodeProbe -JavaScript $ptyScript -Argument $ptyRoot
        if ($ptyProbe.ExitCode -ne 0) {
            return [pscustomobject]@{ Ok = $false; Message = "??????????? $($ptyProbe.ExitCode)?$($ptyProbe.Output)" }
        }

        return [pscustomobject]@{ Ok = $true; Message = 'Koffi ? Windows ???????' }
    } catch {
        return [pscustomobject]@{ Ok = $false; Message = $_.Exception.Message }
    }
}

function Ensure-LatestDsh {
    Write-Step '[2/3] ?? DeepSeek Harness ????'

    New-Item -ItemType Directory -Path $RuntimeRoot -Force | Out-Null
    $npmConfigText = [string]::Join([Environment]::NewLine, @('fund=false', 'audit=false', 'update-notifier=false', ''))
    [IO.File]::WriteAllText($NpmConfig, $npmConfigText, $utf8)

    $installed = Get-InstalledDshVersion
    if ($null -ne $installed) {
        Write-Host ("  ???????{0}" -f $installed)
    } else {
        Write-Host '  ??????????'
    }

    $release = Get-LatestDshRelease
    $expectedVersion = $installed
    if ($null -eq $release) {
        if ($null -ne $installed -and (Test-Path -LiteralPath $DshCmd -PathType Leaf)) {
            Write-Notice ("?????????????????? {0}???????????" -f $installed)
        } else {
            throw '???? npm ??????????????????? dsh?'
        }
    } else {
        $expectedVersion = $release.Latest
        Write-Host ("  ?? latest?{0}" -f $release.Latest)
        if ($installed -eq $release.Latest -and (Test-Path -LiteralPath $DshCmd -PathType Leaf)) {
            Write-Ok ("?????? {0}?" -f $installed)
        } else {
            if ($null -eq $installed) {
                Write-Host ("  ????{0}?? {1}??????????????" -f $release.Source, $release.Latest)
            } else {
                Write-Host ("  ????{0}? {1} ??? {2}??" -f $release.Source, $installed, $release.Latest)
            }

            $exitCode = Invoke-DshInstall -Version $release.Latest -Registry $release.Registry
            if ($exitCode -ne 0 -and $release.FallbackRegistry -and $release.FallbackRegistry -ne $release.Registry) {
                Write-Notice '????????????? npm ???????'
                $exitCode = Invoke-DshInstall -Version $release.Latest -Registry $release.FallbackRegistry
            }
            if ($exitCode -ne 0) {
                throw "npm ?? dsh ???????$exitCode"
            }
        }
    }

    $verifiedVersion = Get-InstalledDshVersion
    if ($verifiedVersion -ne $expectedVersion) {
        throw "???????????? $expectedVersion??? $verifiedVersion"
    }
    if (-not (Test-Path -LiteralPath $DshCmd -PathType Leaf)) {
        throw "??????????????$DshCmd"
    }

    $cliOutput = (& $DshCmd --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "dsh --version ?????$cliOutput"
    }
    $cliLines = @($cliOutput -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($cliLines.Count -eq 0) {
        throw 'dsh --version ???????'
    }
    $cliVersion = $cliLines[-1].Trim()
    if ($cliVersion -ne $verifiedVersion) {
        throw "dsh ???????????? $verifiedVersion????? $cliVersion"
    }

    $runtimeProbe = Test-DshRuntimeDependencies
    if (-not $runtimeProbe.Ok) {
        Write-Notice ("???????????????????{0}" -f $runtimeProbe.Message)
        $rebuildExit = Invoke-DshRebuild
        if ($rebuildExit -ne 0) {
            throw "dsh ???????npm ????$rebuildExit"
        }
        $runtimeProbe = Test-DshRuntimeDependencies
        if (-not $runtimeProbe.Ok) {
            throw "dsh ????????????$($runtimeProbe.Message)"
        }
    }

    Write-Ok ("dsh {0} ??????Koffi ???????" -f $verifiedVersion)
    return $verifiedVersion
}

function Test-LocalPortAvailable {
    param([int]$Port)

    $listener = $null
    try {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        if ($null -ne $listener) {
            try { $listener.Stop() } catch {}
        }
    }
}

function Get-WebPort {
    if (-not [string]::IsNullOrWhiteSpace($env:DSH_SETUP_PORT)) {
        $requested = 0
        if (-not [int]::TryParse($env:DSH_SETUP_PORT, [ref]$requested) -or $requested -lt 1 -or $requested -gt 65535) {
            throw "???????$($env:DSH_SETUP_PORT)"
        }
        if (-not (Test-LocalPortAvailable -Port $requested)) {
            throw "???? $requested ????????????"
        }
        return $requested
    }

    foreach ($candidate in 3080..3099) {
        if (Test-LocalPortAvailable -Port $candidate) {
            if ($candidate -ne 3080) {
                Write-Notice ("?? 3080 ??????????? {0}?" -f $candidate)
            }
            return $candidate
        }
    }

    throw '?? 3080 ? 3099 ????????????????'
}

function Main {
    if (-not [string]::IsNullOrWhiteSpace($env:DSH_SETUP_BAD_ARG)) {
        throw "???????$($env:DSH_SETUP_BAD_ARG)??????--install-only?--port ???--no-open?--no-pause?"
    }
    if (-not [string]::IsNullOrWhiteSpace($env:DSH_SETUP_PORT)) {
        $validatedPort = 0
        if (-not [int]::TryParse($env:DSH_SETUP_PORT, [ref]$validatedPort) -or $validatedPort -lt 1 -or $validatedPort -gt 65535) {
            throw "???????$($env:DSH_SETUP_PORT)"
        }
    }

    Set-Location -LiteralPath $SetupRoot
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host '  DeepSeek Harness ??????Windows 10/11?64 ??' -ForegroundColor White
    Write-Host '  ??????????????????? dsh latest' -ForegroundColor White
    Write-Host '============================================================' -ForegroundColor DarkCyan

    Ensure-PortableNode
    $env:PATH = "$NodeRoot;$env:PATH"

    $npmVersion = (& $NpmCmd --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "npm ?????$npmVersion"
    }
    Write-Host ("  npm ???{0}" -f $npmVersion)

    $dshVersion = Ensure-LatestDsh

    Write-Step '[3/3] ????????'
    if ($env:DSH_SETUP_INSTALL_ONLY -eq '1') {
        Write-Ok ("????????dsh ???{0}" -f $dshVersion)
        Write-Host ('  ?????"{0}" web' -f $DshCmd)
        return
    }

    $port = Get-WebPort
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host ("  ???? DeepSeek Harness {0}" -f $dshVersion) -ForegroundColor White
    Write-Host ("  ?????http://127.0.0.1:{0}" -f $port) -ForegroundColor White
    Write-Host '  ?????????????? Ctrl+C ??????' -ForegroundColor White
    Write-Host '  ???????????????? ?token= ??????' -ForegroundColor White
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host ''

    if ($env:DSH_SETUP_NO_OPEN -eq '1') {
        & $DshCmd web --port $port --no-open
    } else {
        & $DshCmd web --port $port
    }
    $webExitCode = $LASTEXITCODE
    if ($webExitCode -ne 0) {
        throw "DeepSeek Harness ???????????$webExitCode"
    }

    Write-Notice 'DeepSeek Harness ???????'
}

try {
    Main
    Wait-ForClose '????????'
    exit 0
} catch {
    Write-Host ''
    Write-Host ("??????{0}" -f $_.Exception.Message) -ForegroundColor Red
    Wait-ForClose '?????????????????????'
    exit 1
}
