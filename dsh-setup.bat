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

# 控制台代码页必须与 [Console]::OutputEncoding 一致，否则中文会乱码：
# 中文版 Windows 的控制台默认是 936(GBK)，若只把 OutputEncoding 设为 UTF-8，
# PowerShell 按 UTF-8 写出的字节会被控制台按 GBK 解读，中文全部变成乱码。
# 因此先把代码页切到 65001(UTF-8) 再设置编码；切换失败则按原代码页输出。
$consoleCodePage = 65001
try {
    $previousCodePage = [Console]::OutputEncoding.CodePage
    $null = & chcp.com $consoleCodePage 2>&1
    if ($LASTEXITCODE -ne 0) {
        $consoleCodePage = $previousCodePage
    }
} catch {
    $consoleCodePage = [Console]::OutputEncoding.CodePage
}

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
if ($consoleCodePage -eq 65001) {
    [Console]::InputEncoding = $utf8
    [Console]::OutputEncoding = $utf8
    $OutputEncoding = $utf8
} else {
    # 代码页未能切换到 UTF-8（受限环境）：按实际代码页输出，中文才不会乱码。
    $legacy = [System.Text.Encoding]::GetEncoding($consoleCodePage)
    try { [Console]::InputEncoding = $legacy } catch {}
    try { [Console]::OutputEncoding = $legacy } catch {}
    $OutputEncoding = $legacy
}

try {
    $Host.UI.RawUI.WindowTitle = 'DeepSeek Harness 一键安装器'
} catch {
    # 某些非交互终端不支持修改标题，不影响安装。
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
$FallbackNodeVersion = 'v24.21.0'
$AllowedInstallScripts = '@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs'

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Text)
    Write-Host ("  [完成] {0}" -f $Text) -ForegroundColor Green
}

function Write-Notice {
    param([string]$Text)
    Write-Host ("  [提示] {0}" -f $Text) -ForegroundColor Yellow
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
        # 输入流不可用时直接结束。
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
        default { throw "暂不支持此 Windows 架构：$value。需要 64 位 x64 或 ARM64。" }
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
            throw '没有找到 latest 标签'
        }
        if ($metadata.versions.PSObject.Properties.Name -notcontains $latest) {
            throw "latest 指向的版本 $latest 不在仓库元数据中"
        }
        return [pscustomobject]@{
            Name = $Name
            Registry = $Registry
            Latest = $latest
        }
    } catch {
        Write-Notice ("无法读取{0}：{1}" -f $Name, $_.Exception.Message)
        return $null
    }
}

function Get-LatestDshRelease {
    $official = Invoke-RegistryMetadata -Registry 'https://registry.npmjs.org' -Name 'npm 官方仓库'
    $mirror = Invoke-RegistryMetadata -Registry 'https://registry.npmmirror.com' -Name '国内 npm 镜像'

    if ($null -ne $official) {
        $installRegistry = $official.Registry
        $installSource = $official.Name
        if ($null -ne $mirror -and $mirror.Latest -eq $official.Latest) {
            $installRegistry = $mirror.Registry
            $installSource = $mirror.Name
        } elseif ($null -ne $mirror) {
            Write-Notice ("国内镜像目前是 {0}，官方 latest 是 {1}；本次改用官方仓库。" -f $mirror.Latest, $official.Latest)
        }

        return [pscustomobject]@{
            Latest = $official.Latest
            Registry = $installRegistry
            Source = $installSource
            FallbackRegistry = $official.Registry
        }
    }

    if ($null -ne $mirror) {
        Write-Notice '当前无法连接 npm 官方仓库，先以国内镜像的 latest 为准。'
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
        Write-Notice '现有 dsh 包信息无法读取，将执行修复安装。'
        return $null
    }
}

function Get-LatestNodeRelease {
    param([string]$Architecture)

    $requiredFile = "win-$Architecture-zip"
    $sources = @(
        [pscustomobject]@{
            Name = 'Node.js 国内镜像'
            Index = 'https://npmmirror.com/mirrors/node/index.json'
        },
        [pscustomobject]@{
            Name = 'Node.js 官方站'
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
            Write-Notice ("无法读取{0}版本列表：{1}" -f $source.Name, $_.Exception.Message)
        }
    }

    Write-Notice ("暂时无法查询 Node.js 最新 LTS，改用安装器内置的已验证版本 {0}。" -f $FallbackNodeVersion)
    return [pscustomobject]@{
        Version = $FallbackNodeVersion
        Name = '安装器内置版本'
    }
}

