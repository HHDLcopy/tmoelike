# 变更记录

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
