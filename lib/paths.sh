#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike paths.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
get_chroot_sha() {
    local distro="$1" arch="$2"
    [ -f "$CHROOT_SHA_FILE" ] || { echo ""; return; }
    jq -r --arg k "${distro}:${arch}" '.[$k] // empty' "$CHROOT_SHA_FILE" 2>/dev/null || echo ""
}

# ============================================================
#  动态路径：proot-distro rootfs 位置（修复 #1）
# ============================================================
proot_rootfs_dir() {
    # TMOE_ROOTFS_DIR 可显式覆盖（测试隔离 / 自定义安装位置）
    if [ -n "${TMOE_ROOTFS_DIR:-}" ]; then
        echo "$TMOE_ROOTFS_DIR"
        return 0
    fi
    local prefix="${PREFIX:-/data/data/com.termux/files/usr}"
    local candidates=(
        "${prefix}/var/lib/proot-distro/installed-rootfs"
        "${prefix}/var/lib/proot-distro/rootfs"
        "${HOME}/.proot-distro/installed-rootfs"
    )
    for d in "${candidates[@]}"; do
        [ -d "$d" ] && { echo "$d"; return 0; }
    done
    # 找不到就返回第一个（创建时使用）
    echo "${prefix}/var/lib/proot-distro/installed-rootfs"
}
container_rootfs_path() {
    local name="$1"
    echo "$(proot_rootfs_dir)/${name}"
}

# ============================================================
#  容器列表：三种方式回退（修复 #2：解析脆弱）
# ============================================================
list_proot_installed() {
    local out=""

    # 方式 1：新版 proot-distro 的 list --installed 子命令
    if proot-distro list --installed >/dev/null 2>&1; then
        out=$(proot-distro list --installed 2>/dev/null | awk '
            /^\[installed\]/ {f=1; next}
            /^\[/ {f=0}
            f && /^[a-z0-9]/ {print $1}
        ')
        [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    fi

    # 方式 2：扫描 rootfs 目录（动态路径）
    local rootfs; rootfs=$(proot_rootfs_dir)
    if [ -d "$rootfs" ]; then
        out=$(find_dirs "$rootfs")
        [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    fi

    # 方式 3：最老版本 proot-distro 无 --installed，退回 list 解析
    out=$(proot-distro list 2>/dev/null | awk '/installed/ && /^[a-z0-9]/ {print $1}')
    [ -n "$out" ] && printf '%s\n' "$out"
    return 0
}
list_chroot_installed() {
    command -v su >/dev/null 2>&1 || return 0
    su -c "ls -1 '${CHROOT_BASE}' 2>/dev/null" 2>/dev/null | grep -v '^$' || true
}

# ============================================================
#  架构检测（修复 #3）
# ============================================================
detect_arch() {
    case "$(uname -m)" in
        aarch64|arm64) echo "arm64" ;;
        armv7l|armv8l) echo "armhf" ;;
        x86_64|amd64)  echo "amd64" ;;
        i686|i386)     echo "i386" ;;
        riscv64)       echo "riscv64" ;;
        *)             echo "unknown" ;;
    esac
}

# chroot rootfs 表：多架构 + 多镜像 + SHA 校验
# 注意：SHA 需定期更新，这里只做示例
get_chroot_url() {
    local distro="$1" arch="$2"
    case "$distro:$arch" in
        debian:arm64) echo "https://github.com/debuerreotype/docker-debian-artifacts/raw/dist-arm64v8/bookworm/rootfs.tar.xz" ;;
        debian:amd64) echo "https://github.com/debuerreotype/docker-debian-artifacts/raw/dist-amd64/bookworm/rootfs.tar.xz" ;;
        alpine:arm64) echo "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/aarch64/alpine-minirootfs-3.20.0-aarch64.tar.gz" ;;
        alpine:amd64) echo "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/alpine-minirootfs-3.20.0-x86_64.tar.gz" ;;
        ubuntu:arm64) echo "https://partner-images.canonical.com/core/jammy/current/ubuntu-jammy-core-cloudimg-arm64-root.tar.gz" ;;
        ubuntu:amd64) echo "https://partner-images.canonical.com/core/jammy/current/ubuntu-jammy-core-cloudimg-amd64-root.tar.gz" ;;
        fedora:arm64) echo "https://download.fedoraproject.org/pub/fedora/linux/releases/40/Container/arm64/images/Fedora-Container-Base-40-1.14.arm64.tar.xz" ;;
        fedora:amd64) echo "https://download.fedoraproject.org/pub/fedora/linux/releases/40/Container/x86_64/images/Fedora-Container-Base-40-1.14.x86_64.tar.xz" ;;
        *) echo "" ;;
    esac
}

# ---------- find -printf 兼容层 ----------
# Termux 默认 find 来自 busybox/精简实现，不一定支持 -printf；
# 这里探测一次并缓存，缺失时退回 basename/时间戳排序的 POSIX 方案。
TMOE_FIND_PRINTF=""
find_supports_printf() {
    if [ -z "$TMOE_FIND_PRINTF" ]; then
        if find / -maxdepth 0 -printf '' >/dev/null 2>&1; then
            TMOE_FIND_PRINTF=yes
        else
            TMOE_FIND_PRINTF=no
        fi
    fi
    [ "$TMOE_FIND_PRINTF" = "yes" ]
}

# find_dirs <dir> [name_glob]：输出其直接子目录名，每行一个（降序无关）
find_dirs() {
    local dir="$1" pattern="${2:-*}"
    [ -d "$dir" ] || return 0
    if find_supports_printf; then
        find "$dir" -mindepth 1 -maxdepth 1 -type d -name "$pattern" -printf '%f\n' 2>/dev/null
    else
        local d
        for d in "$dir"/$pattern; do
            [ -d "$d" ] || continue
            [ -L "$d" ] && [ ! -d "$d/" ] && continue
            basename "$d"
        done
    fi
}

# list_dirs_by_mtime <dir> <name_glob>：按修改时间从新到旧输出完整路径
list_dirs_by_mtime() {
    local dir="$1" pattern="${2:-*}"
    [ -d "$dir" ] || return 0
    if find_supports_printf; then
        find "$dir" -mindepth 1 -maxdepth 1 -type d -name "$pattern" \
            -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{$1=""; sub(/^ /,""); print}'
    else
        # 回退：用文件名（约定含 YYYYMMDD-HHMMSS）排序，再退回 ls -t
        ls -1dt "$dir"/$pattern 2>/dev/null || true
    fi
}
