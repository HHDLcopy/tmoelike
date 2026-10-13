# TMOE-LIKE

> ## ⚠️ 由 AI 生成（AI-Generated）
>
> **本仓库的全部代码、测试与文档均由 AI（大模型）生成**，人类仅提供需求、架构方向与逐条验收意见。
>
> - 生成与修订过程：需求方提出现状问题清单 → AI 实现并自测 → 需求方逐条核查反馈 → AI 修复 → 循环。
> - 因此：**请勿在未经复核的情况下直接用于生产环境**，尤其在涉及 root(chroot)、挂载、
>   远程脚本执行、SSH/VNC 对外监听等场景。仓库内已尽可能做安全加固并附自动化测试
>   （`tests/`，105 项断言），但这不构成安全审计。
> - 已知局限见文末「已知限制」；`CHANGELOG.md` 记录了每一处修复的动机。
> - 许可证未定：使用、再分发前请与仓库所有者确认。
>
> 如果你不接受 AI 生成代码，请不要使用本仓库。


类 TMOE 的 Termux Linux 容器管理器：proot 容器生命周期、chroot（root）、
桌面环境、SSH/VNC、备份/恢复、插件与自更新。

- **v2.2 起改为模块化结构**：入口 `tmoelike.sh`（43 行）+ `lib/` 下 19 个职责单一的模块。
  原先单文件约 2360 行，现在最大模块 `lib/helper.sh` 489 行（其中大部分是写入容器的内嵌助手脚本）。
- 全程中文注释，关键决策处写明「为什么这么做」。

---

## 目录结构

```
tmoelike.sh              入口：bootstrap（shell 选项/路径/日志）→ 加载模块 → 分发
lib/
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
tests/                   测试套件（纯 bash，无需 bats）
.github/workflows/ci.yml CI：语法 + ShellCheck + 测试
```

---

## 依赖

分层检查，只读命令（`list`/`status`/`--help`）不会被无关依赖挡住：

| 层级 | 命令 | 何时需要 |
|---|---|---|
| core | `jq` | 始终 |
| runtime | `proot` `proot-distro` `tar` | `install`/`start`/`helper`/`remove` |
| compress | `zstd`（导出/备份/恢复）、`xz`/`gzip`（按所选格式） | 备份类命令 |
| optional | `file`（跨架构 chroot 检测）、`ssh-keygen`、`dialog` | 对应功能 |

Termux 上安装：

```bash
pkg install jq proot-distro tar zstd file dialog
```

---

## 部署

模块必须与入口同目录（`tmoelike.sh` 与 `lib/` 并列）。也支持把 `lib/` 放到
`~/.tmoelike/lib`，或用环境变量指定：

```bash
TMOE_LIB=/path/to/lib ./tmoelike.sh status
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
bash tests/run.sh            # 全部
bash tests/run.sh compress   # 只跑名字含 compress 的用例
bash tests/lint_calls.sh     # 跨模块调用一致性自检
```

覆盖：镜像化、脱敏、路径穿越（真实恶意 tar）、多格式压缩往返、
备份校验与保留策略、日志窗口哨兵退出码/竞态/不泄露明文、CLI 全生命周期与降级。

CI（`.github/workflows/ci.yml`）在 push/PR 时执行：`bash -n` 全模块、
`shellcheck -S warning -x`、`tests/run.sh`，并额外验证「无 `find -printf`」降级路径。

---

## 已知限制

- chroot 需要 root（`su`）；本项目的 chroot 支持定位为**实验性**。
- 跨架构 chroot 依赖 `qemu-user-static` 与 `file`。
- proot 无 cgroups，资源限制只能靠 `nice`/`cpulimit` 做软限制。
- 从 v2.1 单文件升级：需要同时部署 `lib/`。

---

## 关于本项目的生成方式

| 项 | 说明 |
|---|---|
| 代码 | 由 AI 生成（含 `lib/` 19 个模块、入口脚本、容器内助手脚本） |
| 测试 | 由 AI 生成（`tests/`，纯 bash，105 项断言） |
| 文档 | 由 AI 生成（本 README、`CHANGELOG.md`、CI 配置） |
| 人类贡献 | 需求定义、问题清单（9 类）、架构取舍确认、逐条验收 |
| 复核状态 | 逻辑经自动化测试与静态自检（`bash -n`、跨模块调用自检）；**ShellCheck 仅在 CI 中运行**，未做人工安全审计 |

> 标注位置：本 README 顶部横幅 + 本节 + 每个 `lib/*.sh` 头部注释均标明了生成来源。
