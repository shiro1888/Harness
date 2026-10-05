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
set "DSH_SETUP_LANG="
set "DSH_SETUP_BAD_ARG="

:parse_arguments
if "%~1"=="" goto run_installer
if /I "%~1"=="--install-only"    set "DSH_SETUP_INSTALL_ONLY=1" & shift & goto parse_arguments
if /I "%~1"=="--no-pause"        set "DSH_SETUP_NONINTERACTIVE=1" & shift & goto parse_arguments
if /I "%~1"=="--no-open"         set "DSH_SETUP_NO_OPEN=1" & shift & goto parse_arguments
if /I "%~1"=="--fast"            set "DSH_SETUP_FAST=1" & shift & goto parse_arguments
if /I "%~1"=="--skip-check"      set "DSH_SETUP_FAST=1" & shift & goto parse_arguments
if /I "%~1"=="--reinstall"       set "DSH_SETUP_REINSTALL=1" & shift & goto parse_arguments
if /I "%~1"=="--update"          set "DSH_SETUP_REINSTALL=1" & shift & goto parse_arguments
if /I "%~1"=="--clean"           set "DSH_SETUP_CLEAN=1" & shift & goto parse_arguments
if /I "%~1"=="--reset"           set "DSH_SETUP_CLEAN=1" & shift & goto parse_arguments
if /I "%~1"=="--create-shortcut" set "DSH_SETUP_SHORTCUT=1" & shift & goto parse_arguments
if /I "%~1"=="--shortcut"        set "DSH_SETUP_SHORTCUT=1" & shift & goto parse_arguments
if /I "%~1"=="--help"            set "DSH_SETUP_HELP=1" & shift & goto parse_arguments
if /I "%~1"=="-h"                set "DSH_SETUP_HELP=1" & shift & goto parse_arguments
if /I "%~1"=="--port"            goto parse_port
if /I "%~1"=="--lang"            goto parse_lang
if not defined DSH_SETUP_BAD_ARG set "DSH_SETUP_BAD_ARG=%~1"
shift
goto parse_arguments

:parse_port
set "_val=%~2"
if "%~2"=="" (
    if not defined DSH_SETUP_BAD_ARG set "DSH_SETUP_BAD_ARG=--port 缺少端口数值"
    shift
    goto parse_arguments
)
if "%_val:~0,1%"=="-" (
    if not defined DSH_SETUP_BAD_ARG set "DSH_SETUP_BAD_ARG=--port 缺少端口数值"
    shift
    goto parse_arguments
)
set "DSH_SETUP_PORT=%~2"
shift
shift
goto parse_arguments

:parse_lang
set "_val=%~2"
if "%~2"=="" (
    if not defined DSH_SETUP_BAD_ARG set "DSH_SETUP_BAD_ARG=--lang 缺少语言选项 (zh/en)"
    shift
    goto parse_arguments
)
if "%_val:~0,1%"=="-" (
    if not defined DSH_SETUP_BAD_ARG set "DSH_SETUP_BAD_ARG=--lang 缺少语言选项 (zh/en)"
    shift
    goto parse_arguments
)
set "DSH_SETUP_LANG=%~2"
shift
shift
goto parse_arguments

:run_installer
set "_val="
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

# ============================
# 国际化语言自适应与文本辅助
# ============================
$Global:IsEnglish = ($env:DSH_SETUP_LANG -eq 'en')
if (-not $Global:IsEnglish -and [string]::IsNullOrWhiteSpace($env:DSH_SETUP_LANG)) {
    try {
        $sysLang = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
        if ($sysLang -ne 'zh') {
            $Global:IsEnglish = $true
        }
    } catch {}
}

function T {
    param([string]$Zh, [string]$En)
    if ($Global:IsEnglish) { return $En }
    return $Zh
}

try {
    $Host.UI.RawUI.WindowTitle = T 'DeepSeek Harness 一键部署管理器' 'DeepSeek Harness Deployment Manager'
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
function Get-DisplayWidth {
    param([string]$Text)
    $w = 0
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        if ($code -ge 0x2500 -and $code -le 0x257F) {
            $w += 1
        } elseif ($code -gt 127) {
            $w += 2
        } else {
            $w += 1
        }
    }
    return $w
}

function Format-ElapsedText {
    param([int]$Milliseconds)
    if ($Milliseconds -ge 1000) {
        return ("{0:N1}s" -f ($Milliseconds / 1000))
    }
    return ("{0}ms" -f $Milliseconds)
}

function Write-BoxHeader {
    param(
        [string]$Title,
        [string]$BadgeText = "",
        [ConsoleColor]$BadgeBg = [ConsoleColor]::DarkCyan,
        [ConsoleColor]$BadgeFg = [ConsoleColor]::Black,
        [int]$TotalWidth = 66
    )
    Write-Host "  ┌─ " -ForegroundColor DarkCyan -NoNewline
    Write-Host $Title -ForegroundColor White -NoNewline
    if (-not [string]::IsNullOrWhiteSpace($BadgeText)) {
        Write-Host " " -NoNewline
        Write-Host " $BadgeText " -BackgroundColor $BadgeBg -ForegroundColor $BadgeFg -NoNewline
        Write-Host " " -ForegroundColor DarkCyan -NoNewline
        $len = 5 + (Get-DisplayWidth $Title) + 1 + (Get-DisplayWidth " $BadgeText ") + 1
    } else {
        Write-Host " " -ForegroundColor DarkCyan -NoNewline
        $len = 5 + (Get-DisplayWidth $Title) + 1
    }
    $rem = [Math]::Max(3, ($TotalWidth - $len))
    Write-Host ("─" * $rem) -ForegroundColor DarkCyan
}

