#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike plugin.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# ============================================================
#  插件（修复 #12：安全）
# ============================================================
PLUGIN_TRUSTED_HASHES="${CONFIG_DIR}/plugin_hashes"

# 插件元数据格式（在 .sh 顶部注释）：
#   # @name: 插件名
#   # @desc: 描述
#   # @version: 1.0
#   # @author: xxx
run_plugins() {
    local plugins=()
    for f in "${PLUGIN_DIR}"/*.sh; do
        [ -f "$f" ] || continue
        local name desc ver
        name=$(grep -m1 '^# @name:' "$f" | sed 's/^# @name: *//')
        desc=$(grep -m1 '^# @desc:' "$f" | sed 's/^# @desc: *//')
        ver=$(grep -m1 '^# @version:' "$f" | sed 's/^# @version: *//')
        [ -z "$name" ] && name=$(basename "$f" .sh)
        [ -z "$desc" ] && desc="（无描述）"
        [ -n "$ver" ] && desc="$desc v$ver"
        plugins+=("$f" "$name — $desc")
    done
    ((${#plugins[@]})) || { tui_msg "插件" "插件目录为空。"; return; }

    local chosen
    chosen=$(tui_menu "插件" "选择要运行的插件：" "${plugins[@]}") || return
    [ -z "$chosen" ] && return

    # 供应链：声明式 SHA256 + 本地信任库「记录并复核」。
    # 关键改进：信任库存的是「批准过的精确哈希」，
    # 任何后续改动（包括直接改文件）都会导致复核失败并要求重新确认；
    # 不接受「同哈希即静默通过」的弱判定。
    local declared_sha actual_sha base
    base=$(basename "$chosen")
    declared_sha=$(grep -m1 '^# @sha256:' "$chosen" | awk '{print $3}')
    actual_sha=$(sha256sum "$chosen" | awk '{print $1}')

    if [ -n "$declared_sha" ] && [ "$declared_sha" != "$actual_sha" ]; then
        tui_yesno "校验失败" "插件声明的 SHA256 与实际不符：\n声明：${declared_sha}\n实际：${actual_sha}\n\n该插件可能被篡改，仍要运行？" || return
    fi

    local trusted=""
    if [ -f "$PLUGIN_TRUSTED_HASHES" ]; then
        trusted=$(awk -v f="$base" '$2 == f {print $1}' "$PLUGIN_TRUSTED_HASHES" | tail -n1)
    fi

    if [ -z "$trusted" ]; then
        tui_yesno "首次运行" "该插件尚未信任：\n${chosen}\n\nSHA256：${actual_sha}\n\n运行并信任此版本？" || return
        mkdir -p "$(dirname "$PLUGIN_TRUSTED_HASHES")"
        echo "${actual_sha}  ${base}" >> "$PLUGIN_TRUSTED_HASHES"
        log "信任插件：$base $actual_sha"
    elif [ "$trusted" != "$actual_sha" ]; then
        tui_yesno "内容已变更" "插件已信任版本与当前不符：\n已信任：${trusted}\n当前：  ${actual_sha}\n\n（文件被修改过）仍要运行并更新信任？" || return
        # 替换旧记录（同一个文件只保留一条）
        local tmp; tmp=$(mktemp)
        awk -v f="$base" '$2 != f' "$PLUGIN_TRUSTED_HASHES" > "$tmp" 2>/dev/null || true
        mv "$tmp" "$PLUGIN_TRUSTED_HASHES"
        echo "${actual_sha}  ${base}" >> "$PLUGIN_TRUSTED_HASHES"
        warn "插件 ${base} 的信任哈希已更新"
        log "更新插件信任：$base $actual_sha"
    fi

    if [ -n "${BASH_VERSION:-}" ]; then
        bash "$chosen"
    else
        sh "$chosen"
    fi
}
