@echo off
setlocal EnableExtensions
title DeepSeek Harness
set "DSH_SETUP_FILE=%~f0"
set "DSH_SETUP_INSTALL_ONLY="
set "DSH_SETUP_NONINTERACTIVE="
set "DSH_SETUP_NO_OPEN="
set "DSH_SETUP_FAST="
set "DSH_SETUP_REINSTALL="
set "DSH_SETUP_CLEAN="
set "DSH_SETUP_SHORTCUT="
set "DSH_SETUP_HELP="
set "DSH_SETUP_PORT="
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
if /I "%~1"=="--fast" (
    set "DSH_SETUP_FAST=1"
    shift
    goto parse_arguments
)
if /I "%~1"=="--skip-check" (
    set "DSH_SETUP_FAST=1"
    shift
    goto parse_arguments
)
if /I "%~1"=="--reinstall" (
    set "DSH_SETUP_REINSTALL=1"
    shift
    goto parse_arguments
)
if /I "%~1"=="--update" (
    set "DSH_SETUP_REINSTALL=1"
    shift
    goto parse_arguments
)
if /I "%~1"=="--clean" (
    set "DSH_SETUP_CLEAN=1"
    shift
    goto parse_arguments
)
if /I "%~1"=="--reset" (
    set "DSH_SETUP_CLEAN=1"
    shift
    goto parse_arguments
)
if /I "%~1"=="--create-shortcut" (
    set "DSH_SETUP_SHORTCUT=1"
    shift
    goto parse_arguments
)
if /I "%~1"=="--shortcut" (
    set "DSH_SETUP_SHORTCUT=1"
    shift
    goto parse_arguments
)
if /I "%~1"=="--help" (
    set "DSH_SETUP_HELP=1"
    shift
    goto parse_arguments
)
if /I "%~1"=="-h" (
    set "DSH_SETUP_HELP=1"
    shift
    goto parse_arguments
)
if /I "%~1"=="--port" goto parse_port
if not defined DSH_SETUP_BAD_ARG set "DSH_SETUP_BAD_ARG=%~1"
shift
goto parse_arguments

:parse_port
if "%~2"=="" (
    if not defined DSH_SETUP_BAD_ARG set "DSH_SETUP_BAD_ARG=--port 缺少端口数值"
    shift
    goto parse_arguments
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
    $Host.UI.RawUI.WindowTitle = 'DeepSeek Harness 一键部署管理器'
    if ($Host.UI.RawUI.WindowSize.Width -lt 85) {
        $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(88, [Math]::Max(28, $Host.UI.RawUI.WindowSize.Height))
    }
} catch {
    # 某些非交互终端或环境不支持修改窗口尺寸/标题，不影响运行。
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

# ============================
# UI 美化与提示函数
# ============================
function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host ("==> {0}" -f $Text) -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Text)
    Write-Host '  [✓] ' -ForegroundColor Green -NoNewline
    Write-Host $Text -ForegroundColor White
}

function Write-Info {
    param([string]$Text)
    Write-Host '  [i] ' -ForegroundColor Cyan -NoNewline
    Write-Host $Text -ForegroundColor Gray
}

function Write-Notice {
    param([string]$Text)
    Write-Host '  [!] ' -ForegroundColor Yellow -NoNewline
    Write-Host $Text -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Text)
    Write-Host '  [×] ' -ForegroundColor Red -NoNewline
    Write-Host $Text -ForegroundColor Red
}

function Show-Banner {
    Write-Host '========================================================================' -ForegroundColor DarkCyan
    Write-Host '                   DeepSeek Harness 一键部署管理器                      ' -ForegroundColor Cyan
    Write-Host '       便携运行环境 · 自动镜像加速 · 完整环境自检 · 极速启动            ' -ForegroundColor Gray
    Write-Host '========================================================================' -ForegroundColor DarkCyan
}

