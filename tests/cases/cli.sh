#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# 端到端 CLI 测试（夹具 jq/proot/proot-distro + 假 rootfs）
export TMOE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
S="${TMOE_ROOT}/tmoelike.sh"

# 夹具 PATH：优先 run.sh 准备的可执行副本
if [ -n "${TMOE_FIXTURES:-}" ] && [ -d "${TMOE_FIXTURES}" ]; then
    PATH="${TMOE_FIXTURES}:${PATH}"
fi
for _d in "${TMOE_ROOT}/.patch/bin" "${HOME}/.tmoelike-testbin"; do
    [ -f "${_d}/jq" ] || continue
    case ":${PATH}:" in *":${_d}:"*) ;; *) PATH="${_d}:${PATH}" ;; esac
done
export PATH
ROOTFS="${PREFIX}/var/lib/proot-distro/installed-rootfs"
export TMOE_TEST_REGISTRY="${HOME}/.tmoelike/config/containers.json"

pass=0; fail=0
t() { if [ "$2" = "$3" ]; then printf '  ok   %-48s %s\n' "$1" "$3"; pass=$((pass+1));
      else printf '  FAIL %-48s expected=%s actual=%s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
has() { if printf '%s' "$3" | grep -q -- "$2"; then printf '  ok   %-48s\n' "$1"; pass=$((pass+1));
        else printf '  FAIL %-48s (未见: %s)\n' "$1" "$2"; fail=$((fail+1)); fi; }

cleanup() { rm -rf "$ROOTFS/demo" "$ROOTFS/imported" "$ROOTFS/restored" "$ROOTFS/cloned" \
    "$ROOTFS/renamed" "$ROOTFS/evilctr" "$HOME/.tmoelike/backups/demo-"* 2>/dev/null; }
mkdir -p "$ROOTFS"; cleanup

echo "== A. 帮助 / 状态 =="
out=$(bash "$S" --help 2>&1); t "--help rc" "0" "$?"
has "帮助含版本号" "TMOE-LIKE v2.2.0" "$out"
has "帮助含 rollback 子命令" "rollback" "$out"
has "帮助含 status 子命令" "status" "$out"
has "帮助含 backup 子命令" "backup <name>" "$out"

st=$(bash "$S" status 2>&1)
has "status 版本" "TMOE-LIKE v2.2.0" "$st"
has "status 架构 arm64" "架构：arm64" "$st"
has "status 表头" "NAME" "$st"

echo "== B. 错误处理 =="
bash "$S" bogus >/dev/null 2>&1;        t "未知子命令 rc=2" "2" "$?"
bash "$S" install >/dev/null 2>&1;      t "install 缺参 rc=2" "2" "$?"
bash "$S" import onlyone >/dev/null 2>&1; t "import 缺参 rc=2" "2" "$?"
bash "$S" clone one >/dev/null 2>&1;    t "clone 缺参 rc=2" "2" "$?"
bash "$S" export nosuch >/dev/null 2>&1;   t "export 不存在 rc=1" "1" "$?"
bash "$S" backup nosuch >/dev/null 2>&1;   t "backup 不存在 rc=1" "1" "$?"
bash "$S" restore /nope nm >/dev/null 2>&1; t "restore 无备份 rc=1" "1" "$?"
bash "$S" rename nosuch new >/dev/null 2>&1; t "rename 不存在 rc=1" "1" "$?"

echo "== C. 容器生命周期往返 =="
mkdir -p "$ROOTFS/demo/bin"
echo "I am a fake rootfs" > "$ROOTFS/demo/marker"
echo "bin" > "$ROOTFS/demo/bin/sh"

WORK=$(mktemp -d)
bash "$S" export demo "$WORK/demo.tar.zst" >/dev/null 2>&1; t "export rc" "0" "$?"
t "export 产物非空" "yes" "$([ -s "$WORK/demo.tar.zst" ] && echo yes || echo no)"

out=$(bash "$S" import "$WORK/demo.tar.zst" imported 2>&1); t "import rc" "0" "$?"
t "import 内容落地" "I am a fake rootfs" "$(cat "$ROOTFS/imported/marker" 2>/dev/null)"
has "import 输出提示" "已导入：imported" "$out"

out=$(bash "$S" backup imported 2>&1); t "backup rc" "0" "$?"
BDIR=$(printf '%s\n' "$out" | tail -1)
t "backup 目录存在" "yes" "$([ -d "$BDIR" ] && echo yes || echo no)"
t "backup 含 rootfs.tar.zst" "yes" "$([ -s "$BDIR/rootfs.tar.zst" ] && echo yes || echo no)"
t "backup 含 meta.json" "yes" "$([ -f "$BDIR/meta.json" ] && echo yes || echo no)"
t "backup 含 version" "yes" "$([ -f "$BDIR/version" ] && echo yes || echo no)"

out=$(bash "$S" restore "$BDIR" restored 2>&1); t "restore rc" "0" "$?"
t "restore 内容一致" "I am a fake rootfs" "$(cat "$ROOTFS/restored/marker" 2>/dev/null)"
has "restore 输出提示" "已恢复：restored" "$out"

out=$(bash "$S" clone restored cloned 2>&1); t "clone rc" "0" "$?"
t "clone 内容一致" "I am a fake rootfs" "$(cat "$ROOTFS/cloned/marker" 2>/dev/null)"

out=$(bash "$S" rename cloned renamed 2>&1); t "rename rc" "0" "$?"
t "rename 旧名消失" "no" "$([ -e "$ROOTFS/cloned" ] && echo yes || echo no)"
t "rename 新名存在" "yes" "$([ -d "$ROOTFS/renamed" ] && echo yes || echo no)"

echo "== D. list / 注册表一致性 =="
ls=$(bash "$S" list 2>&1)
has "list 含 imported" "imported" "$ls"
has "list 含 restored" "restored" "$ls"
has "list 含 renamed" "renamed" "$ls"
t "rename 后注册表无旧名(键)" "0" "$(grep -cE '^[[:space:]]*"cloned"[[:space:]]*:' "$TMOE_TEST_REGISTRY" 2>/dev/null || true)"
t "rename 后注册表有新名(键)" "1" "$(grep -cE '^[[:space:]]*"renamed"[[:space:]]*:' "$TMOE_TEST_REGISTRY" 2>/dev/null || true)"

echo "== E. CLI 拒绝恶意包 =="
python3 - "$WORK/evil.tar" <<'PY'
import sys, io, tarfile
with tarfile.open(sys.argv[1], mode='w') as t:
    data = b'pwned\n'
    ti = tarfile.TarInfo('../../cli-pwned'); ti.size = len(data)
    t.addfile(ti, io.BytesIO(data))
PY
bash "$S" import "$WORK/evil.tar" evilctr >/dev/null 2>&1; t "import 恶意包 rc=1" "1" "$?"
t "恶意包未逃逸" "no" "$([ -e "$ROOTFS/../cli-pwned" ] || [ -e "$ROOTFS/cli-pwned" ] && echo yes || echo no)"
t "未建立容器目录" "no" "$([ -d "$ROOTFS/evilctr" ] && echo yes || echo no)"

echo "== F. 损坏备份被拒 =="
BAD="$HOME/.tmoelike/backups/bad-20250101-000000"
mkdir -p "$BAD"; head -c 30 "$BDIR/rootfs.tar.zst" > "$BAD/rootfs.tar.zst"
bash "$S" restore "$BAD" badrestore >/dev/null 2>&1; t "损坏备份 restore rc=1" "1" "$?"

rm -rf "$WORK" "$BAD"
cleanup
echo
echo "结果：pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
