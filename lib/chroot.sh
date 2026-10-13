#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike chroot.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# ============================================================
#  chroot 容器（修复 #3、#4）
# ============================================================
check_root() {
    if ! command -v su >/dev/null 2>&1; then
        tui_msg "权限" "未找到 su（chroot 需要 root）。"
        return 1
    fi
    if ! su -c id 2>/dev/null | grep -q 'uid=0'; then
        tui_msg "权限" "chroot 功能需要 root 权限（su 未授权或不可用）。"
        return 1
    fi
    return 0
}

# 挂载点记录文件
CHROOT_MOUNTS_FILE="/data/local/tmp/tmoelike-mounts.txt"

# ---------- su 执行辅助：把脚本落盘再执行 ----------
# 为什么不用 su -c "长字符串"：变量/引号/通配符会被两遍 shell 解析，
# 路径含空格或特殊字符时会挂载到错误位置。落盘后执行可彻底规避。
_su_script() {
    local body="$1"
    local tmp; tmp=$(mktemp)
    printf '%s\n' '#!/system/bin/sh' "$body" > "$tmp"
    chmod 755 "$tmp" 2>/dev/null || true
    local rc=0
    su -c "sh $tmp" || rc=$?
    rm -f "$tmp"
    return "$rc"
}

# 记录挂载点，便于统一清理
_chroot_mount_record() {
    local root="$1"
    printf '%s\n' "${root}/dev" "${root}/proc" "${root}/sys" >> "$CHROOT_MOUNTS_FILE"
    log "记录挂载点：${root}/{dev,proc,sys}"
}

mount_chroot() {
    local d="$1"
    local root="${CHROOT_BASE}/${d}"
    local arch; arch=$(detect_arch)

    su -c "mkdir -p '$root/dev' '$root/proc' '$root/sys' '$root/tmp'" 2>/dev/null || true

    # 跨架构：注入 qemu-user-static（可用 file 判定时更准，否则按已知路径推断）
    local rootfs_arch=""
    if command -v file >/dev/null 2>&1 && [ -f "${root}/bin/sh" ]; then
        if file -b "${root}/bin/sh" 2>/dev/null | grep -qi 'aarch64'; then
            rootfs_arch="arm64"
        elif file -b "${root}/bin/sh" 2>/dev/null | grep -qi 'x86-64'; then
            rootfs_arch="amd64"
        fi
    elif [ -f "${root}/usr/bin/qemu-aarch64-static" ]; then
        rootfs_arch="arm64"
    fi

    if [ -n "$rootfs_arch" ] && [ "$rootfs_arch" != "$arch" ]; then
        local host_qemu=""
        case "$rootfs_arch" in
            arm64) host_qemu=$(command -v qemu-aarch64-static 2>/dev/null || true) ;;
            amd64) host_qemu=$(command -v qemu-x86_64-static 2>/dev/null || true) ;;
        esac
        if [ -n "$host_qemu" ]; then
            su -c "mkdir -p '$root/usr/bin' && cp '$host_qemu' '$root/usr/bin/'" 2>/dev/null || true
        else
            tmo_yesno "缺少 qemu" "本机 $arch 运行 $rootfs_arch rootfs，但未检测到 qemu-user-static。\n\n继续挂载？" --default no || return 1
        fi
    fi

    if ! _su_script "mountpoint -q '$root/dev' || mount -o bind /dev '$root/dev'
mountpoint -q '$root/proc' || mount -t proc proc '$root/proc'
mountpoint -q '$root/sys' || mount -t sysfs sys '$root/sys'
[ -f '$root/etc/resolv.conf' ] || cp /etc/resolv.conf '$root/etc/resolv.conf' 2>/dev/null || true"; then
        warn "挂载失败：${root}"
        unmount_chroot "$d"
        return 1
    fi

    _chroot_mount_record "$root"
    return 0
}

unmount_chroot() {
    local d="$1"
    local root="${CHROOT_BASE}/${d}"
    _su_script "for m in '$root/sys' '$root/proc' '$root/dev'; do
    mountpoint -q \"\$m\" && umount \"\$m\" 2>/dev/null
    mountpoint -q \"\$m\" && umount -l \"\$m\" 2>/dev/null
done
exit 0" || warn "卸载返回非零：$root"
    return 0
}

# 清理所有历史挂载（CLI chroot-clean 与 TUI 复用）
cleanup_chroots() {
    check_root || return 1
    if [ ! -s "$CHROOT_MOUNTS_FILE" ]; then
        printf '无挂载记录：%s\n' "$CHROOT_MOUNTS_FILE"
        return 0
    fi
    local m
    # 逆序卸载
    while IFS= read -r m; do
        [ -n "$m" ] || continue
        _su_script "[ -d '$m' ] && { mountpoint -q '$m' && umount '$m' 2>/dev/null; } ; exit 0" || true
        printf '已尝试卸载：%s\n' "$m"
    done < <(tac "$CHROOT_MOUNTS_FILE" 2>/dev/null || tail -r "$CHROOT_MOUNTS_FILE" 2>/dev/null || cat "$CHROOT_MOUNTS_FILE")
    : > "$CHROOT_MOUNTS_FILE"
    printf '挂载记录已清空：%s\n' "$CHROOT_MOUNTS_FILE"
    return 0
}