function Get-CurlExecutable {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $curl) {
        return $null
    }

    # 部分 Windows 10（20H1/20H2/21H1 等）自带的 curl 是 7.55.1，而
    # --ssl-revoke-best-effort 自 curl 7.70.0 才提供。参数不被识别时 curl 会以
    # 退出码 2 直接失败，所以这里先用 --help 探测一次，只在不支持时省略该参数。
    $supportsRevokeBestEffort = $false
    try {
        $savedErrorAction = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $help = (& $curl.Source --help all 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            $help = (& $curl.Source --help 2>&1 | Out-String)
        }
        $ErrorActionPreference = $savedErrorAction
        $supportsRevokeBestEffort = $help -match 'ssl-revoke-best-effort'
    } catch {
        $supportsRevokeBestEffort = $false
    }

    return [pscustomobject]@{
        Path = $curl.Source
        SupportsRevokeBestEffort = $supportsRevokeBestEffort
    }
}

function Invoke-SingleDownload {
    param(
        [string]$Uri,
        [string]$Destination
    )

    # 先试 curl：支持 --ssl-revoke-best-effort 时带上它（可绕开 Schannel 吊销
    # 检查失败导致的下载中断），不支持则省略该参数。
    $curl = Get-CurlExecutable
    if ($null -ne $curl) {
        $curlArguments = @('--location', '--fail', '--silent', '--show-error', '--retry', '3', '--connect-timeout', '20')
        if ($curl.SupportsRevokeBestEffort) {
            $curlArguments += '--ssl-revoke-best-effort'
        }
        $curlArguments += @('--output', $Destination, $Uri)

        $savedErrorAction = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $curl.Path @curlArguments
            $curlExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $savedErrorAction
        }

        if ($curlExitCode -eq 0) {
            return
        }
        Write-Notice ("curl 下载失败（退出码 {0}），改用系统下载组件重试。" -f $curlExitCode)
    }

    # curl 缺失或失败时用系统内置下载组件兜底，保证单个地址仍有机会成功。
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -TimeoutSec 120
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

        Write-Host ("  下载：{0}" -f $uri)
        try {
            Invoke-SingleDownload -Uri $uri -Destination $Destination

            $file = Get-Item -LiteralPath $Destination
            if ($file.Length -le 0) {
                throw '下载结果为空文件'
            }
            return
        } catch {
            Write-Notice ("这个下载地址失败：{0}" -f $_.Exception.Message)
        }
    }

    throw '所有 Node.js 下载地址都失败了，请检查网络后重试。'
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

    Write-Step ("[1/3] 安装便携 Node.js {0}（{1}）" -f $version, $Architecture)
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
            throw 'Node.js 压缩包解压后缺少 node.exe 或 npm.cmd'
        }

        $reportedVersion = (& $stagedNode --version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $reportedVersion -ne $version) {
            throw "Node.js 自检失败，期望 $version，实际输出 $reportedVersion"
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
        Write-Ok ("Node.js {0} 已就绪，版本列表来自：{1}" -f $version, $release.Name)
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
                Write-Step '[1/3] 检查便携 Node.js'
                Write-Ok ("已安装 {0}，继续使用当前便携运行时。" -f $version)
                return
            }
        } catch {
            Write-Notice '现有便携 Node.js 无法运行，将自动修复。'
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

    throw "没有找到 dsh 运行依赖：$Name"
}

