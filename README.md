# TMOE-LIKE

> ## ⚠️ 由 AI 生成（AI-Generated）
>
> **本仓库的全部代码、测试与文档均由 AI（大模型）生成**，人类仅提供需求、架构方向与逐条验收意见。
>
> - 生成与修订过程：需求方提出现状问题清单 → AI 实现并自测 → 需求方逐条核查反馈 → AI 修复 → 循环。
> - 因此：**请勿在未经复核的情况下直接用于生产环境**，尤其在涉及 root(chroot)、挂载、
>   远程脚本执行、SSH/VNC 对外监听等场景。仓库内已尽可能做安全加固并附自动化测试
>   （`tests/`，125 项断言），但这不构成安全审计。
> - **本项目会在首次运行时从网络下载并执行模块代码**，请务必阅读下方「引导机制与安全模型」。
> - 已知局限见文末「已知限制」；`CHANGELOG.md` 记录了每一处修复的动机。
> - 许可证未定：使用、再分发前请与仓库所有者确认。
>
> 如果你不接受 AI 生成代码，请不要使用本仓库。

类 TMOE 的 Termux Linux 容器管理器：proot 容器生命周期、chroot（root）、
桌面环境、SSH/VNC、备份/恢复、插件与自更新。

- **单文件分发**：你只需要下载 `tmoelike.sh` 一个文件；其余模块首次运行时自动获取。
- 模块化结构：`lib/` 下 19 个职责单一的模块，最大 `lib/helper.sh` 489 行
  （其中大部分是写入容器的内嵌助手脚本）。
- 全程中文注释，关键决策处写明「为什么这么做」。

---

## 快速开始

```bash
# 1) 只下载这一个文件（约 13 KB）
curl -fsSL -o tmoelike.sh \
  https://raw.githubusercontent.com/HHDLcopy/tmoelike/main/tmoelike.sh
# 国内推荐走 Gitee（镜像同步，测速会优先选它）：
# curl -fsSL -o tmoelike.sh https://gitee.com/dragon470/tmoelike/raw/main/tmoelike.sh

# 2) 直接运行
bash tmoelike.sh            # 进入 TUI
bash tmoelike.sh list       # 列出容器
bash tmoelike.sh status
```

两个源（GitHub / Gitee）内容一致，脚本会并行测速后选择较快的那个；
Gitee 侧为镜像，若你发现两边版本不同步，以 GitHub `main` 为准。

首次运行会自动：

1. 并行探测 GitHub / Gitee 的 `lib/manifest.json`（测速），**选最快可用的源**；
2. 按清单逐个下载 19 个模块，**每个文件比对 SHA256**；
3. 全部通过后整体原子安装到 `~/.tmoelike/cache/lib`；
4. 之后启动**优先使用本地缓存**，不再联网（除非你要求刷新）。

---

## 引导机制与安全模型

「自动下载代码并执行」天然是高风险动作，本项目用以下手段收敛风险：

| 机制 | 说明 |
|---|---|
| 逐文件 SHA256 | 每个模块下载后与清单里的 SHA256 比对；**任一不符即中止**，且**不写入任何缓存**（不会留下半成品被 source） |
| 哈希硬失败 | 校验失败不重试、不换源、不降级（避免"换个源就过了"掩盖投毒） |
| 清单指纹 | `TMOE_MANIFEST_SHA256=<sha256>` 可固定清单指纹，不匹配直接退出；首次运行会把指纹记到 `~/.tmoelike/cache/manifest.sha256`，之后不一致会**告警** |
| 源可收敛 | `TMOE_SOURCES` 可把下载限制在你自己控制的主机 |
| 离线可用 | 缓存齐全时完全离线；`TMOE_NO_FETCH=1` 强制离线 |
| 更新提示 | 每次启动最多每 24h 检查一次上游清单变化并提示，不阻塞启动 |

**参考做法**：在意供应链安全的话，用别的可信渠道把仓库 `lib/` 目录取到本地，
然后 `TMOE_LIB=/path/to/lib bash tmoelike.sh` 运行，完全不联网。

### 引导相关环境变量

| 变量 | 作用 |
|---|---|
| `TMOE_LIB=<目录>` | 指定本地模块目录（**优先级最高**，测试/离线用） |
| `TMOE_SOURCES="名\|URL 名\|URL"` | 覆盖下载源（空格分隔） |
| `TMOE_MANIFEST_SHA256=<sha256>` | 固定清单指纹 |
| `TMOE_NO_FETCH=1` | 禁止联网（缓存不全则明确报错并给出指引） |
| `TMOE_REFRESH_LIB=1` | 强制重新下载模块（等价 `--refresh-lib`） |
| `TMOE_PROBE_TIMEOUT=<秒>` | 测速探测超时（默认 8，弱网/测试可调小） |
| `TMOE_BASE=<目录>` | 覆盖"脚本所在目录"推断 |