function Write-BoxDivider {
    param(
        [string]$Title = "",
        [int]$TotalWidth = 66
    )
    if ([string]::IsNullOrWhiteSpace($Title)) {
        Write-Host "  ├" -ForegroundColor DarkCyan -NoNewline
        Write-Host ("─" * ($TotalWidth - 3)) -ForegroundColor DarkCyan
    } else {
        Write-Host "  ├─ " -ForegroundColor DarkCyan -NoNewline
        Write-Host $Title -ForegroundColor Gray -NoNewline
        Write-Host " " -ForegroundColor DarkCyan -NoNewline
        $len = 5 + (Get-DisplayWidth $Title) + 1
        $rem = [Math]::Max(3, ($TotalWidth - $len))
        Write-Host ("─" * $rem) -ForegroundColor DarkCyan
    }
}

$Global:InPipeline = $false

function Write-TimedLine {
    param(
        [string]$Prefix,
        [string]$Title,
        [int]$ElapsedMs,
        [int]$TargetWidth = 66
    )
    $cleanPrefix = $Prefix.TrimStart()
    $isSub = ($Prefix -match '^\s*[├└]─')
    $renderedPrefix = if ($isSub) { "  │  │  $cleanPrefix" } else { "  │  $cleanPrefix" }
    $w = Get-DisplayWidth "$renderedPrefix$Title"
    $dots = "." * [Math]::Max(3, ($TargetWidth - $w))
    $timeText = Format-ElapsedText $ElapsedMs

    if ($isSub) {
        Write-Host "  │  │  " -ForegroundColor DarkCyan -NoNewline
        Write-Host $cleanPrefix -ForegroundColor DarkGray -NoNewline
        Write-Host $Title -ForegroundColor Gray -NoNewline
    } else {
        Write-Host "  │  " -ForegroundColor DarkCyan -NoNewline
        Write-Host $cleanPrefix -ForegroundColor Cyan -NoNewline
        Write-Host $Title -ForegroundColor White -NoNewline
    }
    Write-Host " $dots " -ForegroundColor DarkGray -NoNewline
    Write-Host "[✓ $timeText]" -ForegroundColor Green
}

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host '  ● ' -ForegroundColor Cyan -NoNewline
    Write-Host $Text -ForegroundColor White
}

function Write-Ok {
    param([string]$Text)
    if ($Global:InPipeline) {
        Write-Host '  │  │  ├─ ' -ForegroundColor DarkCyan -NoNewline
        Write-Host '[✓] ' -ForegroundColor Green -NoNewline
        Write-Host $Text -ForegroundColor White
    } else {
        Write-Host '    ├─ ' -ForegroundColor DarkGray -NoNewline
        Write-Host '[✓] ' -ForegroundColor Green -NoNewline
        Write-Host $Text -ForegroundColor White
    }
}

function Write-Info {
    param([string]$Text)
    if ($Global:InPipeline) {
        Write-Host '  │  │  ├─ ' -ForegroundColor DarkCyan -NoNewline
        Write-Host '[i] ' -ForegroundColor Cyan -NoNewline
        Write-Host $Text -ForegroundColor Gray
    } else {
        Write-Host '    ├─ ' -ForegroundColor DarkGray -NoNewline
        Write-Host '[i] ' -ForegroundColor Cyan -NoNewline
        Write-Host $Text -ForegroundColor Gray
    }
}

function Write-Notice {
    param([string]$Text)
    if ($Global:InPipeline) {
        Write-Host '  │  │  ├─ ' -ForegroundColor DarkCyan -NoNewline
        Write-Host '[!] ' -ForegroundColor Yellow -NoNewline
        Write-Host $Text -ForegroundColor Yellow
    } else {
        Write-Host '    ├─ ' -ForegroundColor DarkGray -NoNewline
        Write-Host '[!] ' -ForegroundColor Yellow -NoNewline
        Write-Host $Text -ForegroundColor Yellow
    }
}

function Write-Fail {
    param([string]$Text)
    Write-Host '    └─ ' -ForegroundColor DarkGray -NoNewline
    Write-Host '[×] ' -ForegroundColor Red -NoNewline
    Write-Host $Text -ForegroundColor Red
}

function Test-VcRedistInstalled {
    $paths = @(
        (Join-Path $env:SystemRoot "System32\vcruntime140.dll"),
        (Join-Path $env:SystemRoot "SysWOW64\vcruntime140.dll")
    )
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p -PathType Leaf) { return $true }
    }
    $regKeys = @(
        "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64",
        "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x86",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"
    )
    foreach ($k in $regKeys) {
        if (Test-Path -LiteralPath $k) { return $true }
    }
    return $false
}

