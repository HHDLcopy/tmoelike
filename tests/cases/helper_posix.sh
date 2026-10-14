#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# 回归：写进容器里、由 #!/bin/sh 执行的助手脚本必须是真 POSIX。
# 背景：Ubuntu/Debian 容器的 /bin/sh 是 dash，Alpine 是 busybox ash，
#       二者都不支持 bash 的 "${@:3}" 参数切片 —— 曾导致
#       `/usr/local/bin/tmoelike-tui: 95: Bad substitution` 后助手直接退出。
# shellcheck source=../lib_helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib_helpers.sh"
export TMOE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
set +e

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# 把每个 heredoc 体单独落盘：hdN.sh，出现个数写进 count
cat > "$work/extract.awk" <<'AWK'
BEGIN { inb = 0; n = 0 }
{
  if (!inb) {
    if (match($0, /<<-?[ \t]*'?[A-Za-z_][A-Za-z0-9_]*'?[ \t]*$/)) {
      tag = $0
      sub(/.*<<-?[ \t]*/, "", tag)
      gsub(/'/, "", tag)
      inb = 1; n++; file = OUT "/hd" n ".sh"
      next
    }
    next
  }
  chk = $0; sub(/^\t+/, "", chk)
  if (chk == tag) { inb = 0; close(file); next }
  print > file
}
END { print n > (OUT "/count") }
AWK

t_suite "容器内助手脚本的 POSIX 兼容性（#!/bin/sh → dash / ash）"

found=0
for libf in "$TMOE_ROOT"/lib/*.sh; do
    [ -f "$libf" ] || continue
    d="$work/$(basename "$libf" .sh)"
    mkdir -p "$d"
    awk -v OUT="$d" -f "$work/extract.awk" "$libf"
    for hd in "$d"/hd*.sh; do
        [ -f "$hd" ] || continue
        # 只检查显式声明用 sh/ash 执行的脚本（bash 助手不受此约束）
        head -1 "$hd" | grep -qE '^#!.*(env[[:space:]]+sh|/sh|/ash)[[:space:]]*$' || continue
        found=$((found + 1))
        label="$(basename "$libf"):$(basename "$hd")"

        # 1) 不得出现 bash 专有参数切片 ${@:N} / ${*:N}
        #    只看可执行行：注释里提到该语法是合法的文档行为，不会触发 Bad substitution
        hit=$(awk '/^[[:space:]]*#/ { next }
                   /\$\{[@*]:[0-9]/ { printf "%d:%s", NR, $0; exit }' "$hd")
        if [ -n "$hit" ]; then
            t_fail "$label 无 \${@:N} 切片" "纯 POSIX" "$hit"
        else
            t_ok "$label 无 \${@:N} 切片"
        fi

        # 2) 真 POSIX 解析器能收下整个脚本
        if command -v dash >/dev/null 2>&1; then
            if dash -n "$hd" 2>"$work/err"; then
                t_ok "$label dash -n 通过"
            else
                t_fail "$label dash -n 通过" "无语法错误" "$(head -1 "$work/err")"
            fi
        elif command -v busybox >/dev/null 2>&1; then
            if busybox ash -n "$hd" 2>"$work/err"; then
                t_ok "$label busybox ash -n 通过"
            else
                t_fail "$label busybox ash -n 通过" "无语法错误" "$(head -1 "$work/err")"
            fi
        else
            t_ok "$label 无非 POSIX 解析器可验（跳过）"
        fi

        # 3) 助手必须真的把主入口挂上，否则登录进去只会看到空 shell
        if grep -qE '^[[:space:]]*main_menu[[:space:]]*$' "$hd"; then
            t_ok "$label 调用了 main_menu"
        else
            t_fail "$label 调用了 main_menu" "存在 main_menu 调用" "未找到"
        fi
    done
done

if [ "$found" -ge 1 ]; then
    t_ok "至少抽到一个 sh 助手脚本（共 $found 个）"
else
    t_fail "至少抽到一个 sh 助手脚本" ">=1" "$found"
fi

t_report
