#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike proot.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# ============================================================
#  proot 容器：安装 / 启动 / 删除
# ============================================================

# ============================================================
#  容器安装核心（CLI 与 TUI 共用，行为一致）
#    container_install <distro> [--no-helper] [--no-register]
#  幂等：已安装则跳过安装步骤，仅补齐注册信息与助手。
# ============================================================
container_install() {
    local distro="$1"; shift || true
    local want_helper=yes want_register=yes
    local a
    for a in "$@"; do
        case "$a" in
            --no-helper)   want_helper=no ;;
            --no-register) want_register=no ;;
        esac
    done
    [ -n "$distro" ] || { warn "container_install 需要发行版名"; return 2; }

    if ! command -v proot-distro >/dev/null 2>&1; then
        die "缺少 proot-distro（pkg install proot-distro）"
    fi
    # 不做"发行版是否受支持"的预检查：`proot-distro list` 只显示**已安装**的
    # 容器，用它判断会把所有未安装的发行版误判为"不支持"。
    # 直接交给 proot-distro install，由它自己报告未知发行版。

    local rootfs; rootfs=$(container_rootfs_path "$distro")
    local need_install=yes
    [ -d "$rootfs" ] && need_install=no

    if [ "$need_install" = "yes" ]; then
        if ! run_with_logbox "安装 ${distro}" "${LOG_DIR}/install-${distro}.log" \
                proot-distro install "$distro"; then
            warn "安装失败：${distro}（原因见 ${LOG_DIR}/install-${distro}.log）"
            warn "若提示未知发行版，说明该名称不在当前 proot-distro 支持范围内。"
            return 1
        fi
    else
        log "容器已存在，跳过安装：$distro"
    fi

    if [ "$want_register" = "yes" ]; then
        registry_set "$distro" "type" "proot"
        registry_set "$distro" "distro" "$distro"
        registry_set "$distro" "arch" "$(detect_arch)"
        registry_set "$distro" "created" "$(date '+%F %T')"
    fi

    if [ "$want_helper" = "yes" ]; then
        if deploy_container_helper "$distro"; then
            registry_set "$distro" "helper_version" "$HELPER_VERSION"
        else
            warn "容器助手部署失败：$distro"
        fi
    fi
    return 0
}

# 启动核心：mode = shell | helper
container_start() {
    local name="$1" mode="${2:-shell}"
    [ -n "$name" ] || { warn "container_start 需要容器名"; return 2; }
    local rootfs; rootfs=$(container_rootfs_path "$name")
    [ -d "$rootfs" ] || { warn "容器不存在：$name"; return 1; }

    case "$mode" in
        helper)
            run_container_helper "$name" ;;
        shell|*)
            if [ -t 0 ]; then clear; fi
            proot-distro login "$name" ;;
    esac
}

# 删除核心（CLI 与 TUI 共用）
container_remove() {
    local name="$1"
    [ -n "$name" ] || { warn "container_remove 需要容器名"; return 2; }
    local rootfs; rootfs=$(container_rootfs_path "$name")
    if [ ! -d "$rootfs" ]; then
        # 也许只是注册表残留
        registry_del "$name" 2>/dev/null || true
        warn "容器不存在：$name"
        return 1
    fi
    proot-distro remove "$name" || { warn "proot-distro remove 失败：$name"; return 1; }
    registry_del "$name"
    printf '已删除：%s\n' "$name"
    return 0
}

# 确保容器助手存在（CLI helper 与 TUI 共用）
container_helper_ensure() {
    local name="$1"
    local rootfs; rootfs=$(container_rootfs_path "$name")
    [ -d "$rootfs" ] || { warn "容器不存在：$name"; return 1; }
    if [ ! -f "${rootfs}/usr/local/bin/${HELPER_NAME}" ]; then
        deploy_container_helper "$name" || return 1
    fi
    return 0
}