function Show-Dashboard {
    param(
        [string]$Version,
        [int]$Port
    )
    Write-Host ''
    Write-Host '========================================================================' -ForegroundColor DarkCyan
    Write-Host '  DeepSeek Harness 网页服务启动成功！' -ForegroundColor Green
    Write-Host ("  · 运行版本: {0}" -f $Version) -ForegroundColor Gray
    Write-Host '  · 本地访问: ' -ForegroundColor Gray -NoNewline
    Write-Host ("http://127.0.0.1:{0}" -f $Port) -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  使用提示:' -ForegroundColor White
    Write-Host '  1. 系统将自动尝试在默认浏览器中打开该页面' -ForegroundColor Gray
    Write-Host '  2. 浏览器若未自动弹出，请复制控制台下方包含 ?token= 的完整链接' -ForegroundColor Gray
    Write-Host '  3. 运行期间请保持此窗口开启；按 Ctrl + C 可安全停止服务' -ForegroundColor Gray
    Write-Host '========================================================================' -ForegroundColor DarkCyan
    Write-Host ''
}

function Show-Help {
    Write-Host ''
    Write-Host 'DeepSeek Harness 一键部署器 - 命令参数说明' -ForegroundColor Cyan
    Write-Host '========================================================================' -ForegroundColor DarkCyan
    Write-Host '  用法: dsh-setup.bat [选项]' -ForegroundColor White
    Write-Host ''
    Write-Host '  选项列表:' -ForegroundColor White
    Write-Host '    --install-only        仅安装/更新并完成依赖自检，不启动网页服务' -ForegroundColor Gray
    Write-Host '    --fast, --skip-check  极速模式：跳过在线版本检查，直接秒启本地已有版本' -ForegroundColor Gray
    Write-Host '    --reinstall, --update 强制重装模式：重新拉取最新版本并校验原生依赖' -ForegroundColor Gray
    Write-Host '    --clean, --reset      清理并重置便携运行时目录（dsh-runtime）' -ForegroundColor Gray
    Write-Host '    --create-shortcut     在当前用户桌面创建一键启动快捷方式并退出' -ForegroundColor Gray
    Write-Host '    --port <端口号>       指定 Web 服务端口（默认 3080，被占用则自动顺延）' -ForegroundColor Gray
    Write-Host '    --no-open             启动服务后不自动调用浏览器打开网页' -ForegroundColor Gray
    Write-Host '    --no-pause            自动化脚本模式，执行完毕后不等待用户按回车' -ForegroundColor Gray
    Write-Host '    --help, -h            显示此帮助信息' -ForegroundColor Gray
    Write-Host '========================================================================' -ForegroundColor DarkCyan
    Write-Host ''
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

function New-DesktopShortcut {
    param(
        [string]$Arguments = ""
    )
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $shortcutPath = Join-Path $desktop 'DeepSeek Harness.lnk'
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $SetupPath
        if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
            $shortcut.Arguments = $Arguments
        }
        $shortcut.WorkingDirectory = $SetupRoot
        $shortcut.Description = 'DeepSeek Harness 一键启动'
        if (Test-Path -LiteralPath $NodeExe -PathType Leaf) {
            $shortcut.IconLocation = "$NodeExe,0"
        }
        $shortcut.Save()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
        return $shortcutPath
    } catch {
        Write-Notice ("创建桌面快捷方式失败：{0}" -f $_.Exception.Message)
        return $null
    }
}

# ============================
# 架构与网络查询逻辑
# ============================
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
        [string]$Name,
        [int]$TimeoutSec = 8
    )

    $uri = "$Registry/@deepseek-ai%2Fdsh"
    try {
        $headers = @{
            Accept = 'application/vnd.npm.install-v1+json'
            'User-Agent' = 'deepseek-harness-windows-installer'
        }
        $metadata = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec $TimeoutSec
        $latest = [string]$metadata.'dist-tags'.latest
        if ([string]::IsNullOrWhiteSpace($latest)) {
            throw '没有找到 latest 标签'
        }
        return [pscustomobject]@{
            Name = $Name
            Registry = $Registry
            Latest = $latest
        }
    } catch {
        return $null
    }
}

