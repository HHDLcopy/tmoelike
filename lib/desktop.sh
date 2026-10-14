#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike desktop.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# 通过 os-release 探测容器内包管理器（不再硬编码 apt）
detect_container_pm() {
    local name="$1"
    local osid=""
    osid=$(proot-distro login "$name" -- /bin/sh -c \
        '. /etc/os-release 2>/dev/null && echo "$ID"' 2>/dev/null | tail -n1)
    case "$osid" in
        ubuntu|debian|kali|linuxmint|pop)   echo "apt" ;;
        alpine)                             echo "apk" ;;
        arch|archlinux|manjaro|endeavouros) echo "pacman" ;;
        fedora|rhel|centos|rocky|almalinux) echo "dnf" ;;
        opensuse*|sles|suse)                echo "zypper" ;;
        void)                               echo "xbps" ;;
        *)                                  echo "unknown" ;;
    esac
}

# 按 (包管理器, 桌面) 组合给出安装命令
install_de_pkgs() {
    local name="$1" de="$2"
    local pm; pm=$(detect_container_pm "$name")
    if [ "$pm" = "unknown" ] || [ -z "$pm" ]; then
        warn "无法识别 $name 的包管理器"
        return 1
    fi

    local pkgs=""
    case "$pm:$de" in
        apt:xfce)      pkgs="xfce4 xfce4-goodies xfce4-terminal dbus-x11" ;;
        apk:xfce)      pkgs="xfce4 xfce4-terminal dbus" ;;
        pacman:xfce)   pkgs="xfce4 xfce4-goodies xfce4-terminal dbus" ;;
        dnf:xfce)      pkgs="@xfce-desktop xfce4-terminal dbus-x11" ;;
        zypper:xfce)   pkgs="patterns-xfce-xfce xfce4-terminal dbus-1-x11" ;;

        apt:lxqt)      pkgs="lxqt qterminal dbus-x11" ;;
        apk:lxqt)      pkgs="lxqt qterminal dbus" ;;
        pacman:lxqt)   pkgs="lxqt qterminal dbus" ;;
        dnf:lxqt)      pkgs="@lxqt-desktop qterminal dbus-x11" ;;
        zypper:lxqt)   pkgs="patterns-lxqt-lxqt qterminal dbus-1-x11" ;;

        apt:lxde)      pkgs="lxde lxterminal dbus-x11" ;;
        apk:lxde)      pkgs="lxde lxterminal dbus" ;;
        pacman:lxde)   pkgs="lxde lxterminal dbus" ;;

        apt:mate)      pkgs="mate-desktop-environment mate-terminal dbus-x11" ;;
        apk:mate)      pkgs="mate-desktop-environment mate-terminal dbus" ;;
        pacman:mate)   pkgs="mate mate-terminal dbus" ;;

        apt:kde)       pkgs="kde-plasma-desktop konsole dbus-x11" ;;
        apk:kde)       pkgs="plasma-desktop konsole dbus" ;;
        pacman:kde)    pkgs="plasma konsole dbus" ;;
        dnf:kde)       pkgs="@kde-desktop konsole dbus-x11" ;;

        apt:gnome)     pkgs="gnome-shell gnome-terminal dbus-x11" ;;
        apk:gnome)     pkgs="gnome-shell gnome-terminal dbus" ;;
        pacman:gnome)  pkgs="gnome gnome-terminal dbus" ;;

        apt:i3)        pkgs="i3 i3status dmenu dbus-x11" ;;
        apk:i3)        pkgs="i3wm i3status dmenu dbus" ;;
        pacman:i3)     pkgs="i3-wm i3status dmenu dbus" ;;
        dnf:i3)        pkgs="i3 i3status dmenu dbus-x11" ;;

        apt:xterm)     pkgs="xterm dbus-x11" ;;
        apk:xterm)     pkgs="xterm dbus" ;;
        pacman:xterm)  pkgs="xterm dbus" ;;
        dnf:xterm)     pkgs="xterm dbus-x11" ;;

        *) warn "暂不支持的组合：$pm:$de"; return 1 ;;
    esac

    local cmd=""
    case "$pm" in
        apt)    cmd="apt update && DEBIAN_FRONTEND=noninteractive apt install -y $pkgs" ;;
        apk)    cmd="apk add --no-cache $pkgs" ;;
        pacman) cmd="pacman -Sy --noconfirm --needed $pkgs" ;;
        dnf)    cmd="dnf install -y $pkgs" ;;
        zypper) cmd="zypper --non-interactive install $pkgs" ;;
        xbps)   cmd="xbps-install -Sy $pkgs" ;;
    esac

    run_with_logbox "安装 $de 到 $name" "${LOG_DIR}/de-${name}.log" \
        proot-distro login "$name" -- /bin/sh -c "$cmd"
}
desktop_start_cmd() {
    case "$1" in
        xfce)  echo "startxfce4" ;;
        lxqt)  echo "startlxqt" ;;
        mate)  echo "mate-session" ;;
        kde)   echo "startplasma-x11" ;;
        gnome) echo "gnome-session" ;;
        lxde)  echo "startlxde" ;;
        i3)    echo "i3" ;;
        none)  echo "xterm" ;;
        *)     echo "xterm" ;;
    esac
}
install_desktop() {
    local cs; cs=$(list_proot_installed)
    [ -z "$cs" ] && { tui_msg "提示" "请先安装 proot 容器。"; return; }
    local c
    local names=(); local _c; for _c in $cs; do names+=("$_c" "$_c"); done
    c=$(tui_menu "桌面环境" "选择容器：" ${names[@]+"${names[@]}"}) || return
    [ -z "$c" ] && return

    local de
    de=$(tui_menu "桌面环境" "选择桌面：" \
        xfce  "XFCE4 (轻量推荐)" \
        lxqt  "LXQt" \
        lxde  "LXDE (最轻)" \
        mate  "MATE" \
        kde   "KDE Plasma (重)" \
        gnome "GNOME (重)" \
        i3    "i3 平铺" \
        none  "不装桌面") || return
    [ -z "$de" ] && return

    if [ "$de" != "none" ]; then
        local pm; pm=$(detect_container_pm "$c")
        if [ "$pm" = "unknown" ]; then
            tui_msg "不支持" "无法识别容器 $c 的包管理器，暂不能安装桌面。"
            return
        fi
        tui_infobox "安装 $de" "容器 $c 使用 $pm，正在安装…"

        # 修复：按发行版适配包管理器 + 实时日志窗口
        if install_de_pkgs "$c" "$de"; then
            registry_set "$c" "desktop" "$de"
            registry_set "$c" "desktop_pm" "$pm"
            tui_msg "完成" "$de 已安装到 $c。"
        else
            tui_msg "失败" "安装失败，查看日志：${LOG_DIR}/de-${c}.log"
        fi
    else
        registry_set "$c" "desktop" "none"
    fi
}
desktop_menu() {
    while :; do
        local c
        c=$(tui_menu "桌面环境" "管理：" \
            install "安装桌面" \
            list    "查看已配置" \
            back    "返回") || return
        case "$c" in
            install) install_desktop ;;
            list)
                registry_init
                local out; out=$(jq -r '.containers | to_entries[] | select(.value.desktop) | "\(.key) → \(.value.desktop)"' "$REGISTRY" 2>/dev/null)
                [ -z "$out" ] && out="尚无容器安装桌面。"
                tui_msg "桌面记录" "$out" ;;
            back|"") return ;;
        esac
    done
}

# ============================================================
#  常用软件（主脚本调用容器内包管理器）
# ============================================================
install_software() {
    local cs; cs=$(list_proot_installed)
    [ -z "$cs" ] && { tui_msg "提示" "请先安装 proot 容器。"; return; }
    local c
    local names=(); local _c; for _c in $cs; do names+=("$_c" "$_c"); done
    c=$(tui_menu "软件安装" "选择容器：" ${names[@]+"${names[@]}"}) || return
    [ -z "$c" ] && return

    tui_msg "提示" "建议在容器内通过 ${HELPER_NAME} 安装软件，\n因为容器内助手会自动适配发行版和镜像源。"
    run_container_helper "$c"
}
software_menu() {
    local c
    c=$(tui_menu "常用软件" "选择：" \
        helper "在容器内打开助手（推荐）" \
        back   "返回") || return
    case "$c" in
        helper) install_software ;;
        back|"") return ;;
    esac
}