install_chroot_distro() {
    check_root || return
    local d
    d=$(tui_menu "chroot 容器" "选择发行版：" \
        debian "Debian" \
        ubuntu "Ubuntu" \
        alpine "Alpine" \
        fedora "Fedora") || return
    [ -z "$d" ] && return

    local arch; arch=$(detect_arch)
    [ "$arch" = "unknown" ] && { tui_msg "失败" "无法识别 CPU 架构。"; return; }
    local url; url=$(get_chroot_url "$d" "$arch")
    if [ -z "$url" ]; then
        tui_msg "不支持" "发行版 $d 在 $arch 上暂无预置镜像。"
        return
    fi

    local tmp="/data/local/tmp/${d}-rootfs.tar"

    # ---------- SHA256 校验闭环 ----------
    # ① config/chroot-sha256.json（用户/维护者可固定） ② 官方 *.sha256/SHA256SUMS
    tui_infobox "校验" "正在获取 ${d} (${arch}) 的校验值…"
    local sha; sha=$(resolve_chroot_sha "$d" "$arch")
    if [ -n "$sha" ]; then
        log "chroot ${d}:${arch} 使用校验值 $sha"
    elif [ "$(config_get chroot_require_sha yes)" = "yes" ]; then
        tui_msg "无校验值" "未获取到 ${d} (${arch}) 的 SHA256 校验值，已中止。\n\n可手动写入：\n${CHROOT_SHA_FILE}\n{\"${d}:${arch}\": \"<sha256>\"}\n\n或在设置中关闭 chroot_require_sha。"
        return 1
    else
        tui_yesno "无校验" "未获取到 ${d} (${arch}) 的 SHA256 校验值。\n（可在 ${CHROOT_SHA_FILE} 手动补充）\n\n仍要继续下载吗？" || return 1
    fi

    tui_infobox "下载" "下载 ${d} (${arch}) rootfs…\n$url"
    local rc=0
    download_file "$url" "$tmp" "$sha" || rc=$?
    case "$rc" in
        0) : ;;
        2) tui_msg "安全中止" "SHA256 校验失败：下载内容与官方校验值不符。\n可能的中间人篡改或镜像不同步，已中止安装。"; rm -f "$tmp"; return 1 ;;
        *) tui_msg "失败" "下载失败，请检查网络。"; rm -f "$tmp"; return 1 ;;
    esac

    su -c "mkdir -p '${CHROOT_BASE}/${d}'"
    tui_infobox "解压" "正在解压…"
    # 安全：按魔数解压 + 防路径穿越（不再用 tar -xJf/-xzf，避免 fork 压缩器失败）
    if ! safe_untar "$tmp" "${CHROOT_BASE}/${d}"; then
        tui_msg "失败" "解压失败（或压缩包含危险路径），已中止。"
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"

    mount_chroot "$d"

    registry_set "chroot-${d}" "type" "chroot"
    registry_set "chroot-${d}" "distro" "$d"
    registry_set "chroot-${d}" "arch" "$arch"
    registry_set "chroot-${d}" "root" "${CHROOT_BASE}/${d}"

    tui_msg "完成" "${d} chroot 已安装（${arch}）。"
}
enter_chroot() {
    check_root || return
    local cs; cs=$(list_chroot_installed)
    [ -z "$cs" ] && { tui_msg "提示" "暂无 chroot 容器。"; return; }
    local c
    c=$(tui_menu "进入" "选择容器：" $(for x in $cs; do echo "$x"; echo "$x"; done)) || return
    [ -z "$c" ] && return

    mount_chroot "$c"
    local mode
    mode=$(tui_menu "进入方式" "选择：" \
        shell  "Shell" \
        helper "容器助手") || return
    clear
    case "$mode" in
        helper)
            # 若无助手，先部署（从 rootfs 复制）
            su -c "chroot '${CHROOT_BASE}/${c}' '/usr/local/bin/${HELPER_NAME}'" 2>/dev/null || {
                tui_msg "提示" "容器内助手不存在。"
                su -c "chroot '${CHROOT_BASE}/${c}' /bin/sh"
            } ;;
        shell|"") su -c "chroot '${CHROOT_BASE}/${c}' /bin/sh" ;;
    esac
    unmount_chroot "$c"
}
remove_chroot_container() {
    check_root || return
    local cs; cs=$(list_chroot_installed)
    [ -z "$cs" ] && return
    local c
    c=$(tui_menu "删除" "选择容器：" $(for x in $cs; do echo "$x"; echo "$x"; done)) || return
    [ -z "$c" ] && return
    tui_yesno "确认" "删除 ${c}？" || return

    unmount_chroot "$c"
    su -c "rm -rf '${CHROOT_BASE}/${c}'"
    registry_del "chroot-${c}"
    tui_msg "完成" "已删除 ${c}。"
}
chroot_menu() {
    while :; do
        local c
        c=$(tui_menu "chroot 容器" "管理：" \
            install "安装发行版" \
            enter   "进入容器" \
            remove  "删除容器" \
            back    "返回") || return
        case "$c" in
            install) install_chroot_distro ;;
            enter)   enter_chroot ;;
            remove)  remove_chroot_container ;;
            back|"") return ;;
        esac
    done
}
