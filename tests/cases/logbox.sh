#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# shellcheck source=../lib_helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib_helpers.sh"
export TMOE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export TMOE_LIB="${TMOE_ROOT}/lib"
# shellcheck source=/dev/null
source "${TMOE_ROOT}/tests/loader.sh"
set +e

t_suite "run_with_logbox（哨兵退出码 / 竞态 / 脱敏）"
BASH_BIN="$(command -v bash)"
work=$(mktemp -d)

run_with_logbox t "$work/a.log" "$BASH_BIN" -c 'echo hello; exit 0'
t_eq "成功返回 0" "0" "$?"
t_file_has "归档含输出" "$work/a.log" "hello"
t_file_lacks "归档无哨兵行" "$work/a.log" "__EXIT__"

run_with_logbox t "$work/b.log" "$BASH_BIN" -c 'echo boom >&2; exit 7'; rc=$?
t_eq "失败返回真实退出码 7" "7" "$rc"
t_file_has "归档含 stderr" "$work/b.log" "boom"

# 关键回归：放在 if 条件里（父 shell 因 set -e 提前退出）也必须留下哨兵
if run_with_logbox t "$work/c.log" "$BASH_BIN" -c 'echo x; exit 3'; then
    t_fail "if 分支不应为真"
else
    t_ok "if 条件正确判定失败"
fi
t_file_has "if 调用后日志仍有内容" "$work/c.log" "x"
t_file_lacks "归档已剥离哨兵行" "$work/c.log" "__EXIT__"

run_with_logbox t "$work/d.log" definitely-not-a-command; rc=$?
t_eq "命令不存在返回 127" "127" "$rc"

run_with_logbox t "$work/e.log" "$BASH_BIN" -c 'echo "password=topsecret"; exit 0'
t_file_has "归档已脱敏" "$work/e.log" "password=***"
t_file_lacks "归档无明文" "$work/e.log" "topsecret"

out=$(run_with_logbox t "$work/f.log" "$BASH_BIN" -c 'echo "password=leakme"; exit 0' 2>&1)
t_not_contains "stdout 不泄露明文" "leakme" "$out"
t_file_has "归档仍脱敏" "$work/f.log" "password=***"

before=$(ls -1 "$LOG_DIR" 2>/dev/null | wc -l | tr -d ' ')
run_with_logbox t "" "$BASH_BIN" -c 'echo z; exit 0'; rc=$?
after=$(ls -1 "$LOG_DIR" 2>/dev/null | wc -l | tr -d ' ')
t_eq "空 logfile 返回 0" "0" "$rc"
t_eq "默认归档新增文件" "1" "$([ "$after" -gt "$before" ] && echo 1 || echo 0)"

rm -rf "$work"
t_report
