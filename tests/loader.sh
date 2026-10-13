#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# 测试加载器：载入 lib 模块，不执行 main、不启动 TUI
if [ -z "${TMOE_ROOT:-}" ]; then
    TMOE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fi
export TMOE_ROOT
export TMOE_LIB="${TMOE_ROOT}/lib"
# 夹具 PATH（tests/run.sh 会准备可执行副本；单独跑用例时退回 .patch/bin）
if [ -n "${TMOE_FIXTURES:-}" ] && [ -f "${TMOE_FIXTURES}/jq" ]; then
    case ":${PATH}:" in *":${TMOE_FIXTURES}:"*) ;; *) PATH="${TMOE_FIXTURES}:${PATH}" ;; esac
else
    # 兜底：开发期的夹具目录（可能因文件系统限制不带执行位，
    # 因此 tests/run.sh 的 TMOE_FIXTURES 是首选路径）
    for _d in "${TMOE_ROOT}/.patch/bin" "${HOME}/.tmoelike-testbin"; do
        [ -f "${_d}/jq" ] || continue
        case ":${PATH}:" in *":${_d}:"*) ;; *) PATH="${_d}:${PATH}" ;; esac
    done
    unset _d
fi
export PATH
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true
for _m in common tui archive deps paths registry download proot helper \
          chroot desktop ssh vnc beautify plugin update backup_util menu cli; do
    # shellcheck source=/dev/null
    source "${TMOE_LIB}/${_m}.sh"
done
unset _m
