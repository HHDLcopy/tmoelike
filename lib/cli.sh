#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike cli.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# ============================================================
#  CLI 模式（无参数才进 TUI）
# ============================================================
usage() {
    local me; me=$(basename "${0:-tmoelike.sh}")
    cat <<EOF
TMOE-LIKE v${TMOE_VERSION}

用法：
  $me                              进入 TUI（默认）
  $me list                         列出所有容器
  $me install <distro> [--no-helper]   安装（注册元数据 + 部署容器助手）
  $me start <name>                 进入容器 Shell
  $me helper <name>                运行容器内助手
  $me remove <name>                删除容器（含注册表）
  $me export <name> [out.tar.zst]  导出容器
  $me import <archive> <name>      导入容器
  $me backup <name>                备份（校验 + 保留策略）
  $me restore <backup_dir> <name>  从备份恢复
  $me clone <src> <dst>            克隆
  $me rename <old> <new>           重命名
  $me config get <key>             读取设置
  $me config set <key> <value>     写入设置（如 update_repo）
  $me config list                  列出全部设置
  $me rollback                     回滚脚本自身
  $me chroot-clean                 卸载所有 chroot 挂载点并清空记录
  $me status                       显示状态
  $me update                       检查更新
  $me -h|--help                    帮助

全局选项：
  --yes, -Y        非交互确认（等价于 TMOE_ASSUME_YES=1）
  -h, --help       显示帮助

设置项：
  update_repo         自更新源（GitHub Releases API），默认未配置
  chroot_require_sha  chroot 无校验值时是否中止（默认 yes）
EOF
}

