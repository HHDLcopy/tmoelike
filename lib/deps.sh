#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike deps.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# ============================================================
#  依赖检查（统一 TUI / CLI 两条路径）
#  - 必需：所有模式都要有，缺失即中止
#  - 可选：只在对应功能被使用时检查（file/zstd/xz/gzip/ssh-keygen 等）
#  - Termux 包名与命令名大多同名；proot-distro 由 proot-distro 包提供
# ============================================================
# 核心：所有模式都要有（日志/注册表/下载都依赖）
CORE_CMDS=(jq)
# 运行容器必备
RUNTIME_CMDS=(proot tar proot-distro)
# 只在对应功能被使用时才需要
OPTIONAL_CMDS=(file zstd xz gzip ssh-keygen dialog)


# 收集缺失依赖到数组（不用命令替换，避免子 shell 环境影响判定）
_deps_collect() {
    local -n _out=$1; shift
    local c
    _out=()
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || _out+=("$c")
    done
    return 0
}

# 必需的单个命令（供子命令按需调用）
deps_require() {
    local c
    for c in "$@"; do
        if ! command -v "$c" >/dev/null 2>&1; then
            die "缺少依赖：$c（Termux 可运行：pkg install $c）"
        fi
    done
}

# 交互式（TUI）依赖检查：可选择自动安装
ensure_deps() {
    local miss=()
    _deps_collect miss "${CORE_CMDS[@]}" "${RUNTIME_CMDS[@]}"
    ((${#miss[@]})) || return 0
    if tui_yesno "缺少依赖" "检测到缺少：${miss[*]}\n是否自动安装？"; then
        deps_install "${miss[@]}" || die "依赖安装失败"
    else
        die "缺少必要依赖"
    fi
}

# 非交互（CLI）依赖检查：直接失败并给出可复制命令
require_deps() {
    local miss=()
    _deps_collect miss "${CORE_CMDS[@]}"
    ((${#miss[@]})) || return 0
    printf '错误：缺少必需依赖：%s\n' "${miss[*]}" >&2
    command -v pkg >/dev/null 2>&1 && printf '可运行：pkg install %s\n' "${miss[*]}" >&2
    exit 1
}

# 需要运行容器（proot 系）的子命令调用它
run_deps_require() {
    deps_require "${RUNTIME_CMDS[@]}"
}

# 导出功能按目标格式检查压缩器（zstd/xz/gzip）
export_deps_require() {
    local fmt="${1:-zstd}" need=()
    case "$fmt" in
        xz)   command -v xz   >/dev/null 2>&1 || need+=(xz) ;;
        gz)   command -v gzip >/dev/null 2>&1 || need+=(gzip) ;;
        *)    command -v zstd >/dev/null 2>&1 || need+=(zstd) ;;
    esac
    ((${#need[@]})) || return 0
    die "缺少依赖：${need[*]}（导出需要：pkg install ${need[*]}）"
}