function Show-QuickActionMenu {
    if ($env:DSH_SETUP_NONINTERACTIVE -eq '1') { return $null }
    try {
        if ([Console]::IsInputRedirected) { return $null }
    } catch { return $null }

    if ($env:DSH_SETUP_FAST -eq '1' -or $env:DSH_SETUP_REINSTALL -eq '1' -or $env:DSH_SETUP_CLEAN -eq '1' -or $env:DSH_SETUP_SHORTCUT -eq '1' -or $env:DSH_SETUP_INSTALL_ONLY -eq '1') {
        return $null
    }

    Write-BoxHeader -Title (T '快捷操作面板' 'Quick Action Panel') -BadgeText 'QUICK ACTION' -BadgeBg DarkCyan -BadgeFg Black
    Write-Host '  │  ' -ForegroundColor DarkCyan -NoNewline
    Write-Host ' Enter ' -BackgroundColor Cyan -ForegroundColor Black -NoNewline
    Write-Host (T ' 正常启动     ' ' Start Normal     ') -ForegroundColor Gray -NoNewline
    Write-Host ' F ' -BackgroundColor DarkCyan -ForegroundColor Black -NoNewline
    Write-Host (T ' 极速秒启     ' ' Fast Launch     ') -ForegroundColor Gray -NoNewline
    Write-Host ' R ' -BackgroundColor DarkYellow -ForegroundColor Black -NoNewline
    Write-Host (T ' 强制重装' ' Reinstall') -ForegroundColor Gray
    Write-Host '  │  ' -ForegroundColor DarkCyan -NoNewline
    Write-Host ' C ' -BackgroundColor DarkMagenta -ForegroundColor White -NoNewline
    Write-Host (T ' 清理重置    ' ' Clean/Reset    ') -ForegroundColor Gray -NoNewline
    Write-Host ' S ' -BackgroundColor DarkGreen -ForegroundColor White -NoNewline
    Write-Host (T ' 桌面快捷    ' ' Shortcut       ') -ForegroundColor Gray -NoNewline
    Write-Host ' H ' -BackgroundColor DarkGray -ForegroundColor White -NoNewline
    Write-Host (T ' 帮助手册    ' ' Help Manual    ') -ForegroundColor Gray -NoNewline
    Write-Host ' Q ' -BackgroundColor DarkRed -ForegroundColor White -NoNewline
    Write-Host (T ' 安全退出' ' Exit') -ForegroundColor Gray
    Write-Host '  │' -ForegroundColor DarkCyan

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $selectedKey = $null

    while ($sw.Elapsed.TotalSeconds -lt 3) {
        $remaining = [Math]::Max(0.0, 3.0 - $sw.Elapsed.TotalSeconds)
        $filled = [int][Math]::Round(16 * ($remaining / 3.0))
        $empty = 16 - $filled
        Write-Host "`r  │  " -NoNewline -ForegroundColor DarkCyan
        Write-Host (T '倒计时 ' 'Countdown ') -NoNewline -ForegroundColor Gray
        Write-Host '❯ ' -NoNewline -ForegroundColor Cyan
        Write-Host '[' -NoNewline -ForegroundColor DarkGray
        Write-Host ('■' * $filled) -NoNewline -ForegroundColor Cyan
        Write-Host ('·' * $empty) -NoNewline -ForegroundColor DarkGray
        Write-Host ("] {0:N1}s  " -f $remaining) -NoNewline -ForegroundColor White

        try {
            if ([Console]::KeyAvailable) {
                $keyInfo = [Console]::ReadKey($true)
                if ($keyInfo.Key -eq [ConsoleKey]::Escape) {
                    $selectedKey = 'q'
                    break
                }
                $selectedKey = [string]$keyInfo.KeyChar
                break
            }
        } catch { break }
        Start-Sleep -Milliseconds 60
    }

    $desc = switch -Regex ($selectedKey) {
        '(?i)f' { T '极速秒启模式 (Fast Launch)' 'Fast Launch Mode' }
        '(?i)r' { T '强制重装模式 (Force Reinstall)' 'Force Reinstall Mode' }
        '(?i)c' { T '清理便携环境 (Clean & Reset)' 'Clean & Reset Mode' }
        '(?i)s' { T '创建桌面快捷方式 (Create Shortcut)' 'Create Desktop Shortcut' }
        '(?i)h' { T '查看命令帮助文档 (Command Help)' 'Show Help Manual' }
        '(?i)q' { T '操作已取消，安全退出 (Exiting)' 'Operation Canceled, Exiting' }
        default { T '默认正常启动 (Normal Launch)' 'Default Normal Launch' }
    }
    Write-Host "`r  │  " -NoNewline -ForegroundColor DarkCyan
    Write-Host (T '模式选定 ' 'Selected ') -NoNewline -ForegroundColor Gray
    Write-Host '❯ ' -NoNewline -ForegroundColor Cyan
    Write-Host ("{0}" -f $desc).PadRight(44) -ForegroundColor White
    Write-Host '  └───────────────────────────────────────────────────────────────' -ForegroundColor DarkCyan
    Write-Host ''

    return $selectedKey
}

function Start-WebHeartbeatPing {
    param([int]$Port)
    try {
        $rs = [RunspaceFactory]::CreateRunspace()
        $rs.Open()
        $ps = [PowerShell]::Create()
        $ps.Runspace = $rs
        $null = $ps.AddScript({
            param($p, $isEn)
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt 15) {
                Start-Sleep -Milliseconds 600
                try {
                    $req = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$p/")
                    $req.Timeout = 1000
                    $resp = $req.GetResponse()
                    if ($null -ne $resp) {
                        $resp.Close()
                        Write-Host ''
                        Write-Host '  ● ' -ForegroundColor Green -NoNewline
                        $msg = if ($isEn) {
                            ("Web heartbeat alive: local HTTP responded in {0:N1}s." -f $sw.Elapsed.TotalSeconds)
                        } else {
                            ("Web 活跃心跳探测正常：本地 HTTP 服务已于 {0:N1}s 成功握手响应。" -f $sw.Elapsed.TotalSeconds)
                        }
                        Write-Host $msg -ForegroundColor White
                        break
                    }
                } catch {}
            }
        }).AddArgument($Port).AddArgument($Global:IsEnglish)
        $null = $ps.BeginInvoke()
    } catch {}
}

function Get-LocalLanIp {
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Wi-Fi*", "以太网*", "Ethernet*", "WLAN*", "本地连接*" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -notmatch "^(169\.254|127\.)" -and
                $_.PrefixOrigin -ne "WellKnown" -and
                $_.InterfaceAlias -notmatch "(vEthernet|VirtualBox|VMware|WSL|Tailscale|ZeroTier)"
            } |
            Select-Object -First 1).IPAddress
        if (-not $ip) {
            $ip = ([System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
                Where-Object { $_.AddressFamily -eq "InterNetwork" -and $_.IPAddressToString -notmatch "^(127\.|169\.254)" } |
                Select-Object -First 1).IPAddressToString
        }
        return $ip
    } catch {
        return $null
    }
}

