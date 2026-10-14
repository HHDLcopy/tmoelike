#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# 用例：容器枚举与发行版安装
#
# 关键认知：`proot-distro list` 只反映**已安装**状态，不能用它判断
# "proot-distro 支持哪些发行版"，否则所有未安装的发行版都会被误判为不支持。
#   - 枚举已安装容器：扫 rootfs 目录（容器本质就是目录）
#   - 安装发行版：直接 proot-distro install，不做"支持与否"的预检查
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib_helpers.sh"

export TMOE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export TMOE_LIB="${TMOE_ROOT}/lib"
# shellcheck source=/dev/null
source "${TMOE_ROOT}/tests/loader.sh"
set +e

t_suite "静态检查：不再用 proot-distro list 判断发行版支持"
# 只检查"用 list 做支持性判断"这一模式。
# （注释说明、以及给用户的提示文本里出现该命令名，都是合理的）
n=$(grep -cF 'proot-distro list 2>/dev/null | grep' "$TMOE_LIB/proot.sh" || true)
t_eq "无 list+grep 的支持性判断" "0" "$n"
n3=$(grep -cF 'grep -qw "$distro"' "$TMOE_LIB/proot.sh" || true)
t_eq "无针对发行版的 list 匹配" "0" "$n3"
n2=$(grep -c 'distro_available' "$TMOE_LIB/proot.sh" 2>/dev/null || true)
t_eq "distro_available 已移除" "0" "$n2"

t_suite "枚举已安装容器：扫 rootfs 目录（不依赖 proot-distro 输出）"
W=$(mktemp -d)
export TMOE_ROOTFS_DIR="$W/installed-rootfs"
mkdir -p "$TMOE_ROOTFS_DIR/ubuntu" "$TMOE_ROOTFS_DIR/alpine" "$TMOE_ROOTFS_DIR/debian"
# 这些目录没有真实的 proot-distro 元数据，仍应被列出
out=$(list_proot_installed | sort | tr '\n' ' ')
t_eq "列出全部容器目录" "alpine debian ubuntu " "$out"

mkdir -p "$TMOE_ROOTFS_DIR/fedora"
out=$(list_proot_installed | sort | tr '\n' ' ')
t_eq "新增目录后同步出现" "alpine debian fedora ubuntu " "$out"

t_suite "空 rootfs：不应报错"
rm -rf "$TMOE_ROOTFS_DIR"; mkdir -p "$TMOE_ROOTFS_DIR"
out=$(list_proot_installed 2>&1); rc=$?
t_eq "返回 0（无容器）" "0" "$rc"
t_eq "输出为空" "" "$(printf '%s' "$out" | tr -d '[:space:]')"

t_suite "安装路径：不做预检查（静态确认调用链）"
body=$(awk '/^container_install\(\)/,/^}/' "$TMOE_LIB/proot.sh")
if printf '%s' "$body" | grep -qF 'proot-distro install'; then
    t_ok "container_install 直接调用 proot-distro install"
else
    t_fail "container_install 未直接调用 proot-distro install"
fi
# 同样排除注释行
if printf '%s' "$body" | grep -v '^[[:space:]]*#' | grep -qF 'proot-distro list'; then
    t_fail "container_install 仍用 list 做预检查"
else
    t_ok "container_install 不再用 list 预检查"
fi

rm -rf "$W"
t_report
