#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# 用例：启动依赖（jq / python3）缺失时的**自动安装**行为
#
# 需求：缺 jq 或 python3 时自动下载安装（Termux 下有 pkg）；
#       安装失败或没有 pkg 时，给出手动安装指引并中止。
#
# 手法：用「退出 127 的包装脚本」遮蔽命令伪造"缺依赖"；
#       用假 pkg 记录调用并（可选）真正装上夹具 jq。
#       注意 jq 夹具本身是 python3 脚本，所以"只缺 jq"场景需保留 python3 可用。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib_helpers.sh"

# 该用例依赖"遮蔽目录排在真实目录之前"来伪造缺依赖；某些发行版把 jq 与 bash
# 装在同一目录（如 Ubuntu 的 /usr/bin），那种布局下无法构造，允许运行器跳过。
if [ "${TMOE_SKIP_DEPS_PROMPT:-0}" = "1" ]; then
    echo "跳过：运行器指定 TMOE_SKIP_DEPS_PROMPT=1（jq 与 bash 同目录的布局无法伪造缺依赖）"
    t_report
    exit 0
fi

export TMOE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
BASHBIN="$(command -v bash)"
PYBIN="$(command -v python3)"
[ -n "$PYBIN" ] || { echo "跳过：无 python3"; t_report; exit 0; }

WORK=$(mktemp -d)
HOME_T="$WORK/home"; RUN="$WORK/run"
BIN="$WORK/bin"              # 假 pkg 与"已安装"的命令
HIDE_JQ="$WORK/hide_jq"      # 只遮蔽 jq
HIDE_BOTH="$WORK/hide_both"  # 遮蔽 jq 与 python3
mkdir -p "$HOME_T" "$RUN/lib" "$BIN" "$HIDE_JQ" "$HIDE_BOTH"
cp "$TMOE_ROOT/tmoelike.sh" "$RUN/"
cp "$TMOE_ROOT/lib/"*.sh "$TMOE_ROOT/lib/manifest.json" "$RUN/lib/" 2>/dev/null || true

printf '#!/bin/sh\nexit 127\n' > "$HIDE_JQ/jq"; chmod +x "$HIDE_JQ/jq"
for n in jq python3; do
    printf '#!/bin/sh\nexit 127\n' > "$HIDE_BOTH/$n"; chmod +x "$HIDE_BOTH/$n"
done

FIX_SRC="${TMOE_FIXTURES:-$TMOE_ROOT/tests/fixtures}/jq"
[ -f "$FIX_SRC" ] || { echo "跳过：找不到 jq 夹具"; t_report; exit 0; }

# 假 pkg：记录调用；含 python 时提供 python3，含 jq 时装夹具 jq
cat > "$BIN/pkg" <<EOS
#!/bin/sh
echo "pkg \$*" >> "$WORK/pkg.log"
case "\$*" in
  *python*) printf '#!/bin/sh\nexec %s "$@"\n' "$PYBIN" > "$BIN/python3"; chmod +x "$BIN/python3" ;;
esac
case "\$*" in
  *jq*)
    cp "$FIX_SRC" "$BIN/jq"
    sed -i '1s|.*|#!$PYBIN|' "$BIN/jq"
    chmod +x "$BIN/jq"
    ;;
esac
exit 0
EOS
chmod +x "$BIN/pkg"

# 会失败的假 pkg（验证"安装失败给指引"）
FAIL_BIN="$WORK/failbin"
mkdir -p "$FAIL_BIN"
printf '#!/bin/sh\necho "pkg: 模拟安装失败" >&2\nexit 1\n' > "$FAIL_BIN/pkg"
chmod +x "$FAIL_BIN/pkg"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

REAL_DIR="$(dirname "$BASHBIN")"
PATH_A="$BIN:$REAL_DIR:$HIDE_JQ:/system/bin"           # 缺 jq、python3 可用
PATH_B="$BIN:$HIDE_BOTH:$REAL_DIR:/system/bin"         # jq 与 python3 都缺
PATH_FAIL="$FAIL_BIN:$HIDE_BOTH:$REAL_DIR:/system/bin"  # 都缺且 pkg 安装失败

run_with() {
    local p="$1"; shift
    local envs=() args=() seen=0 a
    for a in "$@"; do
        if [ "$a" = "--" ]; then seen=1; continue; fi
        if [ "$seen" = "0" ]; then envs+=("$a"); else args+=("$a"); fi
    done
    env HOME="$HOME_T" "${envs[@]}" TMOE_LIB="$RUN/lib" PATH="$p" \
        "$BASHBIN" "$RUN/tmoelike.sh" ${args[@]+"${args[@]}"} 2>&1
}

t_suite "遮蔽环境自检"
PATH="$PATH_A" jq --version >/dev/null 2>&1; rc_jq=$?
PATH="$PATH_A" python3 -c pass >/dev/null 2>&1; rc_py=$?
PATH="$PATH_B" python3 -c pass >/dev/null 2>&1; rc_py2=$?
t_eq "场景A：jq 不可用" "1" "$([ "$rc_jq" -ne 0 ] && echo 1 || echo 0)"
t_eq "场景A：python3 可用" "0" "$rc_py"
t_eq "场景B：python3 也不可用" "1" "$([ "$rc_py2" -ne 0 ] && echo 1 || echo 0)"

t_suite "A. 缺 jq → 自动执行 pkg install（不再询问）"
rm -f "$WORK/pkg.log" "$BIN/jq"
out=$(run_with "$PATH_A" -- --help); rc=$?
t_contains "提示将自动安装" "自动安装" "$out"
t_not_contains "不再出现询问式提问" "是否现在执行" "$out"
if [ -f "$WORK/pkg.log" ] && grep -q '^pkg install -y ' "$WORK/pkg.log"; then
    t_ok "自动调用了 pkg install -y"
else
    t_fail "未自动调用 pkg install" "$(cat "$WORK/pkg.log" 2>/dev/null || echo 无日志)"
fi
t_contains "装好后继续运行" "TMOE-LIKE v" "$out"

t_suite "B. jq 与 python3 都缺 → 自动安装后继续"
rm -f "$WORK/pkg.log" "$BIN/jq" "$BIN/python3"
out=$(run_with "$PATH_B" -- --help); rc=$?
t_eq "退出码 0" "0" "$rc"
t_contains "输出主流程内容" "TMOE-LIKE v" "$out"

t_suite "C. 自动安装失败 → 给出手动安装指引并中止"
out=$(run_with "$PATH_FAIL" -- --help); rc=$?
t_eq "退出码 1" "1" "$rc"
t_contains "提示 Termux 装法" "pkg install" "$out"
t_contains "提示 Debian/Ubuntu 装法" "apt install" "$out"
t_contains "提示 Alpine 装法" "apk add" "$out"

t_report
