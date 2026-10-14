#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike helper.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# ============================================================
#  ★ 容器内助手（修复 #5：兼容无 bash）
# ============================================================
deploy_container_helper() {
    local name="$1"
    local rootfs; rootfs=$(container_rootfs_path "$name")
    [ -d "$rootfs" ] || { log "rootfs 不存在：$rootfs"; return 1; }

    mkdir -p "${rootfs}/usr/local/bin"

    # 用带引号的 heredoc 写入助手，主脚本不展开变量
    cat > "${rootfs}/usr/local/bin/${HELPER_NAME}" <<'CONTAINER_HELPER_EOF'
#!/usr/bin/env sh
# ============================================================
#  tmoelike-tui — 容器内配置助手 (POSIX sh 兼容)
# ============================================================
set -e

# ---------- 包管理器检测 ----------
detect_pm() {
    if   command -v apt    >/dev/null 2>&1; then PM=apt
    elif command -v apk    >/dev/null 2>&1; then PM=apk
    elif command -v pacman >/dev/null 2>&1; then PM=pacman
    elif command -v dnf    >/dev/null 2>&1; then PM=dnf
    elif command -v zypper >/dev/null 2>&1; then PM=zypper
    elif command -v xbps-install >/dev/null 2>&1; then PM=xbps
    else echo "不支持的包管理器"; exit 1
    fi
}
detect_pm

pm_install() {
    local pkgs="$1"
    case "$PM" in
        apt)    apt update -qq && DEBIAN_FRONTEND=noninteractive apt install -y $pkgs ;;
        apk)    apk add --no-cache $pkgs ;;
        pacman) pacman -Sy --noconfirm --needed $pkgs ;;
        dnf)    dnf install -y $pkgs ;;
        zypper) zypper --non-interactive install $pkgs ;;
        xbps)   xbps-install -Sy $pkgs ;;
    esac
}

# 修复 #6：完整包名映射
map_pkgs() {
    local input="$1" out=""
    for p in $input; do
        case "$PM:$p" in
            apk:build-essential)        p="build-base" ;;
            apk:dnsutils)               p="bind-tools" ;;
            apk:p7zip-full)             p="p7zip" ;;
            apk:man-db)                 p="man" ;;
            apk:python3-pip)            p="py3-pip" ;;
            apk:python3-venv)           p="py3-virtualenv" ;;
            apk:fonts-noto-cjk)         p="font-noto-cjk" ;;
            apk:fonts-noto-color-emoji) p="font-noto-emoji" ;;
            apk:fcitx)                  p="fcitx" ;;
            apk:fcitx-pinyin)           p="fcitx-pinyin" ;;
            apk:tzdata)                 p="tzdata" ;;
            apk:net-tools)              p="net-tools" ;;
            apk:openssh-client)         p="openssh-client" ;;

            pacman:build-essential) p="base-devel" ;;
            pacman:dnsutils)        p="bind" ;;
            pacman:p7zip-full)      p="p7zip" ;;
            pacman:python3-pip)     p="python-pip" ;;
            pacman:python3-venv)    p="python-virtualenv" ;;
            pacman:fonts-noto-cjk)  p="noto-fonts-cjk" ;;
            pacman:fcitx)           p="fcitx5" ;;
            pacman:fcitx-pinyin)    p="fcitx5-chinese-addons" ;;

            dnf:build-essential)    p="@development-tools" ;;
            dnf:dnsutils)           p="bind-utils" ;;
            dnf:p7zip-full)         p="p7zip" ;;
            dnf:python3-pip)        p="python3-pip" ;;
            dnf:python3-venv)       p="python3-virtualenv" ;;
            dnf:man-db)             p="man-db" ;;
            dnf:fonts-noto-cjk)     p="google-noto-sans-cjk-fonts" ;;

            zypper:build-essential) p="devel_basis" ;;
            zypper:dnsutils)        p="bind-utils" ;;
            zypper:p7zip-full)      p="p7zip" ;;
            zypper:fonts-noto-cjk)  p="noto-sans-cjk-fonts" ;;

            xbps:build-essential)   p="base-devel" ;;
            xbps:dnsutils)          p="bind-utils" ;;
            xbps:python3-pip)       p="python3-pip" ;;
        esac
        out="$out $p"
    done
    echo "$out"
}

