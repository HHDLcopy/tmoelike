# 变更记录

## v2.3.3

### 修复（用户反馈的两处）
1. **缺 jq/python3 时不自动安装**：原先是弹窗询问，改为**自动执行
   `pkg install -y <缺失包>`**（Termux），装好后继续；没有 `pkg` 或安装失败时
   给出手动安装指引后中止。
   同时修掉一个隐蔽缺陷：bash 会缓存命令路径，安装前若探测过（解析到旧路径），
   安装后仍用缓存 → "装好了却判定不可用"。现在安装后先 `hash -r` 再检测。
2. **所有发行版都提示"不支持"**：`proot-distro` 刚安装时发行版列表为空
   （需先 `proot-distro update`），旧实现直接 `grep list`，于是全部被判为不支持。
   新增 `distro_available()`：列表为空时自动执行一次 `proot-distro update`
   后重试；两处校验（TUI 与 CLI 安装）都改用它。

### 测试
- 新增 `tests/cases/proot_distro.sh`（8 项）：空列表自动 update、不存在的发行版、
  两个调用方都改用 `distro_available` 的回归断言。
- `tests/cases/deps_prompt.sh` 改为覆盖"自动安装"（不再询问）：
  缺 jq 自动装、两者都缺自动装后继续、安装失败给三平台指引。
- 测试总数 140 → **148**。


## v2.3.2

### 修复（线上报错）
- **`deps_install: command not found`**：`ensure_deps` 在用户选择"自动安装依赖"后
  调用 `deps_install`，但该函数在 v2.2 模块化重构时丢失，只剩调用点。
  表现为缺 `proot`/`proot-distro` 时点 Yes 直接报
  `deps.sh: line 48: deps_install: command not found / 错误：依赖安装失败`。
  现已补回：无 `pkg` 时给警告并返回非 0，有 `pkg` 时执行 `pkg install -y <包名>`。
- 教训：调用点与定义必须成对；本次同时补了回归测试（见下）。

### 测试
- `tests/cases/core.sh` 新增 2 项：断言 `deps_install` 已定义、且确实调用
  `pkg install -y <包名>`——防止该函数再次被重构弄丢。
- 测试总数 138 → **140**。


## v2.3.1

### 改进：启动依赖缺失时询问安装（不再直接报错退出）
- 首次运行前检测 `jq` / `python3`；**缺 `jq` 即询问是否安装**，
  即使 `python3` 可用也会问（jq 是首选：启动更快、依赖更小）。
- 交互确认优先用 dialog（有终端时），否则用文本提问；
  完全非交互（管道/CI）走默认安装；`TMOE_ASSUME_YES=1` 可跳过。
- 有 `pkg`（Termux）→ 执行 `pkg install -y jq`，装好后继续；
  无 `pkg` → 给出 Debian/Ubuntu/Alpine/Termux 的手动安装指引后中止。
- 修正依赖检测：不再只靠 `command -v`（命令"存在"≠"可用"），
  改为实测（`jq --version` / `python3 -c import sys`），
  避免 jq 损坏或缺动态库时被误判为可用。

### 修复
- `_boot_ask_install` 的终端判定：`[ -r /dev/tty ]` 在无控制终端时仍为真，
  导致 dialog 失败后误判为"拒绝安装"；改用 `-t 0/-t 1` 判定。

### 测试
- 新增 `tests/cases/deps_prompt.sh`（13 项）：缺 jq 时询问、两者都缺时拒绝并中止、
  无 pkg 时给出各发行版指引。
- `tests/fixtures/jq` 支持 `--version` / `-V` / `--help`（更接近真实 jq）。
- 测试总数 125 → **138**。


## v2.3.0

### 新增：单文件分发 + 自动引导
- **用户只需下载 `tmoelike.sh`**；其余 19 个模块首次运行时自动获取。
- 引导流程：并行探测 GitHub / Gitee 的 `lib/manifest.json`（按 `curl -w time_total`
  测速）→ 选最快可用源 → 逐模块下载并比对 SHA256 → 全部通过后原子安装到
  `~/.tmoelike/cache/lib`。