function Invoke-ParallelRegistryQuery {
    param(
        [string]$OfficialRegistry = 'https://registry.npmjs.org',
        [string]$MirrorRegistry = 'https://registry.npmmirror.com',
        [int]$TimeoutSec = 8
    )

    $officialRes = $null
    $mirrorRes = $null

    try {
        Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
        $handler = New-Object System.Net.Http.HttpClientHandler
        $proxyUri = $env:HTTPS_PROXY
        if ([string]::IsNullOrWhiteSpace($proxyUri)) { $proxyUri = $env:HTTP_PROXY }
        if ([string]::IsNullOrWhiteSpace($proxyUri)) { $proxyUri = $env:ALL_PROXY }
        if (-not [string]::IsNullOrWhiteSpace($proxyUri)) {
            try {
                $handler.Proxy = New-Object System.Net.WebProxy($proxyUri)
                $handler.UseProxy = $true
            } catch {}
        }
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
        $client.DefaultRequestHeaders.Add('User-Agent', 'deepseek-harness-windows-installer')
        $client.DefaultRequestHeaders.Add('Accept', 'application/vnd.npm.install-v1+json')

        $taskOff = $client.GetStringAsync("$OfficialRegistry/@deepseek-ai%2Fdsh")
        $taskMir = $client.GetStringAsync("$MirrorRegistry/@deepseek-ai%2Fdsh")

        # 智能竞速等待：国内镜像通常极速返回，一旦镜像完成，最多再给官方 1.2 秒缓冲，避免死等超时
        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        $maxWaitMs = $TimeoutSec * 1000
        $mirrorDoneTime = -1

        while ($stopwatch.ElapsedMilliseconds -lt $maxWaitMs) {
            if ($taskOff.IsCompleted -and $taskMir.IsCompleted) { break }
            if ($taskMir.IsCompleted -and $mirrorDoneTime -lt 0) {
                $mirrorDoneTime = $stopwatch.ElapsedMilliseconds
            }
            if ($mirrorDoneTime -ge 0 -and ($stopwatch.ElapsedMilliseconds - $mirrorDoneTime) -gt 1200) {
                break
            }
            Start-Sleep -Milliseconds 40
        }

        if ($taskOff.IsCompleted -and -not $taskOff.IsFaulted -and -not $taskOff.IsCanceled) {
            try {
                $meta = $taskOff.Result | ConvertFrom-Json
                $latest = [string]$meta.'dist-tags'.latest
                if (-not [string]::IsNullOrWhiteSpace($latest)) {
                    $officialRes = [pscustomobject]@{
                        Name = 'npm 官方仓库'
                        Registry = $OfficialRegistry
                        Latest = $latest
                    }
                }
            } catch {}
        }

        if ($taskMir.IsCompleted -and -not $taskMir.IsFaulted -and -not $taskMir.IsCanceled) {
            try {
                $meta = $taskMir.Result | ConvertFrom-Json
                $latest = [string]$meta.'dist-tags'.latest
                if (-not [string]::IsNullOrWhiteSpace($latest)) {
                    $mirrorRes = [pscustomobject]@{
                        Name = '国内 npm 镜像'
                        Registry = $MirrorRegistry
                        Latest = $latest
                    }
                }
            } catch {}
        }
    } catch {
        # 异步客户端不可用时，优雅回退到逐个查询
        $officialRes = Invoke-RegistryMetadata -Registry $OfficialRegistry -Name 'npm 官方仓库' -TimeoutSec 5
        $mirrorRes = Invoke-RegistryMetadata -Registry $MirrorRegistry -Name '国内 npm 镜像' -TimeoutSec 5
    } finally {
        if ($null -ne $client) {
            try { $client.Dispose() } catch {}
        }
    }

    return [pscustomobject]@{
        Official = $officialRes
        Mirror = $mirrorRes
    }
}