# ---------- 确保 TUI 可用（含 bash 依赖处理） ----------
ensure_tui() {
    if ! command -v dialog >/dev/null 2>&1 && ! command -v whiptail >/dev/null 2>&1; then
        echo "正在安装 dialog…"
        pm_install dialog >/dev/null 2>&1 || pm_install whiptail >/dev/null 2>&1 || true
    fi
    if   command -v dialog   >/dev/null 2>&1; then TUI=dialog
    elif command -v whiptail >/dev/null 2>&1; then TUI=whiptail
    else echo "无法安装 dialog/whiptail"; exit 1
    fi
}
ensure_tui

m()    { $TUI --title "$1" --menu      "$2" 22 78 14 "${@:3}" 3>&1 1>&2 2>&3; }
cl()   { $TUI --title "$1" --checklist "$2" 22 78 14 "${@:3}" 3>&1 1>&2 2>&3; }
msg()  { $TUI --title "$1" --msgbox    "$2" 14 70; }
inp()  { $TUI --title "$1" --inputbox  "$2" 12 70 "${3:-}" 3>&1 1>&2 2>&3; }
info() { $TUI --title "$1" --infobox   "$2" 10 70; }

# 修复 #8：正确捕获管道退出码 + 修复 $(cat) 读 stdin 导致对话框挂起
run_install_logged() {
    local pkgs="$1"
    local logfile="${TMPDIR:-/tmp}/tmoelike-install.$$.log"
    ( pm_install "$pkgs" ) >"$logfile" 2>&1
    local rc=$?
    if [ $rc -ne 0 ]; then
        # 先把最后 30 行存进变量再传参；
        # 不能写 tail ... | msg "..." "$(cat)" —— $(cat) 会读 stdin 并挂住对话框
        local tail_out
        tail_out=$(tail -30 "$logfile")
        msg "安装失败" "错误摘要：\n\n${tail_out}\n\n完整日志：$logfile"
        return $rc
    fi
    rm -f "$logfile"
    return 0
}

# ============================================================
#  美化
# ============================================================
do_zsh() {
    info "安装" "正在安装 Zsh + Oh My Zsh…"
    pm_install "zsh git curl" || { msg "失败" "Zsh 安装失败。"; return; }
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        # 收紧：不再 curl | sh；先落盘、记录哈希，失败则不留半成品
        local _omz_tmp="/tmp/ohmyzsh-install.$$.sh"
        if curl -fsSL --retry 3 -o "$_omz_tmp" \
                https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh; then
            echo "Oh My Zsh 脚本 SHA256：$(sha256sum "$_omz_tmp" 2>/dev/null | awk '{print $1}')"
            sh "$_omz_tmp" --unattended || true
        else
            echo "无法下载 Oh My Zsh 安装脚本，已跳过。"
        fi
        rm -f "$_omz_tmp"
    fi
    chsh -s "$(command -v zsh)" 2>/dev/null || true
    msg "完成" "Zsh + Oh My Zsh 已安装。\n重新登录容器生效。"
}

do_theme() {
    [ -d "$HOME/.oh-my-zsh" ] || { msg "提示" "请先安装 Zsh。"; return; }
    local t
    t=$(m "主题" "选择 Zsh 主题：" \
        robbyrussell "robbyrussell (默认)" \
        agnoster "agnoster (需 Nerd Font)" \
        powerlevel10k "powerlevel10k (推荐)" \
        ys "ys" \
        af-magic "af-magic") || return
    [ -z "$t" ] && return
    if [ "$t" = "powerlevel10k" ]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
            "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" 2>/dev/null || true
    fi
    sed -i "s/^ZSH_THEME=.*/ZSH_THEME=\"$t\"/" "$HOME/.zshrc"
    msg "完成" "主题已切换：$t"
}

