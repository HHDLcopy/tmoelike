#!/usr/bin/env bash
# ⚠️ AI 生成代码（AI-Generated）—— 测试同样由 AI 编写，用于自我验证。
# shellcheck source=../lib_helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib_helpers.sh"
export TMOE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export TMOE_LIB="${TMOE_ROOT}/lib"
# shellcheck source=/dev/null
source "${TMOE_ROOT}/tests/loader.sh"
set +e

t_suite "verify_backup（完整性校验）"
work=$(mktemp -d)
mkdir -p "$work/src/sub"; echo hello > "$work/src/sub/a.txt"
tb="$work/bk"; mkdir -p "$tb"
zstd_create "$work/src" "$tb/rootfs.tar.zst" 3
echo '{"type":"proot"}' > "$tb/meta.json"
verify_backup "$tb" && rc=0 || rc=$?
t_eq "完好备份通过" "0" "$rc"

cp "$tb/rootfs.tar.zst" "$tb/good.zst"
head -c 20 "$tb/good.zst" > "$tb/rootfs.tar.zst"
verify_backup "$tb" && rc=0 || rc=$?
t_eq "截断压缩包被拒" "1" "$rc"
mv -f "$tb/good.zst" "$tb/rootfs.tar.zst"

echo 'not json' > "$tb/meta.json"
verify_backup "$tb" && rc=0 || rc=$?
t_eq "损坏 meta.json 被拒" "1" "$rc"
echo '{"ok":1}' > "$tb/meta.json"

t_suite "keep_backups（保留策略）"
if [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
    for i in 1 2 3 4 5 6 7; do
        mkdir -p "$BACKUP_DIR/smoketest-2025010$i-000000"; sleep 0.02
    done
    keep_backups smoketest 3 >/dev/null 2>&1
    t_eq "保留 3 份" "3" "$(find "$BACKUP_DIR" -maxdepth 1 -name 'smoketest-*' | wc -l | tr -d ' ')"
    latest=""
    for d in "$BACKUP_DIR"/smoketest-*; do
        [ -d "$d" ] || continue
        b=$(basename "$d")
        if [[ "$b" > "$latest" ]]; then latest="$b"; fi
    done
    t_eq "保留最新一份" "smoketest-20250107-000000" "$latest"
    rm -rf "$BACKUP_DIR"/smoketest-*
else
    t_ok "跳过（备份目录非空，避免误删真实数据）"
fi
list_backups >/dev/null 2>&1; t_eq "list_backups 可调用" "0" "$?"

t_suite "find -printf 兼容层"
find_supports_printf && t_ok "find 支持 -printf（原生路径）" || t_ok "find 不支持 -printf（已走回退）"
mkdir -p "$work/d1" "$work/d2"; rm -rf "$work/d2"
t_eq "find_dirs 只列目录" "d1" "$(find_dirs "$work" | grep -v src | grep -v bk | grep -v out | head -1)"

rm -rf "$work"
t_report