function Get-HardwareSpecSummary {
    try {
        $cores = $env:NUMBER_OF_PROCESSORS
        $memGb = $null
        try {
            $ram = Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | Measure-Object -Property Capacity -Sum
            if ($ram -and $ram.Sum -gt 0) {
                $memGb = [Math]::Round($ram.Sum / 1GB)
            }
        } catch {}
        if ($memGb) {
            return ("{0}C · {1}G" -f $cores, $memGb)
        } elseif ($cores) {
            return ("{0} Cores" -f $cores)
        }
    } catch {}
    return $null
}

function Show-StatusCard {
    param(
        [string]$Arch,
        [string]$NodeVer,
        [string]$DshVer,
        [string]$MirrorSource
    )
    $hwSpec = Get-HardwareSpecSummary
    $archText = if ($hwSpec) { ("Win ({0} · {1})" -f $Arch, $hwSpec) } else { ("Windows ({0})" -f $Arch) }

    Write-BoxHeader -Title (T '运行状态看板' 'Runtime Matrix') -BadgeText 'ACTIVE' -BadgeBg DarkCyan -BadgeFg Black
    Write-Host '  │  ' -ForegroundColor DarkCyan -NoNewline
    Write-Host (T '系统架构 ' 'Platform ') -ForegroundColor Gray -NoNewline
    Write-Host '❯ ' -ForegroundColor Cyan -NoNewline
    Write-Host $archText.PadRight(21) -ForegroundColor White -NoNewline
    Write-Host (T '便携引擎 ' 'Runtime  ') -ForegroundColor Gray -NoNewline
    Write-Host '❯ ' -ForegroundColor Cyan -NoNewline
    Write-Host ("Node.js {0}" -f $NodeVer) -ForegroundColor White
    Write-Host '  │  ' -ForegroundColor DarkCyan -NoNewline
    Write-Host (T '核心版本 ' 'Version  ') -ForegroundColor Gray -NoNewline
    Write-Host '❯ ' -ForegroundColor Cyan -NoNewline
    Write-Host ("v{0}" -f $DshVer).PadRight(21) -ForegroundColor Cyan -NoNewline
    Write-Host (T '网络加速 ' 'Mirror   ') -ForegroundColor Gray -NoNewline
    Write-Host '❯ ' -ForegroundColor Cyan -NoNewline
    Write-Host ("{0}" -f $MirrorSource) -ForegroundColor Green
    Write-Host '  └───────────────────────────────────────────────────────────────' -ForegroundColor DarkCyan
    Write-Host ''
}

function Show-Banner {
    $verText = Get-InstalledDshVersion
    $verBadge = if ($verText) { "v$verText" } else { "Installer" }

    Write-Host ''
    Write-Host "    ____                  ____            _    " -ForegroundColor Cyan
    Write-Host "   |  _ \  ___  ___ _ __ / ___|  ___  ___| | __" -ForegroundColor Cyan
    Write-Host "   | | | |/ _ \/ _ \ '_ \ \___ \ / _ \/ _ \ |/ /" -ForegroundColor DarkCyan
    Write-Host "   | |_| |  __/  __/ |_) |___) |  __/  __/   < " -ForegroundColor DarkCyan
    Write-Host "   |____/ \___|\___| .__/ |____/ \___|\___|_|\_\" -ForegroundColor Blue
    Write-Host "                   |_|   " -NoNewline -ForegroundColor Blue
    Write-Host "H A R N E S S        " -NoNewline -ForegroundColor White
    Write-Host $verBadge -ForegroundColor Cyan
    Write-Host ''
    Write-BoxHeader -Title (T '一键极速部署管理器' 'One-Click Deployment Manager') -BadgeText 'PORTABLE' -BadgeBg Cyan -BadgeFg Black
    Write-Host '  │  ' -ForegroundColor DarkCyan -NoNewline
    Write-Host '●' -ForegroundColor Cyan -NoNewline
    Write-Host (T ' 便携运行环境  ' ' Portable Runtime  ') -ForegroundColor Gray -NoNewline
    Write-Host '●' -ForegroundColor Cyan -NoNewline
    Write-Host (T ' 自动镜像加速  ' ' Mirror Accelerated  ') -ForegroundColor Gray -NoNewline
    Write-Host '●' -ForegroundColor Cyan -NoNewline
    Write-Host (T ' 原生依赖自检  ' ' Native Probes  ') -ForegroundColor Gray -NoNewline
    Write-Host '●' -ForegroundColor Cyan -NoNewline
    Write-Host (T ' 双端局域网访问' ' Dual-Network Ready') -ForegroundColor Gray
    Write-Host '  └───────────────────────────────────────────────────────────────' -ForegroundColor DarkCyan
    Write-Host ''
}