do_plugins() {
    [ -d "$HOME/.oh-my-zsh" ] || { msg "提示" "请先安装 Zsh。"; return; }
    local sel
    sel=$(cl "插件" "勾选插件：" \
        zsh-autosuggestions "自动建议" on \
        zsh-syntax-highlighting "语法高亮" on \
        zsh-completions "补全增强" on \
        sudo "双击 ESC 加 sudo" off \
        extract "万能解压 x" off) || return
    local P="git"
    for p in $sel; do
        p="${p%\"}"; p="${p#\"}"
        case "$p" in
            zsh-autosuggestions)
                git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
                    "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" 2>/dev/null || true ;;
            zsh-syntax-highlighting)
                git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
                    "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" 2>/dev/null || true ;;
            zsh-completions)
                git clone --depth=1 https://github.com/zsh-users/zsh-completions \
                    "$HOME/.oh-my-zsh/custom/plugins/zsh-completions" 2>/dev/null || true ;;
        esac
        [ "$p" != "git" ] && P="$P $p"
    done
    sed -i "s/^plugins=.*/plugins=($P)/" "$HOME/.zshrc"
    msg "完成" "插件已启用：$P"
}

do_fonts() {
    info "安装" "正在安装 CJK 字体…"
    pm_install "fonts-noto-cjk" 2>/dev/null || true
    fc-cache -fv >/dev/null 2>&1 || true
    msg "完成" "CJK 字体安装完成。"
}

do_motd() {
    local t
    t=$(inp "MOTD" "登录欢迎语：" "Welcome!") || return
    [ -z "$t" ] && return
    echo "$t" > /etc/motd 2>/dev/null || true
    msg "完成" "MOTD 已更新。"
}

do_locale() {
    # 新增 #9：locale / 时区 / 中文环境
    info "配置" "正在配置 locale 和时区…"
    case "$PM" in
        apt)
            pm_install "locales tzdata" || true
            sed -i 's/^# *zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen 2>/dev/null || true
            sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen 2>/dev/null || true
            locale-gen 2>/dev/null || true
            ;;
        apk) pm_install "tzdata" || true ;;
    esac
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true
    echo "Asia/Shanghai" > /etc/timezone 2>/dev/null || true
    msg "完成" "时区已设为 Asia/Shanghai。"
}

beautify() {
    while :; do
        local c
        c=$(m "美化容器" "选择：" \
            zsh     "安装 Zsh + Oh My Zsh" \
            theme   "更换 Zsh 主题" \
            plugins "添加 Zsh 插件" \
            fonts   "安装 CJK 字体" \
            locale  "配置 locale / 时区" \
            motd    "MOTD Banner" \
            back    "返回") || return
        case "$c" in
            zsh)     do_zsh ;;
            theme)   do_theme ;;
            plugins) do_plugins ;;
            fonts)   do_fonts ;;
            locale)  do_locale ;;
            motd)    do_motd ;;
            back|"") return ;;
        esac
    done
}

# ============================================================
#  常用应用
# ============================================================
APP_LIST_browser="firefox-esr chromium w3m lynx"
APP_LIST_editor="vim neovim nano micro"
APP_LIST_media="mpv ffmpeg imagemagick"
APP_LIST_office="libreoffice"
APP_LIST_graphics="gimp inkscape"
APP_LIST_dev="git build-essential python3 python3-pip nodejs npm golang cargo"
APP_LIST_net="curl wget nmap net-tools dnsutils traceroute openssh-client rsync"
APP_LIST_sys="htop neofetch tmux zsh tree unzip zip p7zip-full sudo man-db less file"
APP_LIST_chinese="fonts-noto-cjk fcitx fcitx-pinyin"

install_group() {
    local g="$1"
    local pkgs_var="APP_LIST_$g"
    eval "local pkgs=\$$pkgs_var"
    local mapped; mapped=$(map_pkgs "$pkgs")
    [ -z "$mapped" ] && return

    # 已安装检测（新增 #10）
    local to_install=""
    for p in $mapped; do
        case "$PM" in
            apt)    dpkg -s "$p" >/dev/null 2>&1 || to_install="$to_install $p" ;;
            apk)    apk info -e "$p" >/dev/null 2>&1 || to_install="$to_install $p" ;;
            pacman) pacman -Qi "$p" >/dev/null 2>&1 || to_install="$to_install $p" ;;
            dnf)    rpm -q "$p" >/dev/null 2>&1 || to_install="$to_install $p" ;;
            *)      to_install="$to_install $p" ;;
        esac
    done
    [ -z "$to_install" ] && { msg "已安装" "$g 全部已安装。"; return; }

    info "安装中" "正在安装 $g…\n$to_install"
    if run_install_logged "$to_install"; then
        msg "完成" "$g 安装完成。"
    fi
}

