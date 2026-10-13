#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike vnc.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# ============================================================
#  VNC（修复 #11）
# ============================================================
setup_vnc() {
    if ! pkg install -y tigervnc >/dev/null 2>&1; then
        tui_msg "失败" "tigervnc 安装失败。"
        return
    fi

    local cs; cs=$(list_proot_installed)
    local container="" de="none"
    if [ -n "$cs" ]; then
        local c
        c=$(tui_menu "VNC 目标" "选择容器（none 为 Termux 本机）：" \
            none "Termux 本机 xterm" \
            $(for x in $cs; do echo "$x"; echo "$x"; done)) || return
        container="$c"
        [ "$container" != "none" ] && de=$(registry_get "$container" "desktop" "none")
    fi

    local resolution
    resolution=$(tui_menu "分辨率" "选择屏幕分辨率：" \
        "1280x720"  "1280x720" \
        "1920x1080" "1920x1080 (FHD)" \
        "2560x1440" "2560x1440 (QHD)" \
        "custom"    "自定义") || return
    if [ "$resolution" = "custom" ]; then
        resolution=$(tui_input "分辨率" "输入 WxH：" "1280x720") || return
    fi

    local password
    password=$(tui_input "VNC 密码" "VNC 密码（8 位以内）：" "") || return
    [ -z "$password" ] && { tui_msg "取消" "密码不能为空。"; return; }
    if [ ${#password} -lt 6 ]; then
        tui_yesno "弱密码" "密码长度不足 6 位，继续？" || return
    fi

    mkdir -p "${HOME}/.vnc"
    printf '%s\n' "$password" | vncpasswd -f > "${HOME}/.vnc/passwd"
    chmod 600 "${HOME}/.vnc/passwd"

    local start_cmd; start_cmd=$(desktop_start_cmd "$de")

    if [ "$container" = "none" ]; then
        cat > "${HOME}/.vnc/xstartup" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
exec xterm -geometry 80x24+10+10 -ls &
EOF
    else
        cat > "${HOME}/.vnc/xstartup" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
export DISPLAY=:1 XDG_RUNTIME_DIR=/tmp
exec proot-distro login ${container} --shared-tmp -- /bin/sh -c \
    "export DISPLAY=:1 XDG_RUNTIME_DIR=/tmp; ${start_cmd}"
EOF
    fi
    chmod +x "${HOME}/.vnc/xstartup"

    registry_set "vnc" "container" "$container"
    registry_set "vnc" "resolution" "$resolution"
    registry_set "vnc" "desktop" "$de"

    # 安全加固：默认仅监听 127.0.0.1
    local localonly="yes"
    if tui_yesno "监听范围" "是否允许局域网访问 VNC？\n\n默认仅 127.0.0.1（更安全）。\n局域网访问会把桌面暴露给同网段设备。"; then
        localonly="no"
    fi
    registry_set "vnc" "localonly" "$localonly"

    local scope="仅本机 (127.0.0.1)"
    [ "$localonly" = "no" ] && scope="局域网可访问"
    tui_msg "完成" "VNC 已配置。\n容器：${container}  桌面：${de}\n分辨率：${resolution}\n监听：${scope}\n端口：5901"
}
start_vnc() {
    pgrep -f "Xvnc.*:1" >/dev/null 2>&1 && { tui_msg "VNC" "已在运行。"; return; }
    [ -f "${HOME}/.vnc/passwd" ] || { tui_msg "提示" "请先配置 VNC。"; return; }
    local res localonly
    res=$(registry_get "vnc" "resolution" "1280x720")
    localonly=$(registry_get "vnc" "localonly" "yes")
    if ! vncserver :1 -geometry "$res" -depth 24 -localhost "$localonly"; then
        tui_msg "失败" "启动失败，查看 ~/.vnc/*.log"
        return
    fi
    if [ "$localonly" = "yes" ]; then
        tui_msg "VNC" "已启动，端口 5901（仅本机）。"
    else
        tui_msg "VNC" "已启动，端口 5901（局域网可访问）。"
    fi
}
stop_vnc() {
    vncserver -kill :1 2>/dev/null && tui_msg "VNC" "已停止。" || tui_msg "VNC" "未运行。"
}
vnc_menu() {
    while :; do
        local c
        c=$(tui_menu "VNC" "管理：" \
            config "配置 VNC" \
            start  "启动 VNC" \
            stop   "停止 VNC" \
            back   "返回") || return
        case "$c" in
            config) setup_vnc ;;
            start)  start_vnc ;;
            stop)   stop_vnc ;;
            back|"") return ;;
        esac
    done
}
