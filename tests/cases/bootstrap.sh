#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# 用例：单文件引导下载器（测速选源 / SHA256 校验 / 缓存 / 离线 / 指纹）
# 说明：为控制耗时，按需启停本地模拟源，并统一使用短探测超时。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib_helpers.sh"

export TMOE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# 关键：清掉从外部继承的引导相关变量，避免用例被跑测者的环境干扰
# （否则 TMOE_LIB 会让入口走"本地 lib"分支，绕过下载逻辑）
unset TMOE_LIB TMOE_REFRESH_LIB TMOE_NO_FETCH TMOE_SOURCES \
      TMOE_MANIFEST_SHA256 TMOE_PROBE_TIMEOUT TMOE_BASE
BASHBIN="$(command -v bash)"
PYBIN="$(command -v python3)"
[ -n "$PYBIN" ] || { echo "跳过：无 python3（本用例需要本地 HTTP 源）"; t_report; exit 0; }

# 夹具（jq / proot / proot-distro 桩）：CLI 子命令需要 jq 与 proot
FIX=""
for d in "${TMOE_FIXTURES:-}" "${TMOE_ROOT}/tests/fixtures" "$HOME/.tmoelike-testbin"; do
    [ -n "$d" ] && [ -f "$d/jq" ] && { FIX="$d"; break; }
done
if [ -n "$FIX" ]; then
    PATH="${FIX}:$(dirname "$BASHBIN"):$PATH"
    export PATH
else
    echo "跳过：找不到测试夹具（jq 桩），CLI 模式无法验证"
    t_report
    exit 0
fi

WORK=$(mktemp -d)
HOME_T="$WORK/home"; RUN="$WORK/run"
SRC="$WORK/src"
mkdir -p "$HOME_T" "$RUN" "$SRC/lib"
cp "$TMOE_ROOT/tmoelike.sh" "$RUN/"
cp "$TMOE_ROOT/lib/"*.sh "$TMOE_ROOT/lib/manifest.json" "$SRC/lib/"

PORT=$("$PYBIN" - <<'PY'
import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()
PY
)
PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; rm -rf "$WORK"; }
trap cleanup EXIT

start_src() {
    "$PYBIN" - "$SRC" "$PORT" <<'PY' &
import http.server, socketserver, sys
root, port = sys.argv[1], int(sys.argv[2])
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=root, **k)
    def log_message(self, *a): pass
class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True; daemon_threads = True
S(("127.0.0.1", port), H).serve_forever()
PY
    PIDS+=($!)
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
                "http://127.0.0.1:$PORT/lib/manifest.json" || true)" = "200" ]; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}
stop_src() { local p; for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; PIDS=(); sleep 0.2; }

run_entry() {
    local envs=() args=() seen=0 a
    for a in "$@"; do
        if [ "$a" = "--" ]; then seen=1; continue; fi
        if [ "$seen" = "0" ]; then envs+=("$a"); else args+=("$a"); fi
    done
    env HOME="$HOME_T" TMOE_PROBE_TIMEOUT=3 "${envs[@]}" \
        timeout 60 "$BASHBIN" "$RUN/tmoelike.sh" "${args[@]}" 2>&1
}

SRC_URL="http://127.0.0.1:$PORT"

t_suite "单文件引导：首次运行自动下载"
if start_src; then t_ok "本地模拟源就绪"; else t_fail "本地源未就绪"; t_report; exit 1; fi
out=$(run_entry TMOE_SOURCES="only|$SRC_URL" -- --help); rc=$?
t_eq "退出码 0" "0" "$rc"
t_contains "完成源探测" "已选源：only" "$out"
t_contains "加载后可打印帮助" "TMOE-LIKE v" "$out"
t_eq "缓存模块数 = 19" "19" "$(ls -1 "$HOME_T/.tmoelike/cache/lib"/*.sh 2>/dev/null | wc -l | tr -d ' ')"
t_eq "清单已缓存" "1" "$([ -f "$HOME_T/.tmoelike/cache/manifest.json" ] && echo 1 || echo 0)"
t_eq "清单指纹已记录" "1" "$([ -s "$HOME_T/.tmoelike/cache/manifest.sha256" ] && echo 1 || echo 0)"

t_suite "缓存命中：源关闭后仍可离线启动"
stop_src
out=$(run_entry TMOE_SOURCES="only|$SRC_URL" -- --help); rc=$?
t_eq "退出码 0（源已关闭）" "0" "$rc"
t_not_contains "未再次联网探测" "探测下载源" "$out"

t_suite "离线模式：缓存不完整时明确报错"
mv "$HOME_T/.tmoelike/cache/lib/cli.sh" "$HOME_T/.tmoelike/cache/lib/cli.sh.bak"
out=$(run_entry TMOE_NO_FETCH=1 -- status); rc=$?
t_eq "退出码 1" "1" "$rc"
t_contains "提示离线原因" "TMOE_NO_FETCH" "$out"
mv "$HOME_T/.tmoelike/cache/lib/cli.sh.bak" "$HOME_T/.tmoelike/cache/lib/cli.sh"

t_suite "篡改防护：模块被改动则拒绝，且不污染缓存"
start_src >/dev/null 2>&1
cp "$SRC/lib/common.sh" "$SRC/lib/common.sh.bak"
printf '\n# 恶意注入\n' >> "$SRC/lib/common.sh"
rm -rf "$HOME_T/.tmoelike/cache"
out=$(run_entry TMOE_SOURCES="only|$SRC_URL" TMOE_REFRESH_LIB=1 -- status); rc=$?
t_eq "退出码非 0" "1" "$rc"
t_contains "报告 SHA256 校验失败" "校验失败" "$out"
t_eq "未写入缓存（原子性）" "0" "$([ -d "$HOME_T/.tmoelike/cache/lib" ] && echo 1 || echo 0)"
mv "$SRC/lib/common.sh.bak" "$SRC/lib/common.sh"

t_suite "清单指纹固定（TMOE_MANIFEST_SHA256）"
out=$(run_entry TMOE_SOURCES="only|$SRC_URL" \
      TMOE_MANIFEST_SHA256=0000000000000000000000000000000000000000000000000000000000000000 \
      -- status); rc=$?
t_eq "指纹不符 → 退出码 1" "1" "$rc"
t_contains "提示指纹问题" "指纹" "$out"

t_suite "全源不可达：给出离线替代指引"
out=$(run_entry TMOE_SOURCES="dead|http://127.0.0.1:9" TMOE_REFRESH_LIB=1 -- status); rc=$?
t_eq "退出码 1" "1" "$rc"
t_contains "提示可手动指定 TMOE_LIB" "TMOE_LIB" "$out"

t_suite "--refresh-lib 强制重新下载"
out=$(run_entry TMOE_SOURCES="only|$SRC_URL" -- --refresh-lib --help); rc=$?
t_eq "退出码 0" "0" "$rc"
t_contains "重新探测源" "已选源" "$out"

t_report