cli_list() {
    registry_init
    printf '%-24s %-8s %-12s %s\n' "NAME" "TYPE" "DISTRO" "DESKTOP"
    jq -r '.containers | to_entries[] | "\(.key)\t\(.value.type // "?")\t\(.value.distro // "")\t\(.value.desktop // "")"' \
        "$REGISTRY" 2>/dev/null | while IFS="$(printf '\t')" read -r n t d de; do
            printf '%-24s %-8s %-12s %s\n' "$n" "$t" "$d" "$de"
        done
}
cli_export() {
    local name="$1" out="${2:-${BACKUP_DIR}/${name}-$(date +%Y%m%d-%H%M%S).tar.zst}"
    local rootfs; rootfs=$(container_rootfs_path "$name")
    [ -d "$rootfs" ] || die "容器不存在：$name"
    zstd_create "$rootfs" "$out" 3 || die "导出失败"
    echo "$out"
}
cli_import() {
    local archive="$1" name="$2"
    [ -f "$archive" ] || die "文件不存在：$archive"
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || die "名称不合法"
    local rootfs; rootfs=$(container_rootfs_path "$name")
    [ -e "$rootfs" ] && die "同名容器已存在"
    mkdir -p "$rootfs"
    with_rollback remove_dir "$rootfs" safe_untar "$archive" "$rootfs" || die "导入失败"
    registry_set "$name" "type" "proot"
    registry_set "$name" "imported" "$(date '+%F %T')"
    registry_set "$name" "source" "$archive"
    echo "已导入：$name"
}
cli_backup() {
    local name="$1"
    local rootfs; rootfs=$(container_rootfs_path "$name")
    [ -d "$rootfs" ] || die "容器不存在：$name"
    local ts; ts=$(date +%Y%m%d-%H%M%S)
    local bdir="${BACKUP_DIR}/${name}-${ts}"
    mkdir -p "$bdir"
    registry_init
    jq --arg n "$name" '.containers[$n] // {}' "$REGISTRY" > "${bdir}/meta.json"
    zstd_create "$rootfs" "${bdir}/rootfs.tar.zst" 3 || {
        rm -rf "$bdir"; die "备份失败"
    }
    echo "$TMOE_VERSION" > "${bdir}/version"
    verify_backup "$bdir" || { rm -rf "$bdir"; die "备份校验失败"; }
    keep_backups "$name" "$BACKUP_KEEP"
    echo "$bdir"
}
cli_restore() {
    local bdir="$1" name="$2"
    [ -d "$bdir" ] || die "备份目录不存在：$bdir"
    verify_backup "$bdir" || die "备份不完整或已损坏"
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || die "名称不合法"
    local rootfs; rootfs=$(container_rootfs_path "$name")
    [ -e "$rootfs" ] && die "同名容器已存在"
    mkdir -p "$rootfs"
    with_rollback remove_dir "$rootfs" zstd_extract "${bdir}/rootfs.tar.zst" "$rootfs" || die "恢复失败"
    if [ -f "${bdir}/meta.json" ]; then
        local tmp; tmp=$(mktemp)
        jq --arg n "$name" --slurpfile m "${bdir}/meta.json" \
            '.containers[$n] = $m[0]' "$REGISTRY" > "$tmp" && mv "$tmp" "$REGISTRY"
    fi
    echo "已恢复：$name"
}
cli_clone() {
    local src_name="$1" dst_name="$2"
    local s d
    s=$(container_rootfs_path "$src_name"); d=$(container_rootfs_path "$dst_name")
    [ -d "$s" ] || die "源不存在：$src_name"
    [ -e "$d" ] && die "目标已存在：$dst_name"
    cp -a "$s" "$d"
    registry_set "$dst_name" "type" "proot"
    registry_set "$dst_name" "cloned_from" "$src_name"
    echo "已克隆：$src_name → $dst_name"
}
cli_rename() {
    local old="$1" new="$2"
    local s d
    s=$(container_rootfs_path "$old"); d=$(container_rootfs_path "$new")
    [ -d "$s" ] || die "源不存在：$old"
    [ -e "$d" ] && die "目标已存在：$new"
    mv "$s" "$d"
    registry_init
    local tmp; tmp=$(mktemp)
    jq --arg o "$old" --arg n "$new" \
        'if .containers[$o] then .containers[$n] = .containers[$o] | del(.containers[$o]) else . end' \
        "$REGISTRY" > "$tmp" && mv "$tmp" "$REGISTRY"
    echo "已重命名：$old → $new"
}
cli_status() {
    printf 'TMOE-LIKE v%s\n' "$TMOE_VERSION"
    printf '架构：%s\n' "$(detect_arch)"
    printf '日志：%s\n' "$LOG_DIR"
    printf '备份：%s\n' "$BACKUP_DIR"
    printf '注册表：%s\n\n' "$REGISTRY"
    printf '容器：\n'
    cli_list
}
cli_main() {
    local cmd="${1:-}"; [ $# -gt 0 ] && shift
    # 运行类子命令统一检查 proot/tar/proot-distro（只读命令不受影响）
    case "$cmd" in
        install|start|helper|remove)
            run_deps_require ;;
        export|backup|restore)
            export_deps_require zstd ;;
    esac
    case "$cmd" in
        ""|tui)  require_tui ;;
        list)    cli_list ;;
        install)
            [ -n "${1:-}" ] || { usage; exit 2; }
            local distro="$1"; shift || true
            local extra=()
            [ "${1:-}" = "--no-helper" ] && extra=(--no-helper)
            container_install "$distro" ${extra[@]+"${extra[@]}"} || exit 1
            printf '已安装：%s\n' "$distro" ;;
        start)
            [ -n "${1:-}" ] || { usage; exit 2; }
            container_start "$1" shell || exit 1 ;;
        helper)
            [ -n "${1:-}" ] || { usage; exit 2; }
            container_helper_ensure "$1" || exit 1
            container_start "$1" helper || exit 1 ;;
        remove)
            [ -n "${1:-}" ] || { usage; exit 2; }
            container_remove "$1" ;;
        export)
            [ -n "${1:-}" ] || { usage; exit 2; }
            cli_export "$@" ;;
        import)
            [ $# -ge 2 ] || { usage; exit 2; }
            cli_import "$@" ;;
        backup)
            [ -n "${1:-}" ] || { usage; exit 2; }
            cli_backup "$@" ;;
        restore)
            [ $# -ge 2 ] || { usage; exit 2; }
            cli_restore "$@" ;;
        clone)
            [ $# -ge 2 ] || { usage; exit 2; }
            cli_clone "$@" ;;
        rename)
            [ $# -ge 2 ] || { usage; exit 2; }
            cli_rename "$@" ;;
        config)
            local sub="${1:-list}"; shift || true
            case "$sub" in
                get)  [ -n "${1:-}" ] || { usage; exit 2; }; config_get "$1" "${2:-}"; echo ;;
                set)  [ $# -ge 2 ] || { usage; exit 2; }; config_set "$1" "$2" || exit 1; echo "已设置：$1" ;;
                list) config_list ;;
                *)    usage; exit 2 ;;
            esac ;;
        chroot-clean)
            cleanup_chroots || exit 1 ;;
        status)   cli_status ;;
        update)   self_update ;;
        rollback) TUI=$(command -v dialog 2>/dev/null || command -v whiptail 2>/dev/null || echo dialog); rollback_self ;;
        -h|--help|help) usage ;;
        *) usage; exit 2 ;;
    esac
}
require_tui() {
    detect_tui
    registry_init
    ensure_deps
    log "TMOE v${TMOE_VERSION} 启动"
    main_menu
}
main() {
    # 剥离全局选项（--yes / -Y），其余交给子命令
    local -a args=()
    local a
    for a in "$@"; do
        case "$a" in
            --yes|-Y) export TMOE_ASSUME_YES=1 ;;
            *) args+=("$a") ;;
        esac
    done
    set -- ${args[@]+"${args[@]}"}

    if [ $# -eq 0 ]; then
        require_tui
    else
        registry_init
        # CLI 模式：非交互依赖检查（含 proot-distro，与 TUI 同一套规则）
        require_deps
        cli_main "$@"
    fi
}