### 启动依赖：自动安装

`jq` 是首选（启动更快、依赖更小）。**缺 `jq` 或 `python3` 时会自动执行安装**，
不再询问：

```
提示：未安装 jq，将改用 python3 解析清单（可用但稍慢）。
正在自动安装：pkg install -y jq
已安装：jq
```

- Termux（有 `pkg`）→ 自动 `pkg install -y <缺失的包>`，装好后继续运行；
- 非 Termux 或安装失败 → 给出 `apt install` / `apk add` / `pkg install`
  的手动指引后中止（绝不静默继续）；
- 安装后会自动清 bash 的命令哈希缓存再检测——否则可能出现
  "明明装好了却仍判定不可用"（探测时已缓存旧路径）。

### proot-distro 发行版列表

`proot-distro` 刚安装时发行版列表是空的，需要先 `proot-distro update`。
本项目会自动处理：判定发行版可用性时若列表为空，先自动执行一次
`proot-distro update` 再重试，避免把可用发行版误报成"不支持"。

### 引导参数

```bash
bash tmoelike.sh --refresh-lib     # 强制重新下载模块
bash tmoelike.sh --offline         # 等价 TMOE_NO_FETCH=1
```

---

## 目录结构

```
tmoelike.sh              入口：单文件引导（测速选源 / SHA256 校验 / 原子安装）→ 加载模块 → 分发
lib/
  manifest.json          模块清单（名称 + SHA256 + 大小），由 tools/gen_manifest.py 生成
  common.sh              日志与脱敏、颜色、配置项存取、安全下载执行
  tui.sh                 dialog 封装、交互适配层(tmo_*)、日志窗口
  archive.sh             压缩兼容层、safe_untar（防路径穿越 + 多格式）
  deps.sh                依赖分层（core / runtime / optional）与检查
  paths.sh               动态路径、架构探测、find -printf 兼容层
  registry.sh            容器元数据注册表
  download.sh            下载（镜像回退 + SHA256 硬校验）、远端校验值获取
  proot.sh               proot 容器：安装/启停/备份/恢复/克隆/重命名（TUI 包装）
  helper.sh              容器内助手脚本（写入容器，POSIX sh）与部署
  chroot.sh              chroot：挂载/卸载/清理、rootfs 安装
  desktop.sh             桌面环境安装（按发行版适配包管理器）
  ssh.sh  vnc.sh         SSH / VNC 服务
  beautify.sh            Termux 美化（字体/配色/zsh）
  plugin.sh              插件：元数据 + SHA256 + 信任库复核
  update.sh              自更新（GitHub Releases + SHA256 + 回滚）
  backup_util.sh         备份校验、保留策略、错误回滚
  menu.sh                主菜单与状态/设置
  cli.sh                 命令行子命令与入口分发
tools/gen_manifest.py    清单生成/校验（--check 供 CI 用）
tests/                   测试套件（纯 bash，无需 bats）
.github/workflows/ci.yml CI：语法 + ShellCheck + 清单一致性 + 测试
```

### 开发者模式

仓库里同时存在 `tmoelike.sh` 与 `lib/`，此时入口**优先使用同目录 `lib/`**，
不会联网下载——本地改动即时生效，便于开发与调试。

---

## 依赖

分层检查，只读命令（`list`/`status`/`--help`）不会被无关依赖挡住：

| 层级 | 命令 | 何时需要 |
|---|---|---|
| core | `jq` | 始终 |
| runtime | `proot` `proot-distro` `tar` | `install`/`start`/`helper`/`remove` |
| compress | `zstd`（导出/备份/恢复）、`xz`/`gzip`（按所选格式） | 备份类命令 |
| optional | `file`（跨架构 chroot 检测）、`ssh-keygen`、`dialog` | 对应功能 |
| 引导 | `curl` + (`jq` 或 `python3`) | 仅首次下载模块时需要；**缺失时会自动安装** |

Termux 上安装：

```bash
pkg install jq proot-distro tar zstd file dialog curl
```

---

## 命令行

```bash
./tmoelike.sh                          # 进入 TUI
./tmoelike.sh list                     # 列出容器
./tmoelike.sh install ubuntu           # 安装（注册元数据 + 部署容器助手）
./tmoelike.sh install ubuntu --no-helper
./tmoelike.sh start ubuntu             # 进入 Shell
./tmoelike.sh helper ubuntu            # 运行容器内助手
./tmoelike.sh remove ubuntu
./tmoelike.sh export ubuntu /sdcard/ubuntu.tar.zst
./tmoelike.sh import /sdcard/ubuntu.tar.zst ubuntu-new
./tmoelike.sh backup ubuntu            # 校验 + 保留最近 5 份
./tmoelike.sh restore <backup_dir> ubuntu2
./tmoelike.sh clone ubuntu ubuntu-copy
./tmoelike.sh rename ubuntu renamed
./tmoelike.sh chroot-clean             # 卸载所有 chroot 挂载点
./tmoelike.sh config set update_repo https://api.github.com/repos/<你>/<仓库>/releases/latest
./tmoelike.sh config get update_repo
./tmoelike.sh config list
./tmoelike.sh status
./tmoelike.sh update
./tmoelike.sh rollback                 # 回滚脚本自身到 .bak

# 引导相关
./tmoelike.sh --refresh-lib            # 强制重新下载模块
./tmoelike.sh --offline                # 强制离线

# 非交互（CI/自动化）
./tmoelike.sh --yes install ubuntu
TMOE_ASSUME_YES=1 ./tmoelike.sh remove old
```

