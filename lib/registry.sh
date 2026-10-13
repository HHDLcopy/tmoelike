#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike registry.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# ============================================================
#  容器元数据注册表（修复 #2、新增 #6）
# ============================================================
registry_init() {
    [ -f "$REGISTRY" ] || echo '{"containers":{}}' > "$REGISTRY"
}
registry_set() {
    local name="$1" key="$2" val="$3"
    registry_init
    local tmp; tmp=$(mktemp)
    jq --arg n "$name" --arg k "$key" --arg v "$val" \
        '.containers[$n] = (.containers[$n] // {}) | .containers[$n][$k] = $v' \
        "$REGISTRY" > "$tmp" && mv "$tmp" "$REGISTRY"
}
registry_get() {
    local name="$1" key="$2" default="${3:-}"
    registry_init
    local v
    v=$(jq -r --arg n "$name" --arg k "$key" '.containers[$n][$k] // empty' "$REGISTRY" 2>/dev/null)
    echo "${v:-$default}"
}
registry_del() {
    local name="$1"
    registry_init
    local tmp; tmp=$(mktemp)
    jq --arg n "$name" 'del(.containers[$n])' "$REGISTRY" > "$tmp" && mv "$tmp" "$REGISTRY"
}