function Show-Dashboard {
    param(
        [string]$Version,
        [int]$Port
    )
    $lanIp = Get-LocalLanIp

    Write-Host ''
    Write-BoxHeader -Title (T '网页服务就绪' 'Service Ready') -BadgeText 'ONLINE' -BadgeBg Green -BadgeFg Black
    Write-Host '  │' -ForegroundColor DarkCyan
    Write-Host '  │  ' -ForegroundColor DarkCyan -NoNewline
    Write-Host '▌ ' -ForegroundColor Cyan -NoNewline
    Write-Host (T '本机电脑访问 (Local PC)' 'Local PC Access') -ForegroundColor White
    Write-Host '  │    ' -ForegroundColor DarkCyan -NoNewline
    Write-Host ("http://127.0.0.1:{0}" -f $Port) -ForegroundColor Cyan
    if ($lanIp) {
        Write-Host '  │' -ForegroundColor DarkCyan
        Write-Host '  │  ' -ForegroundColor DarkCyan -NoNewline
        Write-Host '▌ ' -ForegroundColor Green -NoNewline
        Write-Host (T '手机/平板/局域网访问 (Mobile & LAN)' 'Mobile & LAN Access') -ForegroundColor White
        Write-Host '  │    ' -ForegroundColor DarkCyan -NoNewline
        Write-Host ("http://{0}:{1}" -f $lanIp, $Port) -ForegroundColor Green -NoNewline
        Write-Host (T '  (同一 Wi-Fi 局域网可用)' '  (Same Wi-Fi network)') -ForegroundColor DarkGray
    }
    Write-Host '  │' -ForegroundColor DarkCyan
    Write-BoxDivider -Title (T '快捷使用指引' 'Quick Guide')
    Write-Host '  │  • ' -ForegroundColor DarkCyan -NoNewline
    Write-Host (T '自动唤醒 ' 'Browser   ') -ForegroundColor Gray -NoNewline
    Write-Host '❯ ' -ForegroundColor Cyan -NoNewline
    Write-Host (T '默认浏览器已自动尝试打开，亦可点击上方链接访问' 'Default browser opened automatically, or click above URL') -ForegroundColor DarkGray
    Write-Host '  │  • ' -ForegroundColor DarkCyan -NoNewline
    Write-Host (T '令牌认证 ' 'Token     ') -ForegroundColor Gray -NoNewline
    Write-Host '❯ ' -ForegroundColor Cyan -NoNewline
    Write-Host (T '如首次进入需登录，请复制下方日志中包含 ?token= 的完整网址' 'If authentication is required, copy full URL with ?token= below') -ForegroundColor DarkGray
    if ($lanIp) {
        Write-Host '  │  • ' -ForegroundColor DarkCyan -NoNewline
        Write-Host (T '手机访问 ' 'Mobile    ') -ForegroundColor Gray -NoNewline
        Write-Host '❯ ' -ForegroundColor Cyan -NoNewline
        Write-Host (T '手机与电脑连接同一 Wi-Fi 即可打开；若超时请放行防火墙' 'Connect same Wi-Fi; check Windows Firewall if unreachable') -ForegroundColor DarkGray
    }
    Write-Host '  │  • ' -ForegroundColor DarkCyan -NoNewline
    Write-Host (T '服务保持 ' 'Control   ') -ForegroundColor Gray -NoNewline
    Write-Host '❯ ' -ForegroundColor Cyan -NoNewline
    Write-Host (T '请保持此窗口常驻运行；按 Ctrl + C 可安全停止服务' 'Keep this window running; press Ctrl + C to stop server') -ForegroundColor DarkGray
    Write-Host '  └───────────────────────────────────────────────────────────────' -ForegroundColor DarkCyan
    Write-Host ''
}