function Get-LatestDshRelease {
    param([string]$InstalledVersion)

    # 1. 如果用户指定了 --fast 或 --skip-check，且本地已有正常运行版本，直接跳过网络检查
    if ($env:DSH_SETUP_FAST -eq '1') {
        if (-not [string]::IsNullOrWhiteSpace($InstalledVersion) -and (Test-Path -LiteralPath $DshCmd -PathType Leaf)) {
            Write-Info '已启用极速模式 (--fast)，跳过在线版本检查，直接加载本地版本。'
            return [pscustomobject]@{
                Latest = $InstalledVersion
                Registry = $null
                Source = '本地极速模式'
                FallbackRegistry = $null
                Skipped = $true
            }
        }
    }

    Write-Info '正在并发查询 npm 官方仓库与国内镜像最新发布信息...'
    $query = Invoke-ParallelRegistryQuery
    $official = $query.Official
    $mirror = $query.Mirror

    if ($null -ne $official) {
        $installRegistry = $official.Registry
        $installSource = $official.Name
        if ($null -ne $mirror -and $mirror.Latest -eq $official.Latest) {
            $installRegistry = $mirror.Registry
            $installSource = $mirror.Name
            Write-Ok ("官方最新版本为 {0}（国内镜像已同步，优先选用国内镜像加速）" -f $official.Latest)
        } elseif ($null -ne $mirror) {
            Write-Notice ("国内镜像当前为 {0}，官方最新版本为 {1}；将从官方仓库安装。" -f $mirror.Latest, $official.Latest)
        } else {
            Write-Ok ("已获取官方最新版本：{0}" -f $official.Latest)
        }

        return [pscustomobject]@{
            Latest = $official.Latest
            Registry = $installRegistry
            Source = $installSource
            FallbackRegistry = $official.Registry
            Skipped = $false
        }
    }

    if ($null -ne $mirror) {
        Write-Notice 'npm 官方仓库当前连接较慢或不可用，先以国内镜像 latest 为准。'
        return [pscustomobject]@{
            Latest = $mirror.Latest
            Registry = $mirror.Registry
            Source = $mirror.Name
            FallbackRegistry = $null
            Skipped = $false
        }
    }

    # 两者均连接失败（断网或受限机房）：若已有本地版本，优雅降级为离线启动
    if (-not [string]::IsNullOrWhiteSpace($InstalledVersion) -and (Test-Path -LiteralPath $DshCmd -PathType Leaf)) {
        Write-Notice ("当前网络无法连接仓库，自动启用离线模式，继续使用已安装的本地版本 {0}。" -f $InstalledVersion)
        return [pscustomobject]@{
            Latest = $InstalledVersion
            Registry = $null
            Source = '本地离线模式'
            FallbackRegistry = $null
            Skipped = $true
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
            $releases = Invoke-RestMethod -Uri $source.Index -TimeoutSec 15 -Headers @{ 'User-Agent' = 'deepseek-harness-windows-installer' }
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

    # 部分 Windows 10 自带 curl 7.55.1，缺少 --ssl-revoke-best-effort。
    # 探测一次避免传错参数直接退出码 2。
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

    $curl = Get-CurlExecutable
    if ($null -ne $curl) {
        $isInteractive = ($env:DSH_SETUP_NONINTERACTIVE -ne '1')
        $curlArguments = @('--location', '--fail', '--retry', '3', '--connect-timeout', '20')
        if ($isInteractive) {
            $curlArguments += '--progress-bar'
        } else {
            $curlArguments += @('--silent', '--show-error')
        }
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

        Write-Info ("正在下载：{0}" -f $uri)
        try {
            Invoke-SingleDownload -Uri $uri -Destination $Destination

            $file = Get-Item -LiteralPath $Destination
            if ($file.Length -le 0) {
                throw '下载结果为空文件'
            }
            return
        } catch {
            Write-Notice ("当前下载地址失败：{0}" -f $_.Exception.Message)
        }
    }

    throw '所有 Node.js 下载地址均不可用，请检查网络连接后重试。'
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

    Write-Step ("[1/3] 下载并准备便携 Node.js {0}（{1}）" -f $version, $Architecture)
    New-Item -ItemType Directory -Path $RuntimeRoot -Force | Out-Null

    try {
        Invoke-FileDownload -Uris $downloadUris -Destination $archivePath
        Write-Info '正在解压 Node.js 压缩包...'
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
        Write-Ok ("便携 Node.js {0} 安装完成（来源: {1}）" -f $version, $release.Name)
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
                Write-Step '[1/3] 检查便携 Node.js 运行时'
                Write-Ok ("已就绪便携 Node.js {0} ({1})，继续复用当前环境。" -f $version, $architecture)
                return
            }
        } catch {
            Write-Notice '现有便携 Node.js 无法运行，正在自动重新准备。'
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

        return [pscustomobject]@{ Ok = $true; Message = 'Koffi 原生模块与 Windows 伪终端均运行正常' }
    } catch {
        return [pscustomobject]@{ Ok = $false; Message = $_.Exception.Message }
    }
}

function Ensure-LatestDsh {
    Write-Step '[2/3] 检查 DeepSeek Harness 核心组件'

    New-Item -ItemType Directory -Path $RuntimeRoot -Force | Out-Null
    $npmConfigText = [string]::Join([Environment]::NewLine, @('fund=false', 'audit=false', 'update-notifier=false', ''))
    [IO.File]::WriteAllText($NpmConfig, $npmConfigText, $utf8)

    $installed = Get-InstalledDshVersion
    if ($null -ne $installed) {
        Write-Info ("当前已安装版本：{0}" -f $installed)
    } else {
        Write-Info '当前未安装 DeepSeek Harness'
    }

    $release = Get-LatestDshRelease -InstalledVersion $installed
    if ($null -eq $release) {
        throw '无法连接 npm 官方仓库或国内镜像，且本机暂无可用安装版本。请检查网络或代理设置。'
    }

    $expectedVersion = $release.Latest
    $forceReinstall = ($env:DSH_SETUP_REINSTALL -eq '1')
    if ($release.Skipped -and -not $forceReinstall) {
        # 跳过在线更新或进入离线模式
    } elseif ($installed -eq $release.Latest -and (Test-Path -LiteralPath $DshCmd -PathType Leaf) -and -not $forceReinstall) {
        Write-Ok ("已是最新版 {0}，无需重复下载。" -f $installed)
    } else {
        if ($forceReinstall -and ($installed -eq $release.Latest)) {
            Write-Info ("强制重装模式：正在重新部署当前最新版本 {0}..." -f $release.Latest)
        } elseif ($null -eq $installed) {
            Write-Info ("正在通过{0}安装 {1}，首次安装需拉取并配置依赖，请稍候..." -f $release.Source, $release.Latest)
        } else {
            Write-Info ("正在通过{0}把版本从 {1} 更新至 {2}..." -f $release.Source, $installed, $release.Latest)
        }

        $exitCode = Invoke-DshInstall -Version $release.Latest -Registry $release.Registry
        if ($exitCode -ne 0 -and $release.FallbackRegistry -and $release.FallbackRegistry -ne $release.Registry) {
            Write-Notice '国内镜像安装遇到异常，正在改用 npm 官方仓库自动重试...'
            $exitCode = Invoke-DshInstall -Version $release.Latest -Registry $release.FallbackRegistry
        }
        if ($exitCode -ne 0) {
            throw "npm 安装 dsh 失败，退出码：$exitCode"
        }
    }

    $verifiedVersion = Get-InstalledDshVersion
    if ($verifiedVersion -ne $expectedVersion) {
        throw "安装后版本校验失败，期望 $expectedVersion，实际 $verifiedVersion"
    }
    if (-not (Test-Path -LiteralPath $DshCmd -PathType Leaf)) {
        throw "未找到启动文件：$DshCmd"
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

    # 深度自检原生依赖
    Write-Info '正在自检 Koffi 原生模块与 Windows 伪终端...'
    $runtimeProbe = Test-DshRuntimeDependencies
    if (-not $runtimeProbe.Ok) {
        Write-Notice ("运行依赖自检未通过，正在尝试自动修复：{0}" -f $runtimeProbe.Message)
        $rebuildExit = Invoke-DshRebuild
        if ($rebuildExit -ne 0) {
            throw "dsh 依赖修复失败，npm 退出码：$rebuildExit"
        }
        $runtimeProbe = Test-DshRuntimeDependencies
        if (-not $runtimeProbe.Ok) {
            throw "dsh 依赖修复后仍未通过自检：$($runtimeProbe.Message)"
        }
    }

    Write-Ok ("dsh {0} 通过命令行接口、Koffi 原生调用与 Windows 伪终端自检。" -f $verifiedVersion)
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
            throw "指定的端口数值无效：$($env:DSH_SETUP_PORT)"
        }
        if (-not (Test-LocalPortAvailable -Port $requested)) {
            throw "指定端口 $requested 已被占用，请更换端口后重试。"
        }
        return $requested
    }

    foreach ($candidate in 3080..3099) {
        if (Test-LocalPortAvailable -Port $candidate) {
            if ($candidate -ne 3080) {
                Write-Notice ("默认端口 3080 已被占用，自动选择空闲端口 {0}。" -f $candidate)
            }
            return $candidate
        }
    }

    throw '本地端口 3080 到 3099 均被占用，请关闭占用程序后重试。'
}

