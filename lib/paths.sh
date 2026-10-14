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
    # 候选按"常见程度"排列；不同 proot-distro 版本/安装方式会用不同位置
    # 只列"容器目录的父目录"。绝不能放裸的 proot-distro 根目录：
    # 它下面是 locks/cache/containers 这些内部目录，会被误当成容器。
    local candidates=(
        "${prefix}/var/lib/proot-distro/installed-rootfs"
        "${prefix}/var/lib/proot-distro/containers"
        "${prefix}/var/lib/proot-distro/rootfs"
        "/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs"
        "/data/data/com.termux/files/usr/var/lib/proot-distro/containers"
        "${HOME}/.proot-distro/installed-rootfs"
        "${HOME}/.local/share/proot-distro/installed-rootfs"
    )
    local d
    # 优先返回"确实装了容器"的目录（而不是仅仅存在）
    for d in "${candidates[@]}"; do
        [ -d "$d" ] || continue
        if [ -n "$(find_dirs "$d" 2>/dev/null | head -n1)" ]; then
            echo "$d"
            return 0
        fi
    done
    # 其次返回存在的目录（用于创建新容器）
    for d in "${candidates[@]}"; do
        [ -d "$d" ] && { echo "$d"; return 0; }
    done
    # 都没有：返回最常见的默认位置
    echo "${candidates[0]}"
}

# 简短诊断：用于 TUI 提示（msgbox 放不下太多行）
proot_diag_short() {
    local rootfs; rootfs=$(proot_rootfs_dir)
    printf 'rootfs：%s\n（%s）' "$rootfs" "$([ -d "$rootfs" ] && echo 存在 || echo 不存在)"
}

# 诊断信息：找不到容器时输出，帮助定位实际安装位置/命令行为
proot_diag() {
    local rootfs; rootfs=$(proot_rootfs_dir)
    local out=""
    out+="rootfs 目录：${rootfs}\n"
    out+="  ├ 存在：$([ -d "$rootfs" ] && echo 是 || echo 否)\n"
    if [ -d "$rootfs" ]; then
        out+="  └ 内容：$(find_dirs "$rootfs" 2>/dev/null | tr '\n' ' ')\n"
    fi
    out+="\nPREFIX=${PREFIX:-<未设置>}\n"
    local inst
    inst=$(proot-distro list --installed 2>&1 | head -n 8)
    out+="\nproot-distro list --installed：\n${inst:-<无输出>}\n"
    local all
    all=$(proot-distro list 2>&1 | head -n 8)
    out+="\nproot-distro list：\n${all:-<无输出>}"
    printf '%s' "$out"
}
container_rootfs_path() {
    local name="$1"
    local base
    base="$(proot_rootfs_dir)/${name}"
    # 兼容两种布局：
    #   旧版 installed-rootfs/<name>/      该目录本身就是 rootfs
    #   新版 containers/<name>/rootfs/     rootfs 在下一层
    # 判据：容器目录下若存在 rootfs/ 子目录，真正的 rootfs 是它。
    if [ -d "${base}/rootfs" ]; then
        printf '%s\n' "${base}/rootfs"
    else
        printf '%s\n' "$base"
    fi
}

# ============================================================
#  容器列表：三种方式回退（修复 #2：解析脆弱）
# ============================================================
# 从 proot-distro list 输出解析"已安装容器名"。
# 实测各版本格式差异很大，这里兼容三种：
#   ① Installed containers: 段落 + "  * ubuntu"   ← Termux proot-distro 4.x/5.x
#   ② [installed] 段落 + "ubuntu"
#   ③ 纯名字行 + "  ubuntu"
_pd_parse_installed() {
    local raw="$1" out=""
    # ① "* name"
    out=$(printf '%s\n' "$raw" \
        | sed -n 's/^[[:space:]]*\*[[:space:]]*\([A-Za-z0-9][A-Za-z0-9._:+-]*\)[[:space:]]*$/\1/p')
    if [ -n "$out" ]; then printf '%s\n' "$out"; return 0; fi
    # ② [installed] 段落里的纯名字行
    out=$(printf '%s\n' "$raw" | sed -n '/^\[installed\]/,/^\[/p' \
        | awk '/^[[:space:]]*[A-Za-z0-9][A-Za-z0-9._:+-]*[[:space:]]*$/ {print $1}')
    if [ -n "$out" ]; then printf '%s\n' "$out"; return 0; fi
    # ③ 纯名字行（只认小写开头，避免把 "Installed containers:" 之类当容器名）
    printf '%s\n' "$raw" \
        | awk '/^[[:space:]]*[a-z0-9][a-z0-9._:+-]*[[:space:]]*$/ {print $1}'
    return 0
}

list_proot_installed() {
    local out="" names="" rootfs
    rootfs=$(proot_rootfs_dir)

    # TMOE_ROOTFS_DIR 是显式覆盖（测试隔离 / 自定义安装位置）：直接以它为准
    if [ -n "${TMOE_ROOTFS_DIR:-}" ]; then
        find_dirs "$rootfs"
        return 0
    fi

    # 方式 1：官方 list —— 让 proot-distro 自己报告"已安装了哪些容器"。
    # 用途说明：枚举"已安装的容器"正是它的本职；但**不能**用它判断
    # "支持哪些发行版"（那是发行版清单，不是已安装状态）。
    # 注意：部分版本不认识 --installed（会直接报错），所以两个都试。
    out=""
    if out=$(proot-distro list --installed 2>/dev/null) && [ -n "$out" ]; then
        :
    elif out=$(proot-distro list 2>/dev/null) && [ -n "$out" ]; then
        :
    fi
    if [ -n "$out" ]; then
        names=$(_pd_parse_installed "$out")
        if [ -n "$names" ]; then
            printf '%s\n' "$names"
            return 0
        fi
    fi

    # 方式 2：扫 rootfs 目录（不依赖任何命令输出格式）
    # 过滤掉 proot-distro 的内部目录，避免把 locks/cache 之类当成容器。
    if [ -d "$rootfs" ]; then
        names=$(find_dirs "$rootfs" \
            | grep -vxE 'locks|cache|tmp|installed-rootfs|rootfs|containers')
        if [ -n "$names" ]; then
            printf '%s\n' "$names"
            return 0
        fi
    fi

    log "list_proot_installed: 未发现容器（rootfs=${rootfs} 存在=$([ -d "$rootfs" ] && echo yes || echo no)）"
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
