#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# tmoelike 测试入口：逐个运行 tests/cases/*.sh
#   ./tests/run.sh              跑全部
#   ./tests/run.sh compress     只跑名字含 compress 的用例
# shellcheck disable=SC2034
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export TMOE_ROOT="$(cd "${TESTS_DIR}/.." && pwd -P)"
export TMOE_LIB="${TMOE_ROOT}/lib"

filter="${1:-}"
total_pass=0
total_fail=0
failed_cases=()

# 夹具（jq / proot / proot-distro 桩）需要可执行位；
# /sdcard 之类的 fuse 挂载无法 chmod，因此复制到可执行位置后再注入 PATH。
TMOE_FIXTURES="$(mktemp -d)"
# 隔离测试用的 rootfs 与 chroot 挂载记录：避免污染真实环境，
# 也避免在无权限路径（如 Linux 的 /var）创建目录而失败。
TMOE_ROOTFS_DIR="$(mktemp -d)"
TMOE_MOUNTS_FILE="$(mktemp)"
export TMOE_ROOTFS_DIR TMOE_MOUNTS_FILE
trap 'rm -rf "$TMOE_FIXTURES" "$TMOE_ROOTFS_DIR"; rm -f "$TMOE_MOUNTS_FILE"' EXIT
if [ -d "${TESTS_DIR}/fixtures" ]; then
    cp -f "${TESTS_DIR}/fixtures/"* "$TMOE_FIXTURES/" 2>/dev/null || true
    chmod 755 "$TMOE_FIXTURES"/* 2>/dev/null || true
    # 修正 shebang 为当前环境的解释器路径
    for f in "$TMOE_FIXTURES"/*; do
        [ -f "$f" ] || continue
        case "$(head -1 "$f")" in
            '#!'*python*) sed -i "1s|.*|#!$(command -v python3 || echo /usr/bin/python3)|" "$f" ;;
            '#!'*bash*)   sed -i "1s|.*|#!$(command -v bash || echo /bin/bash)|" "$f" ;;
        esac
    done
    export PATH="${TMOE_FIXTURES}:${PATH}"
fi

# 让用例内的 loader 也能找到夹具
export TMOE_FIXTURES

for case_file in "${TESTS_DIR}"/cases/*.sh; do
    [ -f "$case_file" ] || continue
    name="$(basename "$case_file" .sh)"
    if [ -n "$filter" ] && [[ "$name" != *"$filter"* ]]; then
        continue
    fi
    printf '\n########## %s ##########\n' "$name"
    out=$(bash "$case_file" 2>&1)
    rc=$?
    printf '%s\n' "$out"
    p=$(printf '%s' "$out" | sed -n 's/^结果：pass=\([0-9]*\).*/\1/p' | tail -1)
    f=$(printf '%s' "$out" | sed -n 's/.*fail=\([0-9]*\).*/\1/p' | tail -1)
    total_pass=$((total_pass + ${p:-0}))
    total_fail=$((total_fail + ${f:-0}))
    [ "$rc" -eq 0 ] || failed_cases+=("$name")
done

printf '\n========================================\n'
printf '总计：pass=%d fail=%d\n' "$total_pass" "$total_fail"
if [ ${#failed_cases[@]} -gt 0 ]; then
    printf '失败用例：%s\n' "${failed_cases[*]}"
    exit 1
fi
[ "$total_fail" -eq 0 ]
