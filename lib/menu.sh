#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike menu.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# ============================================================
#  设置（新增 #6：集中管理）
# ============================================================
show_settings() {
    local c
    c=$(tui_menu "设置与状态" "选择操作：" \
        view   "查看状态" \
        helper "更新所有容器的助手" \
        back   "返回") || return
    case "$c" in
        view)
            local out
            out="TMOE 版本：${TMOE_VERSION}\n"
            out+="架构：$(detect_arch)\n"
            out+="日志目录：${LOG_DIR}\n"
            out+="备份目录：${BACKUP_DIR}\n"
            out+="注册表：${REGISTRY}\n"
            out+="更新源：$(tmo_repo_url)\n"
            out+="chroot 强校验：$(config_get chroot_require_sha yes)\n"
            out+="\n---- 容器 ----\n"
            registry_init
            out+=$(jq -r '.containers | to_entries[] | "\(.key) [\(.value.type // "?")] \(.value.distro // "") \(.value.desktop // "")"' "$REGISTRY" 2>/dev/null)
            tui_msg "设置与状态" "$out" ;;
        helper) update_all_helpers ;;
        back|"") return ;;
    esac
}

# ============================================================
#  主菜单
# ============================================================
main_menu() {
    while :; do
        local c
        c=$(tui_menu "TMOE-LIKE v${TMOE_VERSION}" "主菜单：" \
            1 "proot 容器管理" \
            2 "chroot 容器管理（需 root）" \
            3 "桌面环境安装" \
            4 "常用软件（进入容器助手）" \
            5 "生命周期（导出/备份/克隆）" \
            6 "SSH 服务" \
            7 "VNC 服务" \
            8 "Termux 美化" \
            9 "运行插件" \
            s "查看状态/设置" \
            u "检查更新" \
            r "回滚到上一版本" \
            0 "退出") || exit 0
        case "$c" in
            1) proot_menu ;;
            2) chroot_menu ;;
            3) desktop_menu ;;
            4) software_menu ;;
            5) lifecycle_menu ;;
            6) ssh_menu ;;
            7) vnc_menu ;;
            8) beautify_termux ;;
            9) run_plugins ;;
            s) show_settings ;;
            u) self_update ;;
            r) rollback_self ;;
            0|"") exit 0 ;;
        esac
    done
}
