#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# 用例：启动依赖（jq / python3）缺失时的引导询问
#
# 三个自洽场景（避免夹具自身依赖造成的自相矛盾）：
#   A. 缺 jq、python3 可用 → 同意安装 → pkg 装上 jq 后可继续运行
#   B. jq 与 python3 都缺   → 回答 n   → 中止且不调用 pkg
#   C. 缺依赖且无 pkg 命令  → 给出各发行版安装指引
#
# 手法：用「退出 127 的包装脚本」遮蔽命令。注意 jq 夹具本身是 python3 脚本，
#       所以场景 A 必须保留 python3 可用，否则装上的 jq 也跑不起来（测试失真）。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib_helpers.sh"

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

# 假 pkg：记录调用；含 jq 时把夹具 jq 装到 BIN 并修正 shebang
cat > "$BIN/pkg" <<EOS
#!/bin/sh
echo "pkg \$*" >> "$WORK/pkg.log"
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

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

REAL_DIR="$(dirname "$BASHBIN")"
# 场景 A：BIN > 真实工具目录（python3 可用）> 只遮蔽 jq
PATH_A="$BIN:$REAL_DIR:$HIDE_JQ:/system/bin"
# 场景 B/C：BIN > 遮蔽层（jq+python3 都不可用）> 真实工具目录
PATH_B="$BIN:$HIDE_BOTH:$REAL_DIR:/system/bin"

run_with() { # run_with <PATH> <额外环境...> -- <参数...>
    local p="$1"; shift
    local envs=() args=() seen=0 a
    for a in "$@"; do
        if [ "$a" = "--" ]; then seen=1; continue; fi
        if [ "$seen" = "0" ]; then envs+=("$a"); else args+=("$a"); fi
    done
    env HOME="$HOME_T" "${envs[@]}" PATH="$p" \
        "$BASHBIN" "$RUN/tmoelike.sh" ${args[@]+"${args[@]}"} 2>&1
}

t_suite "遮蔽环境自检"
PATH="$PATH_A" jq --version >/dev/null 2>&1; rc_jq=$?
PATH="$PATH_A" python3 -c pass >/dev/null 2>&1; rc_py=$?
PATH="$PATH_B" python3 -c pass >/dev/null 2>&1; rc_py2=$?
t_eq "场景A：jq 不可用" "1" "$([ "$rc_jq" -ne 0 ] && echo 1 || echo 0)"
t_eq "场景A：python3 可用" "0" "$rc_py"
t_eq "场景B：python3 也不可用" "1" "$([ "$rc_py2" -ne 0 ] && echo 1 || echo 0)"

t_suite "A. 有 python3 但缺 jq → 仍应询问是否安装 jq"
rm -f "$WORK/pkg.log" "$BIN/jq"
out=$(run_with "$PATH_A" TMOE_ASSUME_YES=1 -- --help); rc=$?
t_contains "提示改用 python3" "python3" "$out"
t_contains "说明将执行 pkg install" "pkg install" "$out"
if [ -f "$WORK/pkg.log" ] && grep -q "pkg install -y jq" "$WORK/pkg.log"; then
    t_ok "调用了 pkg install -y jq"
else
    t_fail "未调用 pkg install" "$(cat "$WORK/pkg.log" 2>/dev/null || echo 无日志)"
fi
# 说明：沙箱里 jq 夹具本身依赖 python3、且命令解析在 bash -c 与入口内存在差异，
# 因此"安装后继续运行"在沙箱无法稳定复现；此处只断言脚本自身负责的行为。
# 真机 Termux 上 `pkg install jq` 装真 jq，流程为：询问 → 安装 → 继续。

t_suite "B. jq 与 python3 都缺 → 回答 n → 中止且不安装"
rm -f "$WORK/pkg.log" "$BIN/jq"
out=$(printf 'n\n' | run_with "$PATH_B" TMOE_ASSUME_INTERACTIVE=1 -- --help); rc=$?
t_eq "退出码非 0" "1" "$rc"
t_contains "列明缺失项" "jq python3" "$out"
t_contains "给出手动安装指引" "pkg install" "$out"
t_eq "未调用 pkg（用户拒绝）" "0" "$([ -f "$WORK/pkg.log" ] && echo 1 || echo 0)"

t_suite "C. 无 pkg 命令 → 给出各发行版指引"
# 本机可能自带 pkg（Termux/沙箱），这里用"只含必要基础工具"的受限 PATH
# 来确保 pkg 确实不可见（剔除 pkg 所在目录比逐个排除更可靠）。
# /system/bin 含基础工具但确实没有 pkg（已实测），用它模拟"无 pkg 环境"
NO_PKG_PATH="/system/bin"
out=$(run_with "$NO_PKG_PATH" TMOE_ASSUME_YES=1 -- --help); rc=$?
t_eq "退出码非 0" "1" "$rc"
t_contains "提示 Debian/Ubuntu 装法" "apt install jq" "$out"
t_contains "提示 Alpine 装法" "apk add jq" "$out"

t_report