function Main {
    if ($env:DSH_SETUP_HELP -eq '1') {
        Show-Help
        exit 0
    }

    if (-not [string]::IsNullOrWhiteSpace($env:DSH_SETUP_BAD_ARG)) {
        throw "不支持的参数：$($env:DSH_SETUP_BAD_ARG)。请使用 --help 查看支持的完整参数列表。"
    }
    if (-not [string]::IsNullOrWhiteSpace($env:DSH_SETUP_PORT)) {
        $validatedPort = 0
        if (-not [int]::TryParse($env:DSH_SETUP_PORT, [ref]$validatedPort) -or $validatedPort -lt 1 -or $validatedPort -gt 65535) {
            throw "端口参数无效：$($env:DSH_SETUP_PORT)"
        }
    }

    Set-Location -LiteralPath $SetupRoot
    Show-Banner

    # 清理重置便携运行时指令
    if ($env:DSH_SETUP_CLEAN -eq '1') {
        Write-Step '清理便携运行时环境'
        if (Test-Path -LiteralPath $RuntimeRoot) {
            Write-Info ("正在清理目录：{0}..." -f $RuntimeRoot)
            try {
                Remove-Item -LiteralPath $RuntimeRoot -Recurse -Force
                Write-Ok '便携运行时已彻底清理完成。下次运行将重新进行全新部署。'
            } catch {
                Write-Fail ("清理失败（请先确保关闭正在运行的 DeepSeek Harness 窗口与服务）：{0}" -f $_.Exception.Message)
            }
        } else {
            Write-Ok '便携运行时目录不存在，无需清理。'
        }
        Wait-ForClose '按回车键关闭窗口...'
        exit 0
    }

    # 快捷方式创建指令
    if ($env:DSH_SETUP_SHORTCUT -eq '1') {
        Write-Step '创建桌面快捷方式'
        $shortcutArgs = if ($env:DSH_SETUP_FAST -eq '1') { '--fast' } else { '' }
        $lnk = New-DesktopShortcut -Arguments $shortcutArgs
        if ($null -ne $lnk) {
            $modeDesc = if ($env:DSH_SETUP_FAST -eq '1') { '（包含 --fast 极速启动参数）' } else { '' }
            Write-Ok ("已在桌面创建快捷方式{0}：{1}" -f $modeDesc, $lnk)
        }
        Wait-ForClose '按回车键关闭窗口...'
        exit 0
    }

    Ensure-PortableNode
    $env:PATH = "$NodeRoot;$env:PATH"

    $npmVersion = (& $NpmCmd --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "npm 无法运行：$npmVersion"
    }
    Write-Info ("便携环境 npm 版本：{0}" -f $npmVersion)

    $dshVersion = Ensure-LatestDsh

    Write-Step '[3/3] 准备启动网页服务'
    if ($env:DSH_SETUP_INSTALL_ONLY -eq '1') {
        Write-Ok ("安装与环境校验已完成！当前 dsh 版本：{0}" -f $dshVersion)
        Write-Info ('后续随时可手动运行："{0}" web 启动服务。' -f $DshCmd)
        return
    }

    $port = Get-WebPort
    Show-Dashboard -Version $dshVersion -Port $port

    if ($env:DSH_SETUP_NO_OPEN -eq '1') {
        & $DshCmd web --port $port --no-open
    } else {
        & $DshCmd web --port $port
    }
    $webExitCode = $LASTEXITCODE
    # 正常退出码包括：0、130 (SIGINT/Ctrl+C)、-1073741510 (0xC000013A STATUS_CONTROL_C_EXIT) 等
    $isGracefulExit = ($webExitCode -eq 0 -or $webExitCode -eq 130 -or $webExitCode -eq -1073741510 -or $webExitCode -eq 3221225786)
    if (-not $isGracefulExit) {
        throw "DeepSeek Harness 服务异常停止，退出码：$webExitCode"
    }

    Write-Notice 'DeepSeek Harness 服务已安全停止。'
}

try {
    Main
    Wait-ForClose '按回车键关闭窗口...'
    exit 0
} catch {
    Write-Host ''
    Write-Fail ("运行遇到错误：{0}" -f $_.Exception.Message)
    Wait-ForClose '请查看上方错误信息，然后按回车键关闭窗口...'
    exit 1
}
