#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# 回归：TUI 之前必须切到 UTF-8 locale。
# 背景：Termux 默认不设 LANG、proot 容器 LC_CTYPE=POSIX，ncurses 于是按单字节
# 绘制，dialog 里所有中文都变成乱码（终端本身没问题）。
# 实测：容器内 LANG 为空时输出中找不到 "容器"，加上 C.UTF-8 后就能找到。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib_helpers.sh"
export TMOE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export TMOE_LIB="${TMOE_ROOT}/lib"
# shellcheck source=/dev/null
source "${TMOE_ROOT}/tests/loader.sh"
set +e

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

t_suite "管理器：POSIX locale 下切到 UTF-8"
out=$( LC_ALL=POSIX; LANG=''; export LC_ALL LANG
       ensure_utf8_locale
       printf '%s' "$LC_ALL" )
case "$out" in
    *UTF-8*|*utf8*) t_ok "LC_ALL 已切到 UTF-8（$out）" ;;
    *)              t_fail "LC_ALL 已切到 UTF-8" "*UTF-8*" "$out" ;;
esac

t_suite "管理器：已是 UTF-8 时不覆盖用户设置"
out=$( LC_ALL=en_US.UTF-8; export LC_ALL
       ensure_utf8_locale
       printf '%s' "$LC_ALL" )
t_eq "保留 en_US.UTF-8" "en_US.UTF-8" "$out"

t_suite "容器助手（POSIX sh）：同样必须切到 UTF-8"
fn=$(awk '/^ensure_utf8_locale\(\)/,/^}/' "$TMOE_LIB/helper.sh")
if [ -n "$fn" ]; then
    t_ok "从 helper.sh 抽到 ensure_utf8_locale"
else
    t_fail "从 helper.sh 抽到 ensure_utf8_locale" "非空" "空"
fi
{
    printf '%s\n' "$fn"
    cat <<'PROBE'
ensure_utf8_locale
printf '%s' "$LC_ALL"
PROBE
} > "$W/fn.sh"

if command -v dash >/dev/null 2>&1; then
    out=$( LC_ALL=POSIX LANG='' dash "$W/fn.sh" 2>&1 )
    case "$out" in
        *UTF-8*|*utf8*) t_ok "dash 下 LC_ALL 已切到 UTF-8（$out）" ;;
        *)              t_fail "dash 下 LC_ALL 已切到 UTF-8" "*UTF-8*" "$out" ;;
    esac
    if dash -n "$W/fn.sh" 2>"$W/err"; then
        t_ok "抽出的函数是合法 POSIX（dash -n）"
    else
        t_fail "抽出的函数是合法 POSIX（dash -n）" "无语法错误" "$(head -1 "$W/err")"
    fi
else
    t_ok "本机无 dash，跳过 POSIX 行为验证"
fi

t_suite "静态：TUI 起来之前就切换"
dt=$(awk '/^detect_tui\(\)/,/^}/' "$TMOE_LIB/tui.sh")
if printf '%s' "$dt" | grep -v '^[[:space:]]*#' | grep -qF 'ensure_utf8_locale'; then
    t_ok "detect_tui 调用了 ensure_utf8_locale"
else
    t_fail "detect_tui 调用了 ensure_utf8_locale"
fi
# 顺序：必须先切 locale，再起 dialog
n_loc=$(printf '%s\n' "$dt" | grep -v '^[[:space:]]*#' | grep -n 'ensure_utf8_locale' | head -1 | cut -d: -f1)
n_dlg=$(printf '%s\n' "$dt" | grep -v '^[[:space:]]*#' | grep -n 'TUI=dialog' | head -1 | cut -d: -f1)
if [ -n "$n_loc" ] && [ -n "$n_dlg" ] && [ "$n_loc" -lt "$n_dlg" ]; then
    t_ok "切换发生在选 dialog 之前（第 $n_loc 行 < 第 $n_dlg 行）"
else
    t_fail "切换发生在选 dialog 之前" "loc 行号 < dialog 行号" "loc=$n_loc dialog=$n_dlg"
fi
body=$(awk '/^ensure_tui\(\)/,/^}/' "$TMOE_LIB/helper.sh")
if printf '%s' "$body" | grep -v '^[[:space:]]*#' | grep -qF 'ensure_utf8_locale'; then
    t_ok "助手 ensure_tui 调用了 ensure_utf8_locale"
else
    t_fail "助手 ensure_tui 调用了 ensure_utf8_locale"
fi

t_report
