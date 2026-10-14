#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike common.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# PREFIX：Termux 下由环境提供；非 Termux（如 CI）给出默认值，
# 避免 set -u 下引用未定义变量。
: "${PREFIX:=/data/data/com.termux/files/usr}"

# ---------- 常量 ----------
readonly TMOE_VERSION="2.2.0"

# 修复：SCRIPT_DIR 在管道/软链下不可靠（BASH_SOURCE 可能为空）
get_script_path() {
    local src="${BASH_SOURCE[0]:-}"
    if [ -n "$src" ] && [ -f "$src" ]; then
        cd "$(dirname "$src")" && pwd -P
    else
        cd "${HOME}/.tmoelike" 2>/dev/null && pwd -P || echo "$HOME"
    fi
}
readonly SCRIPT_DIR="$(get_script_path)"

readonly BASE_DIR="${HOME}/.tmoelike"
readonly PLUGIN_DIR="${BASE_DIR}/plugins"
readonly CONFIG_DIR="${BASE_DIR}/config"
readonly LOG_DIR="${BASE_DIR}/logs"
readonly CACHE_DIR="${BASE_DIR}/cache"
readonly BACKUP_DIR="${BASE_DIR}/backups"
readonly REGISTRY="${CONFIG_DIR}/containers.json"
readonly CHROOT_SHA_FILE="${CONFIG_DIR}/chroot-sha256.json"
readonly CHROOT_BASE="/data/local/tmp/tmoelike-chroot"
readonly HELPER_NAME="tmoelike-tui"
readonly HELPER_VERSION="3"
readonly MAIN_LOG="${LOG_DIR}/main.log"

# 自更新源（GitHub Releases API；可用环境变量覆盖）
# 自更新源必须显式配置（环境变量或 config/settings.json 的 update_repo）。
# 刻意不内置占位仓库：占位值会让「检查更新」看似可用却永远失败。

# 备份保留份数（每个容器）
readonly BACKUP_KEEP="${BACKUP_KEEP:-5}"

for d in "$PLUGIN_DIR" "$CONFIG_DIR" "$LOG_DIR" "$CACHE_DIR" "$BACKUP_DIR"; do
    mkdir -p "$d"
done

# chroot 镜像 SHA256 表：首次运行生成占位文件，由维护者填充
# 结构：{ "debian:arm64": "<sha256>", ... }
if [ ! -f "$CHROOT_SHA_FILE" ]; then
    echo '{}' > "$CHROOT_SHA_FILE" 2>/dev/null || true
fi


# ---------- 颜色 ----------
if [ -t 1 ]; then
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_RESET=""; C_BOLD=""
fi

# ---------- 日志（脱敏） ----------
sanitize() {
    # 移除密码、密钥、token、Bearer、ssh 私钥体等敏感内容
    # 覆盖：password=xxx / password: xxx / password = "xx xx" / --password=xxx
    sed -E \
        -e 's/(password|passwd|token|secret|api[_-]?key|auth)["'"'"']?[[:space:]]*[:=][[:space:]]*"[^"]*"/\1=***/gi' \
        -e 's/(password|passwd|token|secret|api[_-]?key|auth)["'"'"']?[[:space:]]*[:=][[:space:]]*'"'"'[^'"'"']*'"'"'/\1=***/gi' \
        -e 's/(password|passwd|token|secret|api[_-]?key|auth)["'"'"']?[[:space:]]*[:=][[:space:]]*[^ "'"'"']+/\1=***/gi' \
        -e 's/(--password[= ][[:space:]]*)[^ ]+/\1***/gi' \
        -e 's/(Authorization:[[:space:]]*Bearer[[:space:]]+)[A-Za-z0-9._-]+/\1***/gi' \
        -e 's/(ssh-(rsa|ed25519|ecdsa)[[:space:]]+)[A-Za-z0-9+\/=]+/\1***/g'
}
# 归档日志前脱敏；失败则退回原文件（不因脱敏失败丢日志）
sanitize_file() {
    local src="$1" dst="$2"
    if [ -s "$src" ]; then
        sanitize < "$src" > "$dst" 2>/dev/null || cp -f "$src" "$dst"
    else
        : > "$dst"
    fi
}
log()  { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | sanitize >> "$MAIN_LOG"; }
die()  { printf '%s错误：%s%s\n' "$C_RED" "$*" "$C_RESET" >&2; log "ERROR: $*"; exit 1; }
warn() { printf '%s警告：%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; log "WARN: $*"; }

# ============================================================
#  TUI：自动安装 + 兼容层
# ============================================================

# ---------- 配置项存取（config/settings.json） ----------
# 统一设置入口，避免散落的魔法默认值。
readonly SETTINGS="${CONFIG_DIR}/settings.json"

config_init() {
    if [ ! -f "$SETTINGS" ] || ! jq empty "$SETTINGS" >/dev/null 2>&1; then
        echo '{}' > "$SETTINGS" 2>/dev/null || true
    fi
}

config_get() {
    local key="$1" default="${2:-}"
    config_init
    local v
    v=$(jq -r --arg k "$key" '.[$k] // empty' "$SETTINGS" 2>/dev/null)
    printf '%s' "${v:-$default}"
}

config_set() {
    local key="$1" val="$2"
    config_init
    local tmp; tmp=$(mktemp)
    if jq --arg k "$key" --arg v "$val" '.[$k] = $v' "$SETTINGS" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$SETTINGS"
    else
        rm -f "$tmp"
        warn "写入设置失败：$key"
        return 1
    fi
}

config_list() {
    config_init
    jq -S . "$SETTINGS" 2>/dev/null || cat "$SETTINGS"
}

# ---------- 安全下载并执行（替代 curl | sh） ----------
# 先下载到临时文件、校验（可选 sha256）、经用户确认后再执行。
# 目的：避免「边下载边执行」——一旦上游被投毒，管道写法没有任何拦截点。
github_script_run() {
    # github_script_run <url> <expected_sha|""> <label> [-- 传给脚本的参数...]
    local url="$1" expected_sha="$2" label="$3"; shift 3
    [ "${1:-}" = "--" ] && shift
    local tmp; tmp=$(mktemp)
    if ! curl -fsSL --retry 3 --connect-timeout 20 -o "$tmp" "$url"; then
        rm -f "$tmp"
        warn "下载失败：$url"
        return 1
    fi
    local actual; actual=$(sha256sum "$tmp" | awk '{print $1}')
    log "下载 ${label}：$url sha256=${actual}"

    if [ -n "$expected_sha" ]; then
        if [ "$actual" != "$expected_sha" ]; then
            warn "${label} 校验失败：期望 ${expected_sha} 实际 ${actual}"
            rm -f "$tmp"
            return 1
        fi
    else
        tui_yesno "确认执行" "${label}\n\n来源：${url}\nSHA256：${actual}\n\n该脚本将以当前用户身份执行，是否继续？" \
            || { rm -f "$tmp"; return 1; }
    fi

    local rc=0
    sh "$tmp" "$@" || rc=$?
    rm -f "$tmp"
    return "$rc"
}
