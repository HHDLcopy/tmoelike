#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike tui.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
detect_tui() {
    # 必须赶在 dialog 起来之前：否则中文全画成乱码（说明见 common.sh）
    ensure_utf8_locale
    if   command -v dialog   >/dev/null 2>&1; then TUI=dialog
    elif command -v whiptail >/dev/null 2>&1; then TUI=whiptail
    else
        echo "未检测到 dialog/whiptail，正在自动安装…"
        pkg install -y dialog >/dev/null 2>&1 || \
            die "无法安装 dialog，请手动运行：pkg install dialog"
        TUI=dialog
    fi
}

# ---------- TUI 包装（无 dialog / 未初始化时安全降级） ----------
# 为什么要降级：CLI 子命令会复用 TUI 包装函数，但 CLI 未必初始化过 $TUI，
# 也未必有可用终端；直接展开 $TUI 会在 set -u 下报 unbound variable。
_tui_ok() {
    [ -n "${TUI:-}" ] && command -v "$TUI" >/dev/null 2>&1
}

_tui_banner() {
    local title="$1" text="$2"
    printf '\n===== %s =====\n' "$title"
    if [ -n "$text" ]; then
        printf '%b\n' "$text"
    fi
    printf '%s\n' '------------------------------'
}

tui_menu()      { _tui_ok || { _tui_banner "${1:-选择}" "${2:-}"; printf '需在 TUI 下交互\n' >&2; return 1; }; $TUI --title "$1" --menu      "$2" 22 78 14 "${@:3}" 3>&1 1>&2 2>&3; }
tui_msg()       { _tui_ok || { _tui_banner "${1:-提示}" "${2:-}"; return 0; }; $TUI --title "$1" --msgbox    "$2" 14 70; }
tui_input()     { _tui_ok || { printf '%s' "${3:-}"; return 0; }; $TUI --title "$1" --inputbox  "$2" 12 70 "${3:-}" 3>&1 1>&2 2>&3; }
tui_yesno()     { _tui_ok || { [ "${TMOE_ASSUME_YES:-0}" = "1" ] && return 0; return 1; }; $TUI --title "$1" --yesno     "$2" 10 60; }
tui_infobox()   { _tui_ok || { printf '[%s] %b\n' "${1:-}" "${2:-}"; return 0; }; $TUI --title "$1" --infobox   "$2" 10 70; }

# 实时日志窗口（修复：tailbox 不自动关 + 真实退出码 + 归档脱敏）
#
# 退出码通过哨兵行 __EXIT__:N 传递，避免 wait 丢失状态；
# 通过后台监视器在哨兵出现后关闭 dialog，长任务结束后窗口自动消失。
run_with_logbox() {
    local title="$1" logfile="$2"; shift 2
    local tmp; tmp=$(mktemp)
    local rc=1

    # 关键：子 shell 里顺序写「哨兵行」，因此任何退出路径都会留下标记。
    # 调用方即使把本函数放在 if 条件里（父 shell 因 set -e 提前退出），
    # 任务与哨兵也已写入，窗口不会卡住。
    {
        "$@"
        printf '__EXIT__:%d\n' "$?"
    } >"$tmp" 2>&1 &

    local prog=$!

    if command -v dialog >/dev/null 2>&1 && [ -t 1 ]; then
        # 用控制 FIFO 接收 dialog 的 PID：没有「监视器早于 dialog 启动」的竞态，
        # 也不需要轮询 pid 文件。
        local ctl; ctl=$(mktemp -u)
        local dlg_pid=""
        if mkfifo "$ctl" 2>/dev/null; then
            # 后台任务完成即关闭窗口（不依赖用户按键）
            (
                wait "$prog" 2>/dev/null || true
                if read -r dlg_pid < "$ctl"; then
                    sleep 1                      # 让最后一屏输出可见
                    [ -n "$dlg_pid" ] && kill "$dlg_pid" 2>/dev/null || true
                fi
            ) &
            local closer=$!

            dialog --title "$title" --tailbox "$tmp" 22 78 2>/dev/null || true
            # dialog 返回后把 PID 交给 closer（打开 FIFO 会解除其阻塞）
            printf '%s\n' "$$" > "$ctl" 2>/dev/null || true
            kill "$closer" 2>/dev/null || true
        else
            # 无法创建 FIFO：退回 programbox，牺牲实时性换确定性
            wait "$prog" 2>/dev/null || true
            dialog --title "$title" --programbox "$tmp" 22 78 </dev/tty >/dev/tty 2>&1 || true
        fi
        rm -f "$ctl"
    else
        # 非交互（无 dialog / 非终端）：等任务结束。
        # 不直接 cat 原始日志（会绕过脱敏、把敏感值打到终端/CI 日志），
        # 只输出一行摘要，指向已脱敏的归档文件。
        wait "$prog" 2>/dev/null || true
        local _rc_x _out_log
        _rc_x=$(grep -o '__EXIT__:[0-9]*' "$tmp" | tail -n1 | cut -d: -f2)
        _out_log="${logfile:-${LOG_DIR}/$(date +%s).log}"
        printf '[%s] 任务结束（退出码 %s），日志：%s\n' \
            "$title" "${_rc_x:-?}" "$_out_log"
    fi

    wait "$prog" 2>/dev/null || true
    rc=$(grep -o '__EXIT__:[0-9]*' "$tmp" | tail -n1 | cut -d: -f2)
    rc=${rc:-1}
    sed -i '/^__EXIT__:[0-9]*$/d' "$tmp" 2>/dev/null || true

    # 归档：先脱敏再落盘
    if [ -n "$logfile" ]; then
        sanitize_file "$tmp" "$logfile"
    else
        sanitize_file "$tmp" "${LOG_DIR}/$(date +%s).log"
    fi
    rm -f "$tmp"
    return "$rc"
}

# ============================================================
#  交互适配层：让 TUI 与 CLI 走同一套核心逻辑
#  TUI 用 dialog 提问；CLI 用默认值/参数，并在需要时要求显式确认。
# ============================================================
tmo_yesno() {
    # tmo_yesno <标题> <问题> [--default yes|no]
    local title="$1" prompt="$2"; shift 2
    local def="no"
    [ "${1:-}" = "--default" ] && { def="${2:-no}"; shift 2; }
    if [ "${TMOE_ASSUME_YES:-0}" = "1" ]; then
        log "自动确认（TMOE_ASSUME_YES=1）：$prompt"
        return 0
    fi
    if [ ! -t 0 ]; then
        [ "$def" = "yes" ] && return 0 || return 1
    fi
    tui_yesno "$title" "$prompt"
}

tmo_input() {
    # tmo_input <标题> <提示> <值> [--default 值]
    local title="$1" prompt="$2" value="${3:-}"; shift 3 2>/dev/null || shift $#
    if [ "${1:-}" = "--default" ]; then
        value="${2:-$value}"
    fi
    if [ -n "$value" ]; then printf '%s' "$value"; return 0; fi
    if [ -t 0 ] && [ -n "${TUI:-}" ]; then
        tui_input "$title" "$prompt" ""
    else
        printf '%s' ""
    fi
}
