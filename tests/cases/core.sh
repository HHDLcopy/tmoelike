#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# shellcheck source=../lib_helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib_helpers.sh"
export TMOE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export TMOE_LIB="${TMOE_ROOT}/lib"
# shellcheck source=/dev/null
source "${TMOE_ROOT}/tests/loader.sh"
set +e

t_suite "mirrorize（Alpine 不再双 /alpine）"
t_eq "alpine minirootfs" \
  "https://mirrors.tuna.tsinghua.edu.cn/alpine/v3.20/releases/aarch64/alpine-minirootfs-3.20.0-aarch64.tar.gz" \
  "$(mirrorize 'https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/aarch64/alpine-minirootfs-3.20.0-aarch64.tar.gz')"
t_eq "debian" \
  "https://mirrors.tuna.tsinghua.edu.cn/debian/dists/bookworm/Release" \
  "$(mirrorize 'https://deb.debian.org/debian/dists/bookworm/Release')"
t_eq "github -> ghproxy" \
  "https://mirror.ghproxy.com/github.com/x/y/raw/z.tar" \
  "$(mirrorize 'https://github.com/x/y/raw/z.tar')"
t_eq "未收录主机原样" \
  "https://partner-images.canonical.com/a.tar.gz" \
  "$(mirrorize 'https://partner-images.canonical.com/a.tar.gz')"

t_suite "sanitize（日志脱敏）"
t_eq "password="        "password=***"        "$(echo 'password=abc' | sanitize)"
t_eq "password 引号值"   'password=***'        "$(echo 'password: "a b c"' | sanitize)"
t_eq "token"            "token=***"           "$(echo 'token: zz9' | sanitize)"
t_eq "api_key"          "api_key=***"         "$(echo 'api_key=K-1' | sanitize)"
t_eq "Bearer"           "Authorization: Bearer ***" "$(echo 'Authorization: Bearer eyJ.abc-_9' | sanitize)"
t_eq "ssh 公钥"          "ssh-ed25519 *** u@h"  "$(echo 'ssh-ed25519 AAAAC3Nza u@h' | sanitize)"
t_eq "--password="       "cmd --password=***" "$(echo 'cmd --password=hunter2' | sanitize)"
t_eq "普通行不变"         "installing xfce4"    "$(echo 'installing xfce4' | sanitize)"

t_suite "safe_untar（防路径穿越 / 多格式）"
work=$(mktemp -d)
mkdir -p "$work/src/sub"; echo hello > "$work/src/sub/a.txt"
(mkdir -p "$work/evil"; echo pwned > "$work/evil/f"
 cd "$work/evil" && tar -cf "$work/evil.tar" --transform 's|^f$|../../pwned-by-tar|' f 2>/dev/null || true)
python3 - "$work/evil.tar" <<'PY' 2>/dev/null || true
import sys, io, tarfile
with tarfile.open(sys.argv[1], mode='w') as t:
    d=b'pwned\n'; ti=tarfile.TarInfo('../../pwned-by-tar'); ti.size=len(d); t.addfile(ti, io.BytesIO(d))
PY
mkdir -p "$work/out1"
safe_untar "$work/evil.tar" "$work/out1" 2>/dev/null && rc=0 || rc=$?
t_eq "含 ../ 的包被拒绝" "1" "$rc"
t_eq "未逃逸目标目录" "no" "$([ -e "$work/pwned-by-tar" ] && echo yes || echo no)"

python3 - "$work/abs.tar" <<'PY' 2>/dev/null || true
import sys, io, tarfile
with tarfile.open(sys.argv[1], mode='w') as t:
    d=b'x'; ti=tarfile.TarInfo('/tmp/tmoelike-abs-escape'); ti.size=len(d); t.addfile(ti, io.BytesIO(d))
PY
mkdir -p "$work/out2"
safe_untar "$work/abs.tar" "$work/out2" 2>/dev/null && rc=0 || rc=$?
t_eq "绝对路径包被拒绝" "1" "$rc"

mkdir -p "$work/out3"; (cd "$work/src" && tar -cf "$work/plain.tar" .)
safe_untar "$work/plain.tar" "$work/out3" && rc=0 || rc=$?
t_eq "纯 tar 正常解压" "0" "$rc"
t_eq "内容落地" "hello" "$(cat "$work/out3/sub/a.txt" 2>/dev/null)"

t_suite "config_get / config_set"
config_set test_key test_value >/dev/null 2>&1
t_eq "写入后可读" "test_value" "$(config_get test_key '')"
t_eq "缺省值生效" "fallback" "$(config_get no_such_key fallback)"

t_suite "with_rollback（失败回滚 / 成功不回滚）"
wr_flag="$work/wr-flag"
wr_rb() { rm -rf "$1"; touch "$wr_flag"; }
mkdir -p "$work/halfmade"
with_rollback wr_rb "$work/halfmade" false >/dev/null 2>&1 && r=$? || r=$?
t_eq "失败返回 1" "1" "$r"
t_eq "回滚已执行" "yes" "$([ -f "$wr_flag" ] && echo yes || echo no)"
t_eq "半成品被清理" "no" "$([ -e "$work/halfmade" ] && echo yes || echo no)"
rm -f "$wr_flag"; mkdir -p "$work/okmade"
with_rollback wr_rb "$work/okmade" true >/dev/null 2>&1 && r=$? || r=$?
t_eq "成功返回 0" "0" "$r"
t_eq "成功时不回滚" "no" "$([ -f "$wr_flag" ] && echo yes || echo no)"

rm -rf "$work"
t_report