CLI 与 TUI 行为一致：`install` 两条路径都走 `container_install`
（安装 → 注册元数据 → 部署助手，且幂等）；`start`/`helper`/`remove` 同理共用核心。

---

## 安全设计

| 项 | 做法 |
|---|---|
| 模块下载 | 逐文件 SHA256 硬校验；失败即中止且不落缓存 |
| 清单完整性 | 可选指纹固定（`TMOE_MANIFEST_SHA256`）+ 本机指纹变化告警 |
| 下载校验 | `download_file` 校验失败**硬失败（返回 2）**，绝不静默换镜像重试 |
| chroot rootfs | 三级取校验值：用户 `config/chroot-sha256.json` → 官方 `*.sha256`/`SHA256SUMS` → 询问；`chroot_require_sha=yes`（默认）时无校验即中止 |
| 解压 | `safe_untar` 按魔数识别 gzip/xz/bzip2/zstd，预检绝对路径与 `../`，`--no-same-owner` |
| 日志 | 写入前与归档前都脱敏（password/token/api_key/Bearer/ssh 公钥）；非交互模式**不打印原始日志** |
| 插件 | 声明式 `@sha256` + 信任库「记录并复核」；文件被改动必须重新确认 |
| 远程脚本 | 不再 `curl \| sh`：先落盘、展示 SHA256、确认后执行 |
| 镜像源 | 容器内 `safe_sed_file`：备份 → 替换 → 验证 → 失败自动还原 |
| VNC / SSH | 默认仅 `127.0.0.1`，需显式选择才暴露到局域网 |
| 自更新 | GitHub Releases API + SHA256；`update_repo` 未配置时明确提示，不留占位仓库 |
| chroot 挂载 | 不再用 `su -c "长字符串"`（两遍 shell 解析），改为落盘脚本执行；挂载点统一记录并可 `chroot-clean` 清理 |

---

## 测试

```bash
bash tests/run.sh            # 全部（125 项断言）
bash tests/run.sh bootstrap  # 只跑引导下载器用例
bash tests/lint_calls.sh     # 跨模块调用一致性自检
python3 tools/gen_manifest.py --check   # 清单与 lib/ 是否一致
```

覆盖：单文件引导（测速选源/缓存命中/离线/篡改拒绝/指纹固定/全源不可达）、
镜像化、脱敏、路径穿越（真实恶意 tar）、多格式压缩往返、
备份校验与保留策略、日志窗口哨兵退出码/竞态/不泄露明文、CLI 全生命周期与降级。

CI（`.github/workflows/ci.yml`）在 push/PR 时执行：`bash -n` 全模块、
`shellcheck -S warning -x`、清单一致性、`tests/run.sh`，并额外验证
「无 `find -printf`」降级路径。

---

## 已知限制

- **引导下载的信任根是"下载源本身"**：SHA256 清单与被下载模块来自同一处，
  因此能防传输损坏/单文件被替换，但**不能防源被完全接管**。在意这点请用
  `TMOE_LIB` 离线运行，或固定 `TMOE_MANIFEST_SHA256`。
- 首次运行必须联网；完全离线的设备需手动放置 `lib/` 并设置 `TMOE_LIB`。
- chroot 需要 root（`su`）；本项目的 chroot 支持定位为**实验性**。
- 跨架构 chroot 依赖 `qemu-user-static` 与 `file`。
- proot 无 cgroups，资源限制只能靠 `nice`/`cpulimit` 做软限制。

---

## 关于本项目的生成方式

| 项 | 说明 |
|---|---|
| 代码 | 由 AI 生成（含 `lib/` 19 个模块、入口引导、容器内助手脚本） |
| 测试 | 由 AI 生成（`tests/`，纯 bash，125 项断言） |
| 文档 | 由 AI 生成（本 README、`CHANGELOG.md`、CI 配置） |
| 人类贡献 | 需求定义、问题清单（9 类）、架构取舍确认、逐条验收 |
| 复核状态 | 逻辑经自动化测试与静态自检（`bash -n`、跨模块调用自检）；**ShellCheck 仅在 CI 中运行**，未做人工安全审计 |

> 标注位置：本 README 顶部横幅 + 本节 + 每个 `lib/*.sh` 头部注释均标明了生成来源。
