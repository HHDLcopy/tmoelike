#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike ssh.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# ============================================================
#  SSH（修复 #10）
# ============================================================
SSH_DIR="${HOME}/.ssh"
SSHD_CONFIG="${CONFIG_DIR}/sshd_config"

setup_ssh() {
    pkg install -y openssh >/dev/null 2>&1

    local port
    port=$(tui_input "SSH 端口" "监听端口：" "8022") || return
    [ -z "$port" ] && port=8022

    local auth_mode
    auth_mode=$(tui_menu "认证方式" "选择：" \
        key   "仅密钥登录（推荐）" \
        both  "密钥 + 密码" \
        pass  "仅密码（需先设置密码）") || return

    # 生成或复用 host key
    local ssh_prefix="${PREFIX:-/data/data/com.termux/files/usr}"
    [ -f "${ssh_prefix}/etc/ssh/ssh_host_ed25519_key" ] || ssh-keygen -A

    local pass_auth="no" pubkey_auth="yes"
    case "$auth_mode" in
        both) pass_auth="yes" ;;
        pass) pass_auth="yes"; pubkey_auth="no" ;;
    esac

    mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"
    if [ ! -f "${SSH_DIR}/id_ed25519" ]; then
        ssh-keygen -t ed25519 -N "" -f "${SSH_DIR}/id_ed25519"
    fi
    # 写入 authorized_keys
    cat "${SSH_DIR}/id_ed25519.pub" >> "${SSH_DIR}/authorized_keys" 2>/dev/null || true
    sort -u "${SSH_DIR}/authorized_keys" -o "${SSH_DIR}/authorized_keys"
    chmod 600 "${SSH_DIR}/authorized_keys"

    # 安全加固：默认只监听 127.0.0.1，需显式选择才暴露到局域网
    local listen_addr="127.0.0.1"
    local allow_lan; allow_lan=$(config_get ssh_allow_lan no)
    if [ "$allow_lan" = "yes" ]; then
        listen_addr="0.0.0.0"
    else
        if tui_yesno "监听范围" "是否允许局域网访问 SSH？\n\n默认仅 127.0.0.1（更安全）。\n局域网访问会把 sshd 暴露给同网段设备。"; then
            listen_addr="0.0.0.0"
            config_set ssh_allow_lan yes
        else
            config_set ssh_allow_lan no
        fi
    fi

    cat > "$SSHD_CONFIG" <<EOF
Port ${port}
ListenAddress ${listen_addr}
HostKey ${ssh_prefix}/etc/ssh/ssh_host_ed25519_key
PubkeyAuthentication ${pubkey_auth}
PasswordAuthentication ${pass_auth}
PermitRootLogin no
UsePAM no
AllowUsers $(whoami)
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 60
EOF

    if [ "$auth_mode" = "pass" ] || [ "$auth_mode" = "both" ]; then
        if ! tui_yesno "设置密码" "是否需要现在设置 Termux 用户密码？"; then
            :
        else
            passwd
        fi
    fi

    local scope="仅本机 (127.0.0.1)"
    [ "$listen_addr" = "0.0.0.0" ] && scope="局域网可访问"
    tui_msg "完成" "SSH 已配置。\n端口：${port}\n监听：${scope}\n公钥：${SSH_DIR}/id_ed25519.pub"
}
start_ssh() {
    pgrep -x sshd >/dev/null 2>&1 && { tui_msg "SSH" "sshd 已在运行。"; return; }
    [ -f "$SSHD_CONFIG" ] || { tui_msg "提示" "请先配置 SSH。"; return; }
    sshd -f "$SSHD_CONFIG"
    tui_msg "SSH" "已启动。"
}
ssh_menu() {
    while :; do
        local c
        c=$(tui_menu "SSH" "管理：" \
            config "配置 SSH" \
            start  "启动 SSH" \
            stop   "停止 SSH" \
            pubkey "查看公钥" \
            back   "返回") || return
        case "$c" in
            config) setup_ssh ;;
            start)  start_ssh ;;
            stop)   pkill -x sshd && tui_msg "SSH" "已停止。" || tui_msg "SSH" "未运行。" ;;
            pubkey) [ -f "${SSH_DIR}/id_ed25519.pub" ] && tui_msg "公钥" "$(cat "${SSH_DIR}/id_ed25519.pub")" || tui_msg "提示" "尚未生成公钥。" ;;
            back|"") return ;;
        esac
    done
}
