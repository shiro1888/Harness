# DeepSeek Harness 一键部署器（Windows）

一个单文件 `.bat`：在没有 Git、没有 Node.js、没有管理员权限的 Windows 电脑上，双击就能装好并启动 DeepSeek Harness 的 Web 界面。

面向的真实场景是机房/办公电脑：系统可能是精简版、网络时好时坏、装不了开发环境，但需要一个能反复重试、坏了能自愈的部署方式。

## 它做了什么

- **便携 Node.js**：下载官方 zip 解压到 `dsh-runtime\node`，不替换系统 Node，不改系统环境变量。
- **完整性校验**：内置已知版本的 SHA-256；其他版本从 npmmirror 与 nodejs.org 双源拉取 `SHASUMS256.txt` 交叉校验，不一致直接中止。
- **安装脚本白名单**：npm 安装时只允许 `dsh-subprocess-local`、`koffi`、`node-pty` 等必要包执行生命周期脚本，其余一律拒绝。
- **原生依赖自检**：安装后实际加载 Koffi、真实 spawn 一个 Windows 伪终端；失败会自动 `npm rebuild`，仍失败才报错。
- **镜像竞速与回退**：npm 官方源与国内镜像并发查询，镜像落后时改走官方源；断网但本地已有版本时降级为离线启动。
- **默认安全**：Web 只监听 `127.0.0.1`。要让手机/平板访问必须显式加 `--lan`。

## 快速开始

1. 下载 `dsh-setup.bat`（官方 raw 或公共加速，见 [使用说明.md](使用说明.md)）。
2. 校验文件哈希（脚本会被直接执行，公共加速只提速、不建立信任）。
3. 双击运行。

首次运行会下载 Node.js 与 dsh 依赖，耗时取决于网络；之后复用本地运行时，启动只需几秒。

## 常用参数

| 参数 | 作用 |
| --- | --- |
| `--lan` | 绑定检测到的局域网 IPv4，供同一 Wi-Fi 设备访问（会暴露服务） |
| `--port <n>` | 指定 Web 端口，默认 3080，被占用时在 3081–3099 顺延 |
| `--no-open` | 服务就绪后不自动唤起浏览器 |
| `--fast` | 跳过在线版本检查，直接用本地版本秒启 |
| `--reinstall` | 强制重新拉取 dsh 并自检依赖 |
| `--clean` | 删除 `dsh-runtime`，下次运行重新部署 |
| `--create-shortcut` | 在桌面创建快捷方式（可叠加 `--fast` / `--lan`） |
| `--install-only` | 只安装并自检，不启动 Web 服务 |
| `--lang <zh\|en>` | 界面语言 |
| `--help` | 完整参数说明 |

## 安全模型

- 默认仅监听 `127.0.0.1`，不会自动暴露到网络。
- `--lan` 绑定单个局域网 IPv4，**同一网段的所有人都能访问这个具备 shell 与文件读写能力的 Agent**；默认 HTTP 下登录 token 也可能被同网段嗅探。仅在可信网络使用，并把防火墙范围限制在专用网络。
- 安装器自身通过 GitHub raw 或公共加速分发。加速站可能缓存旧文件，请始终用 [使用说明.md](使用说明.md) 里公布的 SHA-256 校验后再运行。

## 目录与清理

所有运行时数据都在脚本同级的 `dsh-runtime\`：

- 整个目录可以直接删除，等价于 `--clean`；
- 安装中断留下的 `.node-install-*` / `.node-backup-*` / `*.download` 会在下次启动时自动清理（超过 1 小时的残留）；
- 已在 `.gitignore` 中排除，不会进入版本库。

## 系统要求

- Windows 10 / 11，x64 或 ARM64
- Windows PowerShell 5.1（系统自带）
- 能访问 npm registry 与 nodejs.org，或配置了可用的 `HTTPS_PROXY` / `HTTP_PROXY`
- 建议安装 Visual C++ 2015–2022 运行库；缺失时脚本会提示，原生模块自检也会给出明确错误

## 版本策略

默认跟随 npm 上 `@deepseek-ai/dsh` 的 `latest` 标签，**官方发布预发布版（rc）时也会跟随**。这是刻意选择：机房机器不常维护，跟上 latest 比钉死旧版更省事。需要固定版本时用 `--reinstall` 配合上游 tag，或自行修改安装参数。

## 详细文档

安装步骤、故障排查、加速链接与校验命令见 [使用说明.md](使用说明.md)。

## English

A single-file Windows installer for [DeepSeek Harness](https://www.npmjs.com/package/@deepseek-ai/dsh). No Git, no system Node.js, no admin rights: it provisions a portable Node.js runtime, verifies the archive with SHA-256, installs the CLI with a strict lifecycle-script allowlist, probes native modules, then starts the web UI.

The web server binds `127.0.0.1` by default; pass `--lan` to expose it to one LAN IPv4 address (this exposes a shell/file-capable agent to your network — trusted networks only).

Run `dsh-setup.bat --help` for all options.
