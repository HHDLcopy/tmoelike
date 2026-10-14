#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# shellcheck source=../lib_helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib_helpers.sh"
export TMOE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export TMOE_LIB="${TMOE_ROOT}/lib"
# shellcheck source=/dev/null
source "${TMOE_ROOT}/tests/loader.sh"
set +e

t_suite "压缩兼容层"
work=$(mktemp -d)
mkdir -p "$work/src/sub"; echo payload > "$work/src/sub/f"

if tar_can_exec_compressor; then
    t_ok "tar 可直接调用压缩器（原生路径）"
else
    t_ok "tar 无法调用压缩器 -> 走两段式回退"
fi

zstd_create "$work/src" "$work/a.tar.zst" 3; t_eq "zstd_create rc" "0" "$?"
t_eq "zstd_test 通过" "0" "$(zstd_test "$work/a.tar.zst"; echo $?)"
mkdir -p "$work/outz"; zstd_extract "$work/a.tar.zst" "$work/outz"; t_eq "zstd_extract rc" "0" "$?"
t_eq "zstd 往返内容一致" "payload" "$(cat "$work/outz/sub/f")"

tar_create_stream xz '-T0 -2' "$work/src" "$work/a.tar.xz"; t_eq "xz 打包 rc" "0" "$?"
xz -t "$work/a.tar.xz" 2>/dev/null; t_eq "xz 产物完整" "0" "$?"
mkdir -p "$work/outx"; safe_untar "$work/a.tar.xz" "$work/outx"; t_eq "xz 可安全解回" "0" "$?"

tar_create_stream gzip '-1' "$work/src" "$work/a.tar.gz"; t_eq "gzip 打包 rc" "0" "$?"
mkdir -p "$work/outg"; safe_untar "$work/a.tar.gz" "$work/outg"; t_eq "gzip 可安全解回" "0" "$?"

zstd_create "$work/src" "$work/probe.zst" 1
t_eq "魔数识别 zstd" "zstd" "$(detect_compress_cmd "$work/probe.zst")"
t_eq "魔数识别 xz"   "xz"   "$(detect_compress_cmd "$work/a.tar.xz")"
t_eq "魔数识别 gzip" "gzip" "$(detect_compress_cmd "$work/a.tar.gz")"
t_eq "魔数识别 纯tar" ""    "$(detect_compress_cmd "$work/plain.tar")" 

# 拒绝穿越的压缩包（用外部 zstd 生成；缺失则跳过，避免把环境问题当失败）
if command -v zstd >/dev/null 2>&1; then
    python3 - "$work/evil.tar.zst" <<'PY'
import sys, io, tarfile, os
raw = sys.argv[1] + '.raw'
with tarfile.open(raw, mode='w') as t:
    d = b'pwned\n'
    ti = tarfile.TarInfo('../../zst-escape')
    ti.size = len(d)
    t.addfile(ti, io.BytesIO(d))
PY
    RAW="$work/evil.tar.zst.raw"
    if [ -f "$RAW" ]; then
        zstd -q -f -o "$work/evil.tar.zst" "$RAW" && rm -f "$RAW"
    fi
    if [ -s "$work/evil.tar.zst" ]; then
        mkdir -p "$work/oute"
        zstd_extract "$work/evil.tar.zst" "$work/oute" 2>/dev/null && rc=0 || rc=$?
        # tar 退出码随构建为 1 或 2，safe_untar 已归一；这里只要求「非 0」
        t_eq "zstd 穿越包被拒绝（非 0）" "1" "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
        t_eq "未逃逸" "no" "$([ -e "$work/zst-escape" ] && echo yes || echo no)"
    else
        t_ok "跳过 zstd 穿越包（本环境无法生成 zstd 夹具）"
    fi
else
    t_ok "跳过 zstd 穿越包（无 zstd 命令）"
fi

rm -rf "$work"
t_report
