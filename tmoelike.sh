#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  tmoelike.sh v2.2 —— 类 TMOE 的 Termux Linux 容器管理器（入口）
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#
#  本项目已按职责拆分为 lib/*.sh：
#    common/tui/archive/deps/paths/registry/download/proot/helper
#    chroot/desktop/ssh/vnc/beautify/plugin/update/backup_util/menu/cli
#  本文件只负责：bootstrap（shell 选项/路径/日志）→ 加载模块 → 分发。
#  模块需与 lib/ 同目录部署；TMOE_LIB 可覆盖 lib 路径。
# ============================================================
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# TMOE_LIB 可被显式覆盖（测试用）；否则取脚本同目录下的 lib/
if [ -z "${TMOE_LIB:-}" ]; then
    _tmo_self="${BASH_SOURCE[0]:-}"
    if [ -n "$_tmo_self" ] && [ -d "$(dirname "$_tmo_self")/lib" ]; then
        TMOE_LIB="$(cd "$(dirname "$_tmo_self")/lib" && pwd -P)"
    elif [ -d "${HOME}/.tmoelike/lib" ]; then
        TMOE_LIB="${HOME}/.tmoelike/lib"
    else
        printf '错误：未找到 tmoelike 的 lib/ 目录（可用 TMOE_LIB 指定）。\n' >&2
        exit 1
    fi
fi

_tmo_mods=(
    common tui archive deps paths registry download proot helper
    chroot desktop ssh vnc beautify plugin update backup_util menu cli
)
for _m in "${_tmo_mods[@]}"; do
    if [ ! -f "${TMOE_LIB}/${_m}.sh" ]; then
        printf '错误：缺少模块 %s/%s.sh\n' "$TMOE_LIB" "$_m" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "${TMOE_LIB}/${_m}.sh"
done
unset _m _tmo_self



main "$@"