install_proot_distro() {
    local d
    d=$(tui_menu "proot 容器" "选择发行版：" \
        ubuntu    "Ubuntu (LTS)" \
        debian    "Debian (stable)" \
        alpine    "Alpine (轻量)" \
        archlinux "Arch Linux" \
        kali      "Kali Linux" \
        fedora    "Fedora" \
        void      "Void Linux" \
        opensuse  "openSUSE") || return
    [ -z "$d" ] && return

    # 与 CLI install 同一核心：安装 + 注册 + 部署助手
    if ! container_install "$d"; then
        tui_msg "失败" "${d} 安装失败，可查看日志：${LOG_DIR}/install-${d}.log"
        return
    fi
    tui_msg "完成" "${d} 安装完成。\n\n进入容器后可运行：${HELPER_NAME}"
}

start_proot_container() {
    local cs; cs=$(list_proot_installed)
    [ -z "$cs" ] && { tui_msg "提示" "暂无 proot 容器。"; return; }
    local c
    local names=(); local _c; for _c in $cs; do names+=("$_c" "$_c"); done
    c=$(tui_menu "启动" "选择容器：" ${names[@]+"${names[@]}"}) || return
    [ -z "$c" ] && return

    local mode
    mode=$(tui_menu "进入方式" "选择进入 ${c}：" \
        shell  "进入 Shell" \
        helper "运行容器助手 (${HELPER_NAME})") || return
    case "$mode" in
        helper) container_start "$c" helper ;;
        shell|"") container_start "$c" shell ;;
    esac
}

remove_proot_container() {
    local cs; cs=$(list_proot_installed)
    [ -z "$cs" ] && { tui_msg "提示" "暂无 proot 容器。"; return; }
    local c
    local names=(); local _c; for _c in $cs; do names+=("$_c" "$_c"); done
    c=$(tui_menu "删除" "选择容器：" ${names[@]+"${names[@]}"}) || return
    [ -z "$c" ] && return
    if tui_yesno "确认" "删除 ${c}？不可恢复。"; then
        if container_remove "$c"; then
            tui_msg "完成" "已删除 ${c}。"
        else
            tui_msg "失败" "删除 ${c} 失败。"
        fi
    fi
}

