#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# 回归：容器助手必须是"内容过期就重部署"，而不是"文件存在就跳过"。
# 背景：老用户升级管理器后，容器里仍是旧助手，于是持续报
#       `/usr/local/bin/tmoelike-tui: 95: Bad substitution`。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib_helpers.sh"

export TMOE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export TMOE_LIB="${TMOE_ROOT}/lib"
# shellcheck source=/dev/null
source "${TMOE_ROOT}/tests/loader.sh"
set +e

W=$(mktemp -d)
export TMOE_ROOTFS_DIR="$W/installed-rootfs"
trap 'rm -rf "$W"' EXIT

# stale 判定：0 = 需要部署，1 = 已是最新
stale() { container_helper_stale "$1"; }

t_suite "助手缺失 → 需要部署"
mkdir -p "$TMOE_ROOTFS_DIR/ubuntu"
stale ubuntu; t_eq "缺失时 stale=0" "0" "$?"

t_suite "部署后 → 已是最新"
deploy_container_helper ubuntu >/dev/null 2>&1
t_eq "部署返回 0" "0" "$?"
dest="$TMOE_ROOTFS_DIR/ubuntu/usr/local/bin/${HELPER_NAME}"
t_eq "助手已落盘" "yes" "$([ -f "$dest" ] && echo yes || echo no)"
t_eq "助手可执行" "yes" "$([ -x "$dest" ] && echo yes || echo no)"
stale ubuntu; t_eq "刚部署完 stale=1" "1" "$?"

t_suite "内容是旧版本 → 必须重部署（曾经漏掉的那一步）"
cat > "$dest" <<'OLD_HELPER'
#!/usr/bin/env sh
m() { echo "${@:3}"; }
OLD_HELPER
stale ubuntu; t_eq "内容不同时 stale=0" "0" "$?"
container_helper_ensure ubuntu >/dev/null 2>&1
t_eq "ensure 返回 0" "0" "$?"
t_eq "内容已恢复为当前模板" "yes" \
    "$([ "$(cat "$dest")" = "$(helper_template)" ] && echo yes || echo no)"
t_eq "不再含 bash 切片语法（只看可执行行）" "0" \
    "$(awk '/^[[:space:]]*#/ { next } /\$\{[@*]:[0-9]/ { c++ } END { print c+0 }' "$dest")"
stale ubuntu; t_eq "修复后 stale=1" "1" "$?"

t_suite "rootfs/ 子目录布局同样生效"
mkdir -p "$TMOE_ROOTFS_DIR/debian/rootfs"
stale debian; t_eq "缺失时 stale=0" "0" "$?"
container_helper_ensure debian >/dev/null 2>&1
t_eq "落地到 rootfs/ 层" "yes" \
    "$([ -f "$TMOE_ROOTFS_DIR/debian/rootfs/usr/local/bin/${HELPER_NAME}" ] && echo yes || echo no)"
stale debian; t_eq "部署后 stale=1" "1" "$?"

t_suite "容器不存在 → 明确失败"
container_helper_ensure nope >/dev/null 2>&1
t_eq "返回 1" "1" "$?"

t_suite "静态：ensure 的判据不再是「文件是否存在」"
body=$(awk '/^container_helper_ensure\(\)/,/^}/' "$TMOE_LIB/proot.sh")
if printf '%s' "$body" | grep -v '^[[:space:]]*#' | grep -qF 'container_helper_stale'; then
    t_ok "container_helper_ensure 使用 container_helper_stale"
else
    t_fail "container_helper_ensure 未使用 container_helper_stale"
fi
if printf '%s' "$body" | grep -v '^[[:space:]]*#' | grep -qF '[ ! -f '; then
    t_fail "container_helper_ensure 仍只看文件存在性"
else
    t_ok "container_helper_ensure 不再只看文件存在性"
fi

t_suite "静态：run_container_helper 也走同一判据"
rh=$(awk '/^run_container_helper\(\)/,/^}/' "$TMOE_LIB/helper.sh")
if printf '%s' "$rh" | grep -v '^[[:space:]]*#' | grep -qF 'container_helper_stale'; then
    t_ok "run_container_helper 使用 container_helper_stale"
else
    t_fail "run_container_helper 未使用 container_helper_stale"
fi

t_report
