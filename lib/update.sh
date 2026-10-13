#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike update.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# ============================================================
#  自更新（新增 #13）
# ============================================================
# 解析更新源：环境变量 > 设置项 > 空（未配置）
tmo_repo_url() {
    local r="${TMOE_REPO:-}"
    [ -n "$r" ] || r=$(config_get update_repo "")
    printf '%s' "$r"
}

self_update() {
    local repo; repo=$(tmo_repo_url)
    if [ -z "$repo" ]; then
        tui_msg "未配置" "尚未配置更新源。\n\n方式一（临时）：\nexport TMOE_REPO=https://api.github.com/repos/<你>/<仓库>/releases/latest\n\n方式二（持久，推荐）：\n$(basename "${0:-tmoelike.sh}") config set update_repo <URL>"
        return 1
    fi

    tui_infobox "更新" "正在查询最新版本…"
    local meta
    meta=$(curl -fsSL "$repo" 2>/dev/null) || { tui_msg "失败" "无法访问更新源。"; return; }

    local tag url_new url_sha
    tag=$(printf '%s' "$meta" | jq -r '.tag_name // empty')
    url_new=$(printf '%s' "$meta" | jq -r '.assets[]? | select(.name|endswith(".sh")) | .browser_download_url' | head -n1)
    url_sha=$(printf '%s' "$meta" | jq -r '.assets[]? | select(.name|endswith(".sh.sha256")) | .browser_download_url' | head -n1)

    [ -z "$tag" ] && { tui_msg "失败" "未能解析版本信息（需要 jq + Releases API）。"; return; }
    [ "$tag" = "v${TMOE_VERSION}" ] || [ "$tag" = "$TMOE_VERSION" ] && { tui_msg "更新" "已是最新：$tag"; return; }
    [ -z "$url_new" ] && { tui_msg "失败" "该 Release 未提供 .sh 资源。"; return; }

    tui_yesno "更新" "发现新版本 $tag（当前 v$TMOE_VERSION）。\n是否更新？" || return

    local tmp; tmp=$(mktemp)
    if ! curl -fL --retry 3 -o "$tmp" "$url_new"; then
        tui_msg "失败" "下载失败。"; rm -f "$tmp"; return
    fi

    # 校验和：优先官方 .sha256，其次 URL 同级 .sha256
    if [ -z "$url_sha" ]; then
        url_sha="${url_new}.sha256"
    fi
    local sha_expected sha_actual
    sha_expected=$(curl -fsSL "$url_sha" 2>/dev/null | awk '{print $1}')
    if [ -n "$sha_expected" ]; then
        sha_actual=$(sha256sum "$tmp" | awk '{print $1}')
        if [ "$sha_expected" != "$sha_actual" ]; then
            tui_msg "失败" "SHA256 不匹配，已放弃。\n期望：$sha_expected\n实际：$sha_actual"
            rm -f "$tmp"; return
        fi
    else
        tui_yesno "警告" "未获取到 SHA256 校验文件。\n继续安装？" || { rm -f "$tmp"; return; }
    fi

    # 备份旧版便于回滚
    local self_path
    self_path="${BASH_SOURCE[0]:-}"
    if [ -z "$self_path" ] || [ ! -f "$self_path" ]; then
        self_path="${SCRIPT_DIR}/tmoelike.sh"
    fi
    if [ ! -f "$self_path" ]; then
        tui_msg "失败" "找不到自身脚本路径，已中止。"; rm -f "$tmp"; return
    fi

    cp -f "$self_path" "${self_path}.bak" || { tui_msg "失败" "备份旧版本失败。"; rm -f "$tmp"; return; }
    if install -m 0755 "$tmp" "$self_path"; then
        rm -f "$tmp"
        tui_msg "完成" "已更新到 $tag。\n旧版本已备份：${self_path}.bak\n\n重新启动脚本后生效。"
        exit 0
    else
        cp -f "${self_path}.bak" "$self_path" 2>/dev/null || true
        rm -f "$tmp"
        tui_msg "失败" "写入失败，已尝试回滚。"
    fi
}

# 回滚到上一版本
rollback_self() {
    local self_path
    self_path="${BASH_SOURCE[0]:-}"
    if [ -z "$self_path" ] || [ ! -f "$self_path" ]; then
        self_path="${SCRIPT_DIR}/tmoelike.sh"
    fi
    if [ ! -f "${self_path}.bak" ]; then
        tui_msg "无备份" "未找到 ${self_path}.bak"
        return
    fi
    tui_yesno "回滚" "确认回滚到上一版本？\n（当前文件会先另存为 .before-rollback）" || return
    cp -f "$self_path" "${self_path}.before-rollback" 2>/dev/null || true
    if install -m 0755 "${self_path}.bak" "$self_path"; then
        tui_msg "完成" "已回滚，请重新启动脚本。"
        exit 0
    fi
    tui_msg "失败" "回滚失败。"
}