# ============================================================
#  ★ 备份 / 恢复 / 导出 / 导入 / 克隆（新增 #1、修复 #13）
# ============================================================
export_container() {
    local cs; cs=$(list_proot_installed)
    [ -z "$cs" ] && { tui_msg "提示" "暂无 proot 容器。"; return; }
    local c
    local names=(); local _c; for _c in $cs; do names+=("$_c" "$_c"); done
    c=$(tui_menu "导出" "选择容器：" ${names[@]+"${names[@]}"}) || return
    [ -z "$c" ] && return

    local rootfs; rootfs=$(container_rootfs_path "$c")
    [ -d "$rootfs" ] || { tui_msg "失败" "rootfs 不存在：$rootfs"; return; }

    local out="${BACKUP_DIR}/${c}-$(date +%Y%m%d-%H%M%S).tar.zst"
    local comp
    comp=$(tui_menu "压缩格式" "选择压缩格式：" \
        zstd "zstd (快，推荐)" \
        xz   "xz (小，慢)" \
        gz   "gzip (兼容)") || return

    tui_infobox "导出中" "正在打包 ${c} 到 ${out}\n请稍候…"
    local rc=0
    case "$comp" in
        zstd) zstd_create "$rootfs" "$out" 3 || rc=$? ;;
        xz)   tar_create_stream xz '-T0 -2' "$rootfs" "$out" || rc=$? ;;
        gz)   tar_create_stream gzip '-1' "$rootfs" "$out" || rc=$? ;;
    esac
    if [ $rc -eq 0 ]; then
        local size; size=$(du -h "$out" | cut -f1)
        tui_msg "完成" "已导出到：\n${out}\n大小：${size}"
    else
        tui_msg "失败" "导出失败。"
    fi
}
import_container() {
    local archive
    archive=$(tui_input "导入" "输入备份文件完整路径：" "") || return
    [ -f "$archive" ] || { tui_msg "失败" "文件不存在：$archive"; return; }

    local name
    name=$(tui_input "导入" "新容器名称（英文）：" "") || return
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || { tui_msg "失败" "名称不合法。"; return; }

    local rootfs; rootfs=$(container_rootfs_path "$name")
    [ -e "$rootfs" ] && { tui_msg "失败" "同名容器已存在。"; return; }

    mkdir -p "$rootfs"
    tui_infobox "导入中" "正在解压到 ${rootfs}…"
    # 安全：safe_untar 做路径穿越预检 + --no-same-owner
    if run_with_logbox "导入 ${name}" "${LOG_DIR}/import-${name}.log" \
            safe_untar "$archive" "$rootfs"; then
        registry_set "$name" "type" "proot"
        registry_set "$name" "imported" "$(date '+%F %T')"
        registry_set "$name" "source" "$archive"
        tui_msg "完成" "导入完成：${name}"
    else
        rm -rf "$rootfs"
        tui_msg "失败" "导入失败，已清理。"
    fi
}
backup_container() {
    # 备份 = 导出 + 元数据
    local cs; cs=$(list_proot_installed)
    [ -z "$cs" ] && { tui_msg "提示" "暂无 proot 容器。"; return; }
    local c
    local names=(); local _c; for _c in $cs; do names+=("$_c" "$_c"); done
    c=$(tui_menu "备份" "选择容器：" ${names[@]+"${names[@]}"}) || return
    [ -z "$c" ] && return

    local ts; ts=$(date +%Y%m%d-%H%M%S)
    local bdir="${BACKUP_DIR}/${c}-${ts}"
    mkdir -p "$bdir"

    tui_infobox "备份中" "正在备份 ${c}…"
    # 元数据
    registry_init
    jq --arg n "$c" '.containers[$n] // {}' "$REGISTRY" > "${bdir}/meta.json"
    # rootfs
    local rootfs; rootfs=$(container_rootfs_path "$c")
    zstd_create "$rootfs" "${bdir}/rootfs.tar.zst" 3 || {
        tui_msg "失败" "备份失败"; rm -rf "$bdir"; return
    }
    echo "$TMOE_VERSION" > "${bdir}/version"
    # 校验 + 保留策略
    if ! verify_backup "$bdir"; then
        tui_msg "警告" "备份已生成但校验未通过：\n${bdir}"
        return
    fi
    keep_backups "$c" "$BACKUP_KEEP"
    tui_msg "完成" "备份已保存并通过校验：\n${bdir}"
}
restore_container() {
    # 用 list_backups 统一列出（兼容无 find -printf 的环境）
    local backups=()
    local name_only
    while IFS= read -r name_only; do
        [ -n "$name_only" ] || continue
        backups+=("$name_only" "${BACKUP_DIR}/${name_only}")
    done < <(list_backups)
    ((${#backups[@]})) || { tui_msg "提示" "无可用备份（${BACKUP_DIR}）。"; return; }

    local chosen
    chosen=$(tui_menu "恢复" "选择备份：" "${backups[@]}") || return
    [ -z "$chosen" ] && return

    local name
    name=$(tui_input "恢复" "恢复为哪个容器名（可与原名不同）：" "$(basename "$chosen" | sed 's/-[0-9]*-[0-9]*$//')") || return
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || { tui_msg "失败" "名称不合法。"; return; }

    local rootfs; rootfs=$(container_rootfs_path "$name")
    [ -e "$rootfs" ] && { tui_msg "失败" "同名容器已存在。"; return; }

    mkdir -p "$rootfs"
    tui_infobox "恢复中" "正在恢复 ${name}…"
    if ! verify_backup "$chosen"; then
        tui_msg "失败" "备份不完整或已损坏：\n${chosen}"
        return
    fi
    if run_with_logbox "恢复 ${name}" "${LOG_DIR}/restore-${name}.log" \
            zstd_extract "${chosen}/rootfs.tar.zst" "$rootfs"; then
        if [ -f "${chosen}/meta.json" ]; then
            local tmp; tmp=$(mktemp)
            jq --arg n "$name" --slurpfile m "${chosen}/meta.json" \
                '.containers[$n] = $m[0]' "$REGISTRY" > "$tmp" && mv "$tmp" "$REGISTRY"
        fi
        tui_msg "完成" "恢复完成：${name}"
    else
        rm -rf "$rootfs"
        tui_msg "失败" "恢复失败。"
    fi
}
clone_container() {
    local cs; cs=$(list_proot_installed)
    [ -z "$cs" ] && { tui_msg "提示" "暂无 proot 容器。"; return; }
    local c
    local names=(); local _c; for _c in $cs; do names+=("$_c" "$_c"); done
    c=$(tui_menu "克隆" "选择源容器：" ${names[@]+"${names[@]}"}) || return
    [ -z "$c" ] && return

    local name
    name=$(tui_input "克隆" "新容器名：" "${c}-clone") || return
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || { tui_msg "失败" "名称不合法。"; return; }

    local src dst
    src=$(container_rootfs_path "$c")
    dst=$(container_rootfs_path "$name")
    [ -e "$dst" ] && { tui_msg "失败" "目标已存在。"; return; }

    tui_infobox "克隆中" "复制 ${c} → ${name}…"
    if run_with_logbox "克隆" "${LOG_DIR}/clone.log" \
            cp -a "$src" "$dst"; then
        registry_set "$name" "type" "proot"
        registry_set "$name" "cloned_from" "$c"
        registry_set "$name" "created" "$(date '+%F %T')"
        tui_msg "完成" "克隆完成：${name}"
    else
        rm -rf "$dst"
        tui_msg "失败" "克隆失败。"
    fi
}
rename_container() {
    local cs; cs=$(list_proot_installed)
    [ -z "$cs" ] && return
    local c
    local names=(); local _c; for _c in $cs; do names+=("$_c" "$_c"); done
    c=$(tui_menu "重命名" "选择容器：" ${names[@]+"${names[@]}"}) || return
    [ -z "$c" ] && return
    local n
    n=$(tui_input "重命名" "新名称：" "$c") || return
    [ "$n" = "$c" ] && return
    [[ "$n" =~ ^[a-zA-Z0-9_-]+$ ]] || { tui_msg "失败" "名称不合法。"; return; }

    local src dst
    src=$(container_rootfs_path "$c"); dst=$(container_rootfs_path "$n")
    [ -e "$dst" ] && { tui_msg "失败" "目标已存在。"; return; }
    mv "$src" "$dst"
    # 迁移元数据
    registry_init
    local tmp; tmp=$(mktemp)
    jq --arg o "$c" --arg n "$n" \
        'if .containers[$o] then .containers[$n] = .containers[$o] | del(.containers[$o]) else . end' \
        "$REGISTRY" > "$tmp" && mv "$tmp" "$REGISTRY"
    tui_msg "完成" "已重命名：$c → $n"
}
lifecycle_menu() {
    while :; do
        local c
        c=$(tui_menu "容器生命周期" "选择操作：" \
            export  "导出容器 (tar)" \
            import  "导入容器" \
            backup  "备份（含元数据）" \
            restore "从备份恢复" \
            clone   "克隆容器" \
            rename  "重命名容器" \
            back    "返回") || return
        case "$c" in
            export)  export_container ;;
            import)  import_container ;;
            backup)  backup_container ;;
            restore) restore_container ;;
            clone)   clone_container ;;
            rename)  rename_container ;;
            back|"") return ;;
        esac
    done
}
proot_menu() {
    while :; do
        local c
        c=$(tui_menu "proot 容器" "管理：" \
            install "安装发行版" \
            start   "启动容器" \
            helper  "运行容器内助手" \
            remove  "删除容器" \
            back    "返回") || return
        case "$c" in
            install) install_proot_distro ;;
            start)   start_proot_container ;;
            helper)
                local cs; cs=$(list_proot_installed)
                [ -z "$cs" ] && { tui_msg "提示" "暂无容器。"; continue; }
                local cc
                local names=(); local _c; for _c in $cs; do names+=("$_c" "$_c"); done
                cc=$(tui_menu "助手" "选择容器：" ${names[@]+"${names[@]}"}) || continue
                [ -n "$cc" ] && run_container_helper "$cc" ;;
            remove)  remove_proot_container ;;
            back|"") return ;;
        esac
    done
}