function Test-DshRuntimeDependencies {
    try {
        $koffiRoot = Find-DshDependencyDirectory -Name 'koffi'
        $koffiProbe = Invoke-NodeProbe -JavaScript "require(process.argv[1]); process.stdout.write('ok')" -Argument $koffiRoot
        if ($koffiProbe.ExitCode -ne 0) {
            return [pscustomobject]@{ Ok = $false; Message = "Koffi 加载失败：$($koffiProbe.Output)" }
        }

        $ptyRoot = Find-DshDependencyDirectory -Name 'node-pty'
        $ptyScript = "const p=require(process.argv[1]);const c=p.spawn(process.env.ComSpec||'cmd.exe',['/d','/c','echo DSH_PTY_PROBE'],{name:'xterm',cols:80,rows:24,cwd:process.cwd(),env:process.env});let out='';const t=setTimeout(()=>process.exit(21),5000);c.onData(d=>out+=d);c.onExit(e=>{clearTimeout(t);process.exit(e.exitCode===0&&out.includes('DSH_PTY_PROBE')?0:22)});"
        $ptyProbe = Invoke-NodeProbe -JavaScript $ptyScript -Argument $ptyRoot
        if ($ptyProbe.ExitCode -ne 0) {
            return [pscustomobject]@{ Ok = $false; Message = "伪终端自检失败，退出码 $($ptyProbe.ExitCode)：$($ptyProbe.Output)" }
        }

        return [pscustomobject]@{ Ok = $true; Message = 'Koffi 与 Windows 伪终端均可运行' }
    } catch {
        return [pscustomobject]@{ Ok = $false; Message = $_.Exception.Message }
    }
}

function Ensure-LatestDsh {
    Write-Step '[2/3] 检查 DeepSeek Harness 最新版本'

    New-Item -ItemType Directory -Path $RuntimeRoot -Force | Out-Null
    $npmConfigText = [string]::Join([Environment]::NewLine, @('fund=false', 'audit=false', 'update-notifier=false', ''))
    [IO.File]::WriteAllText($NpmConfig, $npmConfigText, $utf8)

    $installed = Get-InstalledDshVersion
    if ($null -ne $installed) {
        Write-Host ("  当前安装版本：{0}" -f $installed)
    } else {
        Write-Host '  当前安装版本：未安装'
    }

    $release = Get-LatestDshRelease
    $expectedVersion = $installed
    if ($null -eq $release) {
        if ($null -ne $installed -and (Test-Path -LiteralPath $DshCmd -PathType Leaf)) {
            Write-Notice ("网络检查失败，暂时继续使用已安装版本 {0}。下次运行会重新检查。" -f $installed)
        } else {
            throw '无法连接 npm 官方仓库或国内镜像，且本机还没有可用的 dsh。'
        }
    } else {
        $expectedVersion = $release.Latest
        Write-Host ("  官方 latest：{0}" -f $release.Latest)
        if ($installed -eq $release.Latest -and (Test-Path -LiteralPath $DshCmd -PathType Leaf)) {
            Write-Ok ("已经是最新版 {0}。" -f $installed)
        } else {
            if ($null -eq $installed) {
                Write-Host ("  正在通过{0}安装 {1}，首次安装可能需要几分钟……" -f $release.Source, $release.Latest)
            } else {
                Write-Host ("  正在通过{0}把 {1} 更新到 {2}……" -f $release.Source, $installed, $release.Latest)
            }

            $exitCode = Invoke-DshInstall -Version $release.Latest -Registry $release.Registry
            if ($exitCode -ne 0 -and $release.FallbackRegistry -and $release.FallbackRegistry -ne $release.Registry) {
                Write-Notice '国内镜像安装失败，正在改用 npm 官方仓库重试。'
                $exitCode = Invoke-DshInstall -Version $release.Latest -Registry $release.FallbackRegistry
            }
            if ($exitCode -ne 0) {
                throw "npm 安装 dsh 失败，退出码：$exitCode"
            }
        }
    }

    $verifiedVersion = Get-InstalledDshVersion
    if ($verifiedVersion -ne $expectedVersion) {
        throw "安装后版本校验失败，期望 $expectedVersion，实际 $verifiedVersion"
    }
    if (-not (Test-Path -LiteralPath $DshCmd -PathType Leaf)) {
        throw "安装完成后没有找到启动文件：$DshCmd"
    }

    $cliOutput = (& $DshCmd --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "dsh --version 运行失败：$cliOutput"
    }
    $cliLines = @($cliOutput -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($cliLines.Count -eq 0) {
        throw 'dsh --version 没有返回版本号'
    }
    $cliVersion = $cliLines[-1].Trim()
    if ($cliVersion -ne $verifiedVersion) {
        throw "dsh 命令版本校验失败，包版本 $verifiedVersion，命令输出 $cliVersion"
    }

    $runtimeProbe = Test-DshRuntimeDependencies
    if (-not $runtimeProbe.Ok) {
        Write-Notice ("运行依赖自检未通过，执行一次受限修复：{0}" -f $runtimeProbe.Message)
        $rebuildExit = Invoke-DshRebuild
        if ($rebuildExit -ne 0) {
            throw "dsh 依赖修复失败，npm 退出码：$rebuildExit"
        }
        $runtimeProbe = Test-DshRuntimeDependencies
        if (-not $runtimeProbe.Ok) {
            throw "dsh 依赖修复后仍未通过自检：$($runtimeProbe.Message)"
        }
    }

    Write-Ok ("dsh {0} 已通过命令、Koffi 与伪终端自检。" -f $verifiedVersion)
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
            throw "端口参数无效：$($env:DSH_SETUP_PORT)"
        }
        if (-not (Test-LocalPortAvailable -Port $requested)) {
            throw "指定端口 $requested 已被占用，请换一个端口。"
        }
        return $requested
    }

    foreach ($candidate in 3080..3099) {
        if (Test-LocalPortAvailable -Port $candidate) {
            if ($candidate -ne 3080) {
                Write-Notice ("端口 3080 已被占用，本次自动改用 {0}。" -f $candidate)
            }
            return $candidate
        }
    }

    throw '端口 3080 到 3099 都被占用，请关闭占用程序后重试。'
}

