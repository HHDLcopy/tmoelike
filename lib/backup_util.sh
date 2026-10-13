#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike backup_util.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# ---------- 备份校验 / 保留策略 / 错误回滚 ----------
verify_backup() {
    local bdir="$1"
    [ -f "${bdir}/rootfs.tar.zst" ] || return 1
    zstd_test "${bdir}/rootfs.tar.zst" || return 1
    # jq 可选：缺失时退化为 python/json 粗检，不让备份校验因缺 jq 而失败
    if [ -f "${bdir}/meta.json" ]; then
        if command -v jq >/dev/null 2>&1; then
            jq empty "${bdir}/meta.json" >/dev/null 2>&1 || return 1
        else
            grep -q '^[[:space:]]*{' "${bdir}/meta.json" 2>/dev/null || return 1
        fi
    fi
    return 0
}
list_backups() {
    find_dirs "$BACKUP_DIR" | sort -r
}

# 每个容器只保留最近 N 份备份
keep_backups() {
    local name="$1" keep="${2:-5}"
    [ -d "$BACKUP_DIR" ] || return 0
    local dirs
    dirs=$(list_dirs_by_mtime "$BACKUP_DIR" "${name}-*")
    [ -n "$dirs" ] || return 0
    local i=0 d
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        i=$((i+1))
        if [ "$i" -gt "$keep" ]; then
            rm -rf "$d"
            log "清理旧备份：$d"
        fi
    done <<EOF
$dirs
EOF
}

# 回滚辅助：删除半成品目录（可安全作为 with_rollback 的回滚函数）
remove_dir() { rm -rf "$1"; }

# 失败即回滚的包装器
#   with_rollback <回滚函数> <回滚参数> <待执行命令...>
# 注意：不能用 with_rollback <cmd...> <rollback_fn> 的写法 ——
#       通用 "$@" 无法在调用点尾部追加函数名（会变成 argv[0]），
#       原设计因此必然报 "Is a directory"/"$1: unbound variable"。
with_rollback() {
    local rollback_fn="${1:-}"
    local rollback_arg="${2:-}"
    shift 2
    if ! "$@"; then
        warn "操作失败，执行回滚：${rollback_fn} ${rollback_arg}"
        if [ -n "$rollback_fn" ]; then
            "$rollback_fn" "$rollback_arg" || warn "回滚也失败，请手工检查"
        fi
        return 1
    fi
    return 0
}