- 首选源失败时自动回退到另一个源；缓存齐全时完全离线启动。
- 仓库内同时存在 `lib/` 时**优先用本地**（开发友好，不联网）。
- 新增引导参数：`--refresh-lib`、`--offline`；新增环境变量
  `TMOE_LIB` / `TMOE_SOURCES` / `TMOE_MANIFEST_SHA256` / `TMOE_NO_FETCH` /
  `TMOE_REFRESH_LIB` / `TMOE_PROBE_TIMEOUT` / `TMOE_BASE`。
- 新增 `lib/manifest.json` 与生成器 `tools/gen_manifest.py`（`--check` 供 CI 校验）。

### 安全（自动下载必须收敛）
- 每个模块**逐文件 SHA256 硬校验**；任一不符即中止，且**不写入任何缓存**
  （避免半成品模块被 `source`）。
- 校验失败不重试、不换源、不降级，避免"换个源就过了"掩盖投毒。
- 支持 `TMOE_MANIFEST_SHA256` 固定清单指纹；首次运行记录指纹，之后不一致会告警。
- 支持把下载源收敛到自控主机；每日最多一次的更新提示，不阻塞启动。
- README 明确写出信任边界：清单与被下载模块同源，能防传输损坏/单文件替换，
  **不能防源被完全接管**；在意者应 `TMOE_LIB` 离线运行。

### 测试
- 新增 `tests/cases/bootstrap.sh`：测速选源、缓存命中、离线报错、篡改拒绝、
  指纹固定、全源不可达、`--refresh-lib` 等 20 项断言（用本地模拟源，7 秒完成）。
- 测试总数 105 → **125**。


## v2.2.0

### 结构
- 单文件（约 2360 行）拆分为入口 + `lib/` 19 个模块，删除 6 处死代码
  （`desktop_pkgs`、`run_with_logbox_wait`、`registry_list`、`tui_checklist`、`ok`、`C_BLUE`/`SETTINGS`）。
- 新增跨模块调用一致性自检 `tests/lint_calls.sh`。

### 修复
- **`restore_container` 成功分支引用了未定义的 `$arch_file`**：`set -u` 下恢复完成后会中断。
- **SHA256 校验未闭环**：chroot 安装曾传空校验值；现为「用户配置 → 官方校验文件 → 询问」三级，
  且校验失败硬失败（不再静默换镜像）。
- **`tar -I`/`--zstd`/`-z` 在无法 fork 压缩器的环境产出空归档**：新增压缩兼容层，
  自动退化为「先打 tar 再压缩」。
- **非交互模式直接 `cat` 原始日志**：会绕过脱敏，现只输出摘要指向已脱敏归档。
- **`with_rollback` 签名**：原设计要求回滚函数在参数末尾，实际调用必失败；改为
  `with_rollback <回滚函数> <回滚参数> <命令...>`。
- `verify_backup` 在无 `jq` 时恒失败 → 改为 jq 可选。

### 加固
- `find -printf` 兼容层（`find_dirs` / `list_dirs_by_mtime`），不再强依赖 findutils。
- 依赖分层：只读命令不再被 `proot` 缺失挡住；CLI 补齐 `proot-distro`/`file` 检查。
- `run_with_logbox` 重写：控制 FIFO 消除竞态，非交互可测试；`if` 条件下也能正确收尾。
- CLI 与 TUI 统一：`install`/`start`/`helper`/`remove` 共用核心，支持 `--yes` 非交互。
- 插件信任库改为「记录 + 复核」，改文件必须重新确认。
- 远程脚本不再 `curl | sh`；容器内 `switch_mirror` 用 `safe_sed_file`（备份/验证/还原）。
- SSH 默认 `ListenAddress 127.0.0.1`。
- chroot 去掉 `su -c` 长字符串拼接，挂载点记录 + `chroot-clean` 清理闭环。
- 自更新源改为必须显式配置（`update_repo`），移除 `youruser` 占位。

### 工程
- 新增 `tests/`（5 个用例、105 项断言）与 `.github/workflows/ci.yml`（语法 + ShellCheck + 测试 + 降级路径）。
- 新增 `.shellcheckrc`、`README.md`。

## v2.1.0
- 修复 `$(cat)` 挂起、tailbox 不自动关、Alpine 镜像双 `/alpine`。
- 桌面安装按发行版适配包管理器；`switch_mirror` 支持 Ubuntu 24.04+ `ubuntu.sources`。
- 安全加固：SHA256、`safe_untar`、日志脱敏、VNC 仅本地、插件信任。
- 新增 CLI 子命令、备份保留与校验、自更新与回滚。