function Main {
    if (-not [string]::IsNullOrWhiteSpace($env:DSH_SETUP_BAD_ARG)) {
        throw "不支持的参数：$($env:DSH_SETUP_BAD_ARG)。可用参数：--install-only、--port 端口、--no-open、--no-pause。"
    }
    if (-not [string]::IsNullOrWhiteSpace($env:DSH_SETUP_PORT)) {
        $validatedPort = 0
        if (-not [int]::TryParse($env:DSH_SETUP_PORT, [ref]$validatedPort) -or $validatedPort -lt 1 -or $validatedPort -gt 65535) {
            throw "端口参数无效：$($env:DSH_SETUP_PORT)"
        }
    }

    Set-Location -LiteralPath $SetupRoot
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host '  DeepSeek Harness 一键安装器（Windows 10/11，64 位）' -ForegroundColor White
    Write-Host '  便携安装、无需管理员、每次运行自动检查 dsh latest' -ForegroundColor White
    Write-Host '============================================================' -ForegroundColor DarkCyan

    Ensure-PortableNode
    $env:PATH = "$NodeRoot;$env:PATH"

    $npmVersion = (& $NpmCmd --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "npm 无法运行：$npmVersion"
    }
    Write-Host ("  npm 版本：{0}" -f $npmVersion)

    $dshVersion = Ensure-LatestDsh

    Write-Step '[3/3] 准备启动网页界面'
    if ($env:DSH_SETUP_INSTALL_ONLY -eq '1') {
        Write-Ok ("安装与校验完成，dsh 版本：{0}" -f $dshVersion)
        Write-Host ('  启动命令："{0}" web' -f $DshCmd)
        return
    }

    $port = Get-WebPort
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host ("  即将启动 DeepSeek Harness {0}" -f $dshVersion) -ForegroundColor White
    Write-Host ("  本地地址：http://127.0.0.1:{0}" -f $port) -ForegroundColor White
    Write-Host '  使用期间请保持此窗口开启；按 Ctrl+C 可停止服务。' -ForegroundColor White
    Write-Host '  浏览器若未自动打开，请复制下方带 ?token= 的完整地址。' -ForegroundColor White
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host ''

    if ($env:DSH_SETUP_NO_OPEN -eq '1') {
        & $DshCmd web --port $port --no-open
    } else {
        & $DshCmd web --port $port
    }
    $webExitCode = $LASTEXITCODE
    if ($webExitCode -ne 0) {
        throw "DeepSeek Harness 服务异常停止，退出码：$webExitCode"
    }

    Write-Notice 'DeepSeek Harness 服务已经停止。'
}

try {
    Main
    Wait-ForClose '按回车键关闭窗口'
    exit 0
} catch {
    Write-Host ''
    Write-Host ("安装器失败：{0}" -f $_.Exception.Message) -ForegroundColor Red
    Wait-ForClose '请记录上面的错误信息，然后按回车键关闭窗口'
    exit 1
}
