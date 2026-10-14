#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# 用例：proot-distro 发行版可用性判定
#
# 背景：proot-distro 刚安装时发行版列表为空（需先 `proot-distro update`），
#       旧实现直接 grep list，导致所有发行版都被判成"不支持"。
# 现在 distro_available 会在列表为空时自动执行 update 后重试。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib_helpers.sh"

export TMOE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export TMOE_LIB="${TMOE_ROOT}/lib"
# shellcheck source=/dev/null
source "${TMOE_ROOT}/tests/loader.sh"
set +e

FAKE=$(mktemp -d)
MARK="$FAKE/updated"
# 假 proot-distro：update 之前 list 为空；update 之后列出 ubuntu/alpine
cat > "$FAKE/proot-distro" <<EOS
#!/bin/sh
case "\$1" in
  list)
    [ -f "$MARK" ] && { echo "  ubuntu"; echo "  alpine"; echo "  debian"; }
    ;;
  update) touch "$MARK" ;;
esac
exit 0
EOS
chmod +x "$FAKE/proot-distro"
cleanup() { rm -rf "$FAKE"; }
trap cleanup EXIT

t_suite "distro_available：列表为空时自动 proot-distro update"
rm -f "$MARK"
pre=$(PATH="$FAKE:$PATH" proot-distro list)
t_eq "update 前列表为空" "" "$pre"
PATH="$FAKE:$PATH" distro_available ubuntu >/dev/null 2>&1; rc=$?
t_eq "自动 update 后判定可用" "0" "$rc"
t_eq "确实写入了 update 标记" "1" "$([ -f "$MARK" ] && echo 1 || echo 0)"

t_suite "distro_available：不存在/未支持的发行版"
PATH="$FAKE:$PATH" distro_available nosuchdistro >/dev/null 2>&1; rc=$?
t_eq "正确判定不可用（非 0）" "1" "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"

t_suite "回归：两个调用方都改用 distro_available（不再各自裸 grep）"
# 注意 distro_available 内部本来就要 grep list，这里检查的是调用方。
for fn in install_proot_distro container_install; do
    body=$(awk "/^${fn}\(\)/,/^}/" "$TMOE_LIB/proot.sh")
    if printf '%s' "$body" | grep -qF 'distro_available'; then
        t_ok "${fn} 使用了 distro_available"
    else
        t_fail "${fn} 未使用 distro_available（仍可能把空列表误判为不支持）"
    fi
    if printf '%s' "$body" | grep -qF 'proot-distro list'; then
        t_fail "${fn} 仍直接调用 proot-distro list"
    else
        t_ok "${fn} 不再直接调用 proot-distro list"
    fi
done

t_report