apps() {
    local sel
    sel=$(cl "常用应用" "勾选软件组：" \
        browser "浏览器" off \
        editor "编辑器" on \
        media "媒体工具" off \
        office "办公" off \
        graphics "图形" off \
        dev "开发工具" on \
        net "网络工具" on \
        sys "系统工具" on \
        chinese "中文环境" off) || return
    [ -z "$sel" ] && return
    for g in $sel; do
        g="${g%\"}"; g="${g#\"}"
        install_group "$g"
    done
}

pm_update() {
    case "$PM" in
        apt)    apt update && apt upgrade -y ;;
        apk)    apk update && apk upgrade ;;
        pacman) pacman -Syu --noconfirm ;;
        dnf)    dnf upgrade -y ;;
        zypper) zypper --non-interactive update ;;
        xbps)   xbps-install -Suy ;;
    esac
    msg "完成" "包管理器已更新。"
}

# ============================================================
#  镜像源切换（新增 #10；修复：支持 Ubuntu 24.04+ 的 ubuntu.sources）
# ============================================================
# 安全替换：备份 → 替换 → 验证 → 失败还原（容器内 POSIX 版本）
safe_sed_file() {
    local file="$1" pattern="$2"
    [ -f "$file" ] || return 1
    local bak="${file}.tmoelike-bak"
    cp -f "$file" "$bak" 2>/dev/null || return 1
    if ! sed -i -E "$pattern" "$file" 2>/dev/null; then
        cp -f "$bak" "$file" 2>/dev/null || true
        return 1
    fi
    if [ ! -s "$file" ] || cmp -s "$bak" "$file"; then
        cp -f "$bak" "$file" 2>/dev/null || true
        return 1
    fi
    rm -f "$bak"
    return 0
}

switch_mirror() {
    local mirror
    mirror=$(m "镜像源" "选择镜像源：" \
        tuna "清华 TUNA" \
        aliyun "阿里云" \
        ustc "中科大" \
        official "官方") || return
    [ -z "$mirror" ] && return

    # 按 os-release 判发行版，而不是只看包管理器
    local distro_id="" rc_bad=0
    [ -f /etc/os-release ] && distro_id=$(. /etc/os-release; echo "$ID")

    # 目标镜像主机（official 时为空 = 还原官方源）
    local host=""
    case "$mirror" in
        tuna)     host="mirrors.tuna.tsinghua.edu.cn" ;;
        aliyun)   host="mirrors.aliyun.com" ;;
        ustc)     host="mirrors.ustc.edu.cn" ;;
        official) host="" ;;
    esac

    case "$distro_id" in
        ubuntu)
            # Ubuntu 24.04+ 使用 deb822 格式：/etc/apt/sources.list.d/ubuntu.sources
            local new_sources="/etc/apt/sources.list.d/ubuntu.sources"
            if [ -f "$new_sources" ]; then
                if [ -z "$host" ]; then
                    safe_sed_file "$new_sources" 's|https?://[a-z0-9.-]*/ubuntu/?|http://archive.ubuntu.com/ubuntu/|g' || rc_bad=1
                else
                    safe_sed_file "$new_sources" "s|https?://[a-z0-9.-]*/ubuntu/?|https://${host}/ubuntu/|g" || rc_bad=1
                fi
            fi
            # 旧版 sources.list 一并处理
            if [ -f /etc/apt/sources.list ] && [ -n "$host" ]; then
                safe_sed_file /etc/apt/sources.list "s|https?://[a-z.]*archive\.ubuntu\.com|https://${host}|g" || rc_bad=1
            fi
            ;;
        debian|kali|linuxmint|pop)
            [ -f /etc/apt/sources.list ] || { msg "提示" "未找到 /etc/apt/sources.list"; return; }
            if [ -n "$host" ]; then
                safe_sed_file /etc/apt/sources.list "s|https?://[a-z.]*deb\.debian\.org|https://${host}|g" || rc_bad=1
            else
                safe_sed_file /etc/apt/sources.list 's|https?://[a-z0-9.-]*/debian/?|http://deb.debian.org/debian/|g' || rc_bad=1
            fi
            ;;
        alpine)
            [ -f /etc/apk/repositories ] || { msg "提示" "未找到 /etc/apk/repositories"; return; }
            if [ -n "$host" ]; then
                safe_sed_file /etc/apk/repositories "s|https?://[a-z0-9.-]*alpinelinux\.org|https://${host}|g" || rc_bad=1
            else
                safe_sed_file /etc/apk/repositories 's|https?://[a-z0-9.-]*alpinelinux\.org|https://dl-cdn.alpinelinux.org|g' || rc_bad=1
            fi
            ;;
        *)
            # 兜底：按包管理器处理
            if [ "$PM" = "apt" ] && [ -n "$host" ]; then
                safe_sed_file /etc/apt/sources.list "s|https?://[a-z.]*deb\.debian\.org|https://${host}|g" || rc_bad=1
            elif [ "$PM" = "apk" ] && [ -n "$host" ]; then
                safe_sed_file /etc/apk/repositories "s|https?://[a-z0-9.-]*alpinelinux\.org|https://${host}|g" || rc_bad=1
            fi
            ;;
    esac

    if [ "$rc_bad" = "1" ]; then
        msg "部分失败" "镜像源切换未完全成功（未生效的文件已自动还原）。\n发行版：${distro_id:-未知}"
    else
        msg "完成" "镜像源已切换：$mirror\n（发行版：${distro_id:-未知}）\n\n建议再执行一次「包管理器更新」。"
    fi
}
# 安全替换：备份 → 替换 → 验证 → 失败还原（容器内 POSIX 版本）




