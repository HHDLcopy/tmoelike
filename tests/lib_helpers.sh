#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# tmoelike 测试公共断言库（纯 bash，不依赖 bats）
# 用法：source tests/lib_helpers.sh

T_PASS=0
T_FAIL=0
T_CURRENT=""

t_suite() {
    T_CURRENT="$1"
    printf '\n== %s ==\n' "$1"
}

t_ok() {
    T_PASS=$((T_PASS+1))
    printf '  ok   %s\n' "$1"
}

t_fail() {
    T_FAIL=$((T_FAIL+1))
    printf '  FAIL %s\n' "$1"
    [ -n "${2:-}" ] && printf '       期望=[%s] 实际=[%s]\n' "$2" "$3"
}

# t_eq <描述> <期望> <实际>
t_eq() {
    if [ "$2" = "$3" ]; then t_ok "$1"; else t_fail "$1" "$2" "$3"; fi
}

# t_ne <描述> <不应等于> <实际>
t_ne() {
    if [ "$2" != "$3" ]; then t_ok "$1"; else t_fail "$1" "≠$2" "$3"; fi
}

# t_rc <描述> <期望退出码> <命令...>
t_rc() {
    local desc="$1" want="$2"; shift 2
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    t_eq "$desc" "$want" "$rc"
}

# t_contains <描述> <子串> <文本>
t_contains() {
    if printf '%s' "$3" | grep -qF -- "$2"; then t_ok "$1"; else t_fail "$1" "含 $2" "$3"; fi
}

# t_not_contains <描述> <子串> <文本>
t_not_contains() {
    if printf '%s' "$3" | grep -qF -- "$2"; then t_fail "$1" "不含 $2" "$3"; else t_ok "$1"; fi
}

# t_file_has <描述> <文件> <子串>
t_file_has() {
    if grep -qF -- "$3" "$2" 2>/dev/null; then t_ok "$1"; else t_fail "$1" "$2 含 $3" "未命中"; fi
}

# t_file_lacks <描述> <文件> <子串>
t_file_lacks() {
    if grep -qF -- "$3" "$2" 2>/dev/null; then t_fail "$1" "$2 不含 $3" "命中"; else t_ok "$1"; fi
}

t_report() {
    printf '\n结果：pass=%d fail=%d\n' "$T_PASS" "$T_FAIL"
    [ "$T_FAIL" -eq 0 ]
}