function Show-Help {
    Write-Host ''
    Write-BoxHeader -Title (T '命令参数说明' 'Command Line Manual') -BadgeText 'MANUAL' -BadgeBg DarkCyan -BadgeFg Black
    Write-Host '  │  ' -ForegroundColor DarkCyan -NoNewline
    Write-Host (T '用法: ' 'Usage: ') -ForegroundColor Gray -NoNewline
    Write-Host (T 'dsh-setup.bat [选项]' 'dsh-setup.bat [options]') -ForegroundColor White
    Write-Host '  │' -ForegroundColor DarkCyan
    Write-BoxDivider -Title (T '可用选项列表' 'Available Options')
    Write-Host (T '  │    --install-only        仅安装/更新并完成依赖自检，不启动网页服务' '  │    --install-only        Install/update and probe, without starting web') -ForegroundColor Gray
    Write-Host (T '  │    --fast, --skip-check  极速模式：跳过在线版本检查，直接秒启本地已有版本' '  │    --fast, --skip-check  Fast mode: skip update checks, launch instantly') -ForegroundColor Gray
    Write-Host (T '  │    --reinstall, --update 强制重装模式：重新拉取最新版本并校验原生依赖' '  │    --reinstall, --update Force reinstall: re-fetch and rebuild dependencies') -ForegroundColor Gray
    Write-Host (T '  │    --clean, --reset      清理并重置便携运行时目录（dsh-runtime）' '  │    --clean, --reset      Clean and reset portable runtime directory') -ForegroundColor Gray
    Write-Host (T '  │    --create-shortcut     在当前用户桌面创建一键启动快捷方式并退出' '  │    --create-shortcut     Create desktop shortcut and exit') -ForegroundColor Gray
    Write-Host (T '  │    --port <端口号>       指定 Web 服务端口（默认 3080，被占用则自动顺延）' '  │    --port <number>       Specify web port (default 3080, auto fallback)') -ForegroundColor Gray
    Write-Host (T '  │    --lang <zh|en>        切换语言界面（默认随操作系统自动自适应）' '  │    --lang <zh|en>        Switch UI language (default: system locale)') -ForegroundColor Gray
    Write-Host (T '  │    --no-open             启动服务后不自动调用浏览器打开网页' '  │    --no-open             Do not open browser automatically') -ForegroundColor Gray
    Write-Host (T '  │    --no-pause            自动化脚本模式，执行完毕后不等待用户按回车' '  │    --no-pause            Non-interactive mode, do not wait for enter key') -ForegroundColor Gray
    Write-Host (T '  │    --help, -h            显示此帮助信息' '  │    --help, -h            Show this help manual') -ForegroundColor Gray
    Write-Host '  └───────────────────────────────────────────────────────────────' -ForegroundColor DarkCyan
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
        $shortcut.Description = (T 'DeepSeek Harness 一键启动' 'DeepSeek Harness One-Click Launcher')
        if (Test-Path -LiteralPath $NodeExe -PathType Leaf) {
            $shortcut.IconLocation = "$NodeExe,0"
        }
        $shortcut.Save()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
        return $shortcutPath
    } catch {
        Write-Notice (T ("创建桌面快捷方式失败：{0}" -f $_.Exception.Message) ("Failed to create desktop shortcut: {0}" -f $_.Exception.Message))
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
        # 异常情况下安全回退到 Invoke-RestMethod
        foreach ($target in @(@($OfficialRegistry, 'npm 官方仓库'), @($MirrorRegistry, '国内 npm 镜像'))) {
            try {
                $meta = Invoke-RestMethod -Uri "$($target[0])/@deepseek-ai%2Fdsh" -TimeoutSec 5 -Headers @{ Accept = 'application/vnd.npm.install-v1+json' }
                $lat = [string]$meta.'dist-tags'.latest
                if (-not [string]::IsNullOrWhiteSpace($lat)) {
                    $obj = [pscustomobject]@{ Name = $target[1]; Registry = $target[0]; Latest = $lat }
                    if ($target[0] -eq $OfficialRegistry) { $officialRes = $obj } else { $mirrorRes = $obj }
                }
            } catch {}
        }
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
    $swNode = [Diagnostics.Stopwatch]::StartNew()
    $architecture = Get-MachineArchitecture
    if ((Test-Path -LiteralPath $NodeExe -PathType Leaf) -and (Test-Path -LiteralPath $NpmCmd -PathType Leaf)) {
        try {
            $version = (& $NodeExe --version 2>&1 | Out-String).Trim()
            $npmVer = (& $NpmCmd --version 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -eq 0 -and $version -match '^v\d+\.\d+\.\d+$' -and -not [string]::IsNullOrWhiteSpace($npmVer)) {
                $swNode.Stop()
                Write-TimedLine -Prefix "  ● [1/3] " -Title (T ("便携 Node.js 运行时就绪 ({0} {1})" -f $version, $architecture) ("Portable Node.js runtime ready ({0} {1})" -f $version, $architecture)) -ElapsedMs $swNode.ElapsedMilliseconds
                return [pscustomobject]@{ Version = $version; Architecture = $architecture }
            }
        } catch {
            Write-Notice (T '现有便携 Node.js 无法运行，正在自动重新准备。' 'Existing portable Node.js failed to run, re-preparing automatically.')
        }
    }

    Install-PortableNode -Architecture $architecture
    $swNode.Stop()
    $version = (& $NodeExe --version 2>&1 | Out-String).Trim()
    Write-TimedLine -Prefix "  ● [1/3] " -Title (T ("便携 Node.js 安装部署完成 ({0} {1})" -f $version, $architecture) ("Portable Node.js installation complete ({0} {1})" -f $version, $architecture)) -ElapsedMs $swNode.ElapsedMilliseconds
    return [pscustomobject]@{ Version = $version; Architecture = $architecture }
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
    $swDsh = [Diagnostics.Stopwatch]::StartNew()

    New-Item -ItemType Directory -Path $RuntimeRoot -Force | Out-Null
    $npmConfigText = [string]::Join([Environment]::NewLine, @('fund=false', 'audit=false', 'update-notifier=false', ''))
    [IO.File]::WriteAllText($NpmConfig, $npmConfigText, $utf8)

    $installed = Get-InstalledDshVersion

    $swNet = [Diagnostics.Stopwatch]::StartNew()
    $release = Get-LatestDshRelease -InstalledVersion $installed
    $swNet.Stop()

    if ($null -eq $release) {
        throw (T '无法连接 npm 官方仓库或国内镜像，且本机暂无可用安装版本。请检查网络或代理设置。' 'Cannot connect to npm official or mirror registry, and no local installation found. Please check network/proxy.')
    }

    if (-not $release.Skipped) {
        Write-TimedLine -Prefix "    ├─ " -Title (T "npm 官方与国内镜像并发竞速" "npm official & mirror parallel race") -ElapsedMs $swNet.ElapsedMilliseconds
    }

    $expectedVersion = $release.Latest
    $forceReinstall = ($env:DSH_SETUP_REINSTALL -eq '1')
    if ($release.Skipped -and -not $forceReinstall) {
        # 跳过在线更新或进入离线模式
    } elseif ($installed -eq $release.Latest -and (Test-Path -LiteralPath $DshCmd -PathType Leaf) -and -not $forceReinstall) {
        # 已是最新版
    } else {
        if ($forceReinstall -and ($installed -eq $release.Latest)) {
            Write-Info (T ("强制重装模式：正在重新部署当前最新版本 {0}..." -f $release.Latest) ("Force reinstall: redeploying latest version {0}..." -f $release.Latest))
        } elseif ($null -eq $installed) {
            Write-Info (T ("正在通过{0}安装 {1}，首次安装需拉取并配置依赖，请稍候..." -f $release.Source, $release.Latest) ("Installing {1} via {0}, please wait..." -f $release.Source, $release.Latest))
        } else {
            Write-Info (T ("正在通过{0}把版本从 {1} 更新至 {2}..." -f $release.Source, $installed, $release.Latest) ("Updating version from {1} to {2} via {0}..." -f $release.Source, $installed, $release.Latest))
        }

        $swInstall = [Diagnostics.Stopwatch]::StartNew()
        $exitCode = Invoke-DshInstall -Version $release.Latest -Registry $release.Registry
        if ($exitCode -ne 0 -and $release.FallbackRegistry -and $release.FallbackRegistry -ne $release.Registry) {
            Write-Notice (T '国内镜像安装遇到异常，正在改用 npm 官方仓库自动重试...' 'Mirror install encountered an issue, retrying with official npm registry...')
            $exitCode = Invoke-DshInstall -Version $release.Latest -Registry $release.FallbackRegistry
        }
        $swInstall.Stop()
        if ($exitCode -ne 0) {
            throw "npm 安装 dsh 失败，退出码：$exitCode"
        }
        Write-TimedLine -Prefix "    ├─ " -Title (T ("拉取并安装核心组件 (v{0})" -f $release.Latest) ("Fetch and install core package (v{0})" -f $release.Latest)) -ElapsedMs $swInstall.ElapsedMilliseconds
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
    $swProbe = [Diagnostics.Stopwatch]::StartNew()
    $runtimeProbe = Test-DshRuntimeDependencies
    if (-not $runtimeProbe.Ok) {
        Write-Notice (T ("运行依赖自检未通过，正在尝试自动修复：{0}" -f $runtimeProbe.Message) ("Runtime probe failed, attempting automatic repair: {0}" -f $runtimeProbe.Message))
        $rebuildExit = Invoke-DshRebuild
        if ($rebuildExit -ne 0) {
            throw "dsh 依赖修复失败，npm 退出码：$rebuildExit"
        }
        $runtimeProbe = Test-DshRuntimeDependencies
        if (-not $runtimeProbe.Ok) {
            throw (T ("dsh 依赖修复后仍未通过自检：{0}。如缺少 VC++ 运行库，请安装：https://aka.ms/vs/17/release/vc_redist.x64.exe" -f $runtimeProbe.Message) ("dsh probe failed after rebuild: {0}. If VC++ runtime is missing, install: https://aka.ms/vs/17/release/vc_redist.x64.exe" -f $runtimeProbe.Message))
        }
    }
    $swProbe.Stop()
    Write-TimedLine -Prefix "    └─ " -Title (T "Koffi 原生模块与 Windows 伪终端自检" "Koffi native module & Windows PTY probe") -ElapsedMs $swProbe.ElapsedMilliseconds

    $swDsh.Stop()
    Write-TimedLine -Prefix "  ● [2/3] " -Title (T ("DeepSeek Harness 核心组件就绪 (v{0})" -f $verifiedVersion) ("DeepSeek Harness core package ready (v{0})" -f $verifiedVersion)) -ElapsedMs $swDsh.ElapsedMilliseconds

    return [pscustomobject]@{
        Version = $verifiedVersion
        Source  = if ($release.Skipped) { (T '离线模式' 'Offline mode') } else { $release.Source }
    }
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
            throw (T "指定的端口数值无效：$($env:DSH_SETUP_PORT)" "Invalid port option: $($env:DSH_SETUP_PORT)")
        }
        if (-not (Test-LocalPortAvailable -Port $requested)) {
            throw (T "指定端口 $requested 已被占用，请更换端口后重试。" "Specified port $requested is already in use. Please choose another port.")
        }
        return $requested
    }

    foreach ($candidate in 3080..3099) {
        if (Test-LocalPortAvailable -Port $candidate) {
            if ($candidate -ne 3080) {
                Write-Notice (T ("默认端口 3080 已被占用，自动选择空闲端口 {0}。" -f $candidate) ("Default port 3080 is in use, switched to free port {0}." -f $candidate))
            }
            return $candidate
        }
    }

    throw (T '本地端口 3080 到 3099 均被占用，请关闭占用程序后重试。' 'Local ports 3080 to 3099 are all in use. Please close conflicting programs and retry.')
}

