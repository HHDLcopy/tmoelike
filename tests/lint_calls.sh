#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# 跨模块调用一致性自检（弥补 CI 之外的本地位检查）：
# 1) 所有被调用的 tmoelike 内部函数都必须有定义
# 2) 以 _ 开头的内部函数必须有使用点
# 3) 公开函数（非 _ 前缀）至少在定义之外被引用一次（排除生命周期/入口）
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT" || exit 1

FILES=(tmoelike.sh lib/*.sh)
DEFS=$(grep -hoE '^[a-z_][a-z0-9_]*\(\)' "${FILES[@]}" | sed 's/()//' | sort -u)
ALL=$(cat "${FILES[@]}")

rc=0

echo "== 1) 被调用但未定义的函数 =="
missing=""
while IFS= read -r fn; do
    [ -n "$fn" ] || continue
    # 只看 tmoelike 自身命名风格（含 tmo_/tui_/cli_/container_/registry_ 等前缀）
    case "$fn" in
        tmo_*|tui_*|cli_*|container_*|registry_*|config_*|deps_*|_deps_*|safe_*|zstd_*|tar_*|mirror*|fetch_*|resolve_*|find_*|list_*|keep_*|verify_*|with_*|run_*|install_*|remove_*|enter_*|mount_*|unmount_*|cleanup_*|deploy_*|show_*|beautify*|do_*|lifecycle_*|proot_*|desktop_*|software_*|ssh_*|vnc_*|plugin*|self_*|update_*|usage|main|require_*|ensure_*|detect_*|get_*|proot_*)
            if ! printf '%s\n' "$DEFS" | grep -qx "$fn"; then
                missing="$missing $fn"
            fi ;;
    esac
done < <(printf '%s\n' "$ALL" | grep -oE '(^|[^a-zA-Z0-9_])[a-z][a-z0-9_]*\(' | tr -d '( ' | sort -u)
if [ -n "$missing" ]; then
    echo "  未定义：$missing"; rc=1
else
    echo "  ok（所有 tmoelike 内部调用均有定义）"
fi

echo "== 2) 内部函数（_ 前缀）是否有使用点 =="
unused=""
while IFS= read -r fn; do
    [ -n "$fn" ] || continue
    n=$(grep -c "\b${fn}\b" "${FILES[@]}" | awk -F: '{s+=$2} END {print s}')
    [ "${n:-0}" -le 1 ] && unused="$unused $fn"
done < <(printf '%s\n' "$DEFS" | grep '^_')
if [ -n "$unused" ]; then
    echo "  仅定义未使用：$unused"; rc=1
else
    echo "  ok（内部函数都有使用点）"
fi

echo "== 3) 公开函数引用次数（仅警告，不失败） =="
never=""
while IFS= read -r fn; do
    case "$fn" in _*|main|require_*) continue ;; esac
    n=$(grep -c "\b${fn}\b" "${FILES[@]}" | awk -F: '{s+=$2} END {print s}')
    [ "${n:-0}" -le 1 ] && never="$never $fn"
done < <(printf '%s\n' "$DEFS")
[ -n "$never" ] && echo "  提示（可能仅测试使用或可删）：$never" || echo "  ok"

exit "$rc"