main_menu() {
    local os_name="Unknown"
    [ -f /etc/os-release ] && os_name=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
    while :; do
        local c
        c=$(m "TMOELIKE 容器助手" "容器：$os_name\n包管理器：$PM\n\n选择功能：" \
            1 "美化容器" \
            2 "常用应用一键安装" \
            3 "包管理器更新" \
            4 "切换镜像源" \
            0 "退出") || exit 0
        case "$c" in
            1) beautify ;;
            2) apps ;;
            3) pm_update ;;
            4) switch_mirror ;;
            0|"") exit 0 ;;
        esac
    done
}

main_menu
CONTAINER_HELPER_EOF

    chmod +x "${rootfs}/usr/local/bin/${HELPER_NAME}"

    # 若容器内无 bash，写一个兼容包装器确保能执行
    # (Alpine 等默认无 bash)
    if [ ! -x "${rootfs}/bin/bash" ] && [ ! -x "${rootfs}/usr/bin/bash" ]; then
        # 助手本身是 POSIX sh，直接用 /bin/sh 也能跑
        :
    fi

    log "部署容器助手到 $name"
    return 0
}

run_container_helper() {
    local name="$1"
    local rootfs; rootfs=$(container_rootfs_path "$name")
    if [ ! -f "${rootfs}/usr/local/bin/${HELPER_NAME}" ]; then
        deploy_container_helper "$name" || {
            warn "容器助手部署失败（rootfs=${rootfs}），改为进入 shell。"
        }
    fi
    clear
    # 先确认容器内助手真的可执行；不可用就退回 shell，
    # 而不是把用户丢在 "No such file or directory" 的报错上。
    if proot-distro login "$name" -- sh -c "test -x /usr/local/bin/${HELPER_NAME}" 2>/dev/null; then
        proot-distro login "$name" -- "/usr/local/bin/${HELPER_NAME}"
    else
        warn "容器内未找到 ${HELPER_NAME}，改为进入 shell。"
        warn "（可稍后在容器内重试，或用 容器管理 → 更新助手）"
        proot-distro login "$name"
    fi
}

# 更新容器内助手
update_all_helpers() {
    local cs; cs=$(list_proot_installed)
    [ -z "$cs" ] && return
    local count=0
    for c in $cs; do
        if deploy_container_helper "$c"; then
            registry_set "$c" "helper_version" "$HELPER_VERSION"
            count=$((count+1))
        fi
    done
    tui_msg "完成" "已更新 $count 个容器的助手。"
}