function Main {
    if ($env:DSH_SETUP_HELP -eq '1') {
        Show-Help
        exit 0
    }

    if (-not [string]::IsNullOrWhiteSpace($env:DSH_SETUP_BAD_ARG)) {
        throw (T "不支持的参数：$($env:DSH_SETUP_BAD_ARG)。请使用 --help 查看支持的完整参数列表。" "Unsupported parameter: $($env:DSH_SETUP_BAD_ARG). Use --help for full options.")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:DSH_SETUP_PORT)) {
        $validatedPort = 0
        if (-not [int]::TryParse($env:DSH_SETUP_PORT, [ref]$validatedPort) -or $validatedPort -lt 1 -or $validatedPort -gt 65535) {
            throw (T "端口参数数值无效：$($env:DSH_SETUP_PORT)（有效范围 1-65535）" "Invalid port parameter: $($env:DSH_SETUP_PORT) (Valid range: 1-65535)")
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:DSH_SETUP_LANG) -and $env:DSH_SETUP_LANG -ne 'zh' -and $env:DSH_SETUP_LANG -ne 'en') {
        throw (T "语言参数仅支持 zh 或 en：$($env:DSH_SETUP_LANG)" "Language parameter only supports zh or en: $($env:DSH_SETUP_LANG)")
    }

    Set-Location -LiteralPath $SetupRoot
    Show-Banner

    # 交互模式下的 3 秒快速操作面板
    $quickAction = Show-QuickActionMenu
    if ($null -ne $quickAction) {
        switch ($quickAction.ToLower()) {
            'f' { $env:DSH_SETUP_FAST = '1' }
            'r' { $env:DSH_SETUP_REINSTALL = '1' }
            'c' { $env:DSH_SETUP_CLEAN = '1' }
            's' { $env:DSH_SETUP_SHORTCUT = '1' }
            'h' { Show-Help; exit 0 }
            'q' { exit 0 }
        }
    }

    # 清理重置便携运行时指令
    if ($env:DSH_SETUP_CLEAN -eq '1') {
        Write-Step (T '清理便携运行时环境' 'Clean Portable Runtime Environment')
        if (Test-Path -LiteralPath $RuntimeRoot) {
            Write-Info (T ("正在清理目录：{0}..." -f $RuntimeRoot) ("Cleaning directory: {0}..." -f $RuntimeRoot))
            try {
                Remove-Item -LiteralPath $RuntimeRoot -Recurse -Force
                Write-Ok (T '便携运行时已彻底清理完成。下次运行将重新进行全新部署。' 'Portable runtime cleaned. Fresh deployment on next run.')
            } catch {
                Write-Fail (T ("清理失败（请先确保关闭正在运行的 DeepSeek Harness 窗口与服务）：{0}" -f $_.Exception.Message) ("Cleanup failed: {0}" -f $_.Exception.Message))
            }
        } else {
            Write-Ok (T '便携运行时目录不存在，无需清理。' 'Portable runtime does not exist, nothing to clean.')
        }
        Wait-ForClose (T '按回车键关闭窗口...' 'Press Enter to exit...')
        exit 0
    }

    # 快捷方式创建指令
    if ($env:DSH_SETUP_SHORTCUT -eq '1') {
        Write-Step (T '创建桌面快捷方式' 'Create Desktop Shortcut')
        $shortcutArgs = if ($env:DSH_SETUP_FAST -eq '1') { '--fast' } else { '' }
        $lnk = New-DesktopShortcut -Arguments $shortcutArgs
        if ($null -ne $lnk) {
            $modeDesc = if ($env:DSH_SETUP_FAST -eq '1') { (T '（包含 --fast 极速启动参数）' ' (with --fast arg)') } else { '' }
            Write-Ok (T ("已在桌面创建快捷方式{0}：{1}" -f $modeDesc, $lnk) ("Shortcut created{0}: {1}" -f $modeDesc, $lnk))
        }
        Wait-ForClose (T '按回车键关闭窗口...' 'Press Enter to exit...')
        exit 0
    }

    # Visual C++ 运行库健康体检
    if (-not (Test-VcRedistInstalled)) {
        Write-Notice (T '未检测到 Visual C++ 2015-2022 运行库，如遇启动异常请安装：https://aka.ms/vs/17/release/vc_redist.x64.exe' 'Visual C++ runtime not detected. If native probes fail, install: https://aka.ms/vs/17/release/vc_redist.x64.exe')
    }

    Write-BoxHeader -Title (T '部署流水线' 'Deployment Pipeline') -BadgeText 'PIPELINE' -BadgeBg DarkCyan -BadgeFg Black
    Write-Host '  │' -ForegroundColor DarkCyan
    $Global:InPipeline = $true

    $nodeMeta = Ensure-PortableNode
    $env:PATH = "$NodeRoot;$env:PATH"

    $npmVersion = (& $NpmCmd --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "npm 无法运行：$npmVersion"
    }

    Write-Host '  │  │' -ForegroundColor DarkCyan
    $dshMeta = Ensure-LatestDsh
    $dshVersion = $dshMeta.Version

    if ($env:DSH_SETUP_INSTALL_ONLY -eq '1') {
        Write-Host '  │  │' -ForegroundColor DarkCyan
        Write-TimedLine -Prefix "  ● [3/3] " -Title (T '安装校验模式完成（不启动网页服务）' 'Installation verified (service not started)') -ElapsedMs 0
        Write-Host '  │' -ForegroundColor DarkCyan
        Write-Host '  └───────────────────────────────────────────────────────────────' -ForegroundColor DarkCyan
        Write-Host ''
        $Global:InPipeline = $false
        Show-StatusCard -Arch $nodeMeta.Architecture -NodeVer $nodeMeta.Version -DshVer $dshVersion -MirrorSource $dshMeta.Source
        Write-Info (T ('后续随时可手动运行："{0}" web 启动服务。' -f $DshCmd) ('Run "{0}" web to start server anytime.' -f $DshCmd))
        return
    }

    Write-Host '  │  │' -ForegroundColor DarkCyan
    $swPort = [Diagnostics.Stopwatch]::StartNew()
    $port = Get-WebPort
    $swPort.Stop()
    Write-TimedLine -Prefix "  ● [3/3] " -Title (T ("本地 Web 服务端口就绪 (Port {0})" -f $port) ("Local web port ready (Port {0})" -f $port)) -ElapsedMs $swPort.ElapsedMilliseconds
    Write-Host '  │' -ForegroundColor DarkCyan
    Write-Host '  └───────────────────────────────────────────────────────────────' -ForegroundColor DarkCyan
    Write-Host ''
    $Global:InPipeline = $false

    Show-StatusCard -Arch $nodeMeta.Architecture -NodeVer $nodeMeta.Version -DshVer $dshVersion -MirrorSource $dshMeta.Source
    Show-Dashboard -Version $dshVersion -Port $port

    # 启动后台异步 Web 活跃心跳探测
    Start-WebHeartbeatPing -Port $port

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

    Write-Notice (T 'DeepSeek Harness 服务已安全停止。' 'DeepSeek Harness service stopped safely.')
}

try {
    Main
    Wait-ForClose (T '按回车键关闭窗口...' 'Press Enter to exit...')
    exit 0
} catch {
    $Global:InPipeline = $false
    Write-Host ''
    Write-Fail (T ("运行遇到错误：{0}" -f $_.Exception.Message) ("Execution error: {0}" -f $_.Exception.Message))
    Wait-ForClose (T '请查看上方错误信息，然后按回车键关闭窗口...' 'Please check error message above, then press Enter to exit...')
    exit 1
}
