#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike beautify.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# ============================================================
#  Termux 美化
# ============================================================
beautify_termux() {
    local c
    c=$(tui_menu "美化 Termux" "选择：" \
        zsh    "Zsh + Oh My Zsh" \
        font   "Nerd Font" \
        color  "Tokyo Night 配色" \
        back   "返回") || return
    case "$c" in
        zsh)
            pkg install -y zsh git curl >/dev/null 2>&1
            # 收紧：不再 curl | sh；先落盘、展示哈希并确认，再带 --unattended 执行
            local ohmyzsh_url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
            # 下载→展示哈希→确认→执行（--unattended 由我们显式传入）
            if ! github_script_run "$ohmyzsh_url" "" "Oh My Zsh 安装脚本" -- --unattended; then
                tui_msg "跳过" "Oh My Zsh 安装脚本未执行。"
            fi
            tui_msg "完成" "Zsh 已安装。" ;;
        font)
            mkdir -p "${HOME}/.termux"
            curl -fsSL -o "${HOME}/.termux/font.ttf" \
                "https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/JetBrainsMono/Ligatures/Regular/JetBrainsMonoNerdFont-Regular.ttf"
            termux-reload-settings
            tui_msg "完成" "Nerd Font 已设置。" ;;
        color)
            mkdir -p "${HOME}/.termux"
            cat > "${HOME}/.termux/colors.properties" <<'EOF'
foreground=#c0caf5
background=#1a1b26
cursor=#c0caf5
color0=#15161e
color1=#f7768e
color2=#9ece6a
color3=#e0af68
color4=#7aa2f7
color5=#bb9af7
color6=#7dcfff
color7=#a9b1d6
EOF
            termux-reload-settings
            tui_msg "完成" "配色已应用。" ;;
        back|"") return ;;
    esac
}
