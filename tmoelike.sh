#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  tmoelike.sh v2.3 —— 类 TMOE 的 Termux Linux 容器管理器（单文件入口）
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#
#  单文件分发：用户只需下载本文件。其余模块（lib/*.sh）在首次运行时
#  自动从 Gitee / GitHub 下载：
#    1. 并行探测两个源的清单（测速），选最快可用的；
#    2. 按清单逐模块下载，并对每个文件做 SHA256 校验；
#    3. 全部成功后整体原子安装（不留半成品缓存）；
#    4. 之后启动本地优先，缺文件才联网补齐。
#
#  开发者 / 离线场景：
#    - 脚本同目录存在完整 lib/ 时直接使用（优先于缓存，便于开发）。
#    - TMOE_LIB=<目录>      指定本地模块目录（测试用）
#    - TMOE_NO_FETCH=1      禁止联网（离线环境）
#    - TMOE_REFRESH_LIB=1   强制重新下载（等价 --refresh-lib）
#    - TMOE_SOURCES="名|URL 名|URL"            覆盖下载源
#    - TMOE_MANIFEST_SHA256=<sha256>          固定清单指纹（防清单被替换）
#    - TMOE_PROBE_TIMEOUT=<秒>                测速探测超时（默认 8，弱网可调小）
# ============================================================
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

TMOE_BOOTSTRAP_VERSION="2.3.0"

# ---------- 下载源（顺序即默认优先级，实际按测速选择） ----------
TMOE_DEFAULT_SOURCES=(
    "github|https://raw.githubusercontent.com/HHDLcopy/tmoelike/main"
    "gitee|https://gitee.com/dragon470/tmoelike/raw/main"
)

# 模块加载顺序（与 lib/manifest.json 的顺序一致；权威来源是清单）
TMOE_MODULES=(
    common tui archive deps paths registry download proot helper
    chroot desktop ssh vnc beautify plugin update backup_util menu cli
)

# ---------- 基础路径 ----------
_tmo_self="${BASH_SOURCE[0]:-}"
if [ -z "${TMOE_BASE:-}" ]; then
    if [ -n "$_tmo_self" ] && [ -f "$_tmo_self" ]; then
        TMOE_BASE="$(cd "$(dirname "$_tmo_self")" && pwd -P)"
    else
        TMOE_BASE="${HOME}/.tmoelike"
    fi
fi

TMOE_CACHE_DIR="${HOME}/.tmoelike/cache"
TMOE_CACHE_LIB="${TMOE_CACHE_DIR}/lib"
TMOE_MANIFEST="${TMOE_CACHE_DIR}/manifest.json"
TMOE_ANCHOR="${TMOE_CACHE_DIR}/manifest.sha256"
TMOE_UPDATE_STAMP="${TMOE_CACHE_DIR}/.last-check"

# ---------- 引导期小工具（此时还没有 lib/，不能依赖日志模块） ----------
_boot_info() { printf '%s\n' "$*" >&2; }
_boot_warn() { printf '警告：%s\n' "$*" >&2; }
_boot_die()  { printf '错误：%s\n' "$*" >&2; exit 1; }

_boot_sha256() {
    local f="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$f" 2>/dev/null | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'
    else
        return 1
    fi
}

# 输出可用源：每行 "名称|基础URL"
_boot_sources() {
    local s
    if [ -n "${TMOE_SOURCES:-}" ]; then
        for s in $TMOE_SOURCES; do printf '%s\n' "$s"; done
    else
        for s in "${TMOE_DEFAULT_SOURCES[@]}"; do printf '%s\n' "$s"; done
    fi
}

# ---------- 测速：并行拉取各源清单，选最快可用者 ----------
# 输出 "名称|基础URL|耗时"，全部失败则无输出
_boot_speedtest() {
    local dir; dir=$(mktemp -d)
    local names=() urls=() pids=()

    while IFS='|' read -r name url; do
        [ -n "$name" ] || continue
        names+=("$name"); urls+=("$url")
        (
            local t=""
            t=$(curl -fsSL --connect-timeout 3 \
                    --max-time "${TMOE_PROBE_TIMEOUT:-8}" \
                    -o "${dir}/${name}.json" -w '%{time_total}' \
                    "${url}/lib/manifest.json" 2>/dev/null) || t=""
            [ -n "$t" ] && printf '%s' "$t" > "${dir}/${name}.time"
        ) &
        pids+=($!)
    done < <(_boot_sources)

    local p
    for p in ${pids[@]+"${pids[@]}"}; do wait "$p" 2>/dev/null || true; done

    local i best_time="" best_line=""
    for i in "${!names[@]}"; do
        local t
        t=$(cat "${dir}/${names[$i]}.time" 2>/dev/null || true)
        [ -n "$t" ] || continue
        if [ -z "$best_time" ] || awk "BEGIN{exit !($t < $best_time)}"; then
            best_time="$t"
            best_line="${names[$i]}|${urls[$i]}|${t}"
        fi
    done
    rm -rf "$dir"
    [ -n "$best_line" ] && printf '%s\n' "$best_line"
    return 0
}

# ---------- 清单指纹（防整份替换） ----------
_boot_manifest_hash() {
    local f="$1" h=""
    h=$( { grep -oE '"sha256"[[:space:]]*:[[:space:]]*"[0-9a-f]{64}"' "$f" 2>/dev/null \
           | grep -oE '[0-9a-f]{64}' || true; } | sha256sum 2>/dev/null | awk '{print $1}' )
    h=${h:-}
    if [ -n "$h" ] && [ "$h" != "$(printf '' | sha256sum | awk '{print $1}')" ]; then
        printf '%s' "$h"
    fi
    return 0
}

_boot_check_manifest() {
    local f="$1"
    local want="${TMOE_MANIFEST_SHA256:-}"
    local got; got=$(_boot_manifest_hash "$f")
    if [ -n "$want" ]; then
        if [ "$got" != "$want" ]; then
            _boot_warn "清单指纹不匹配（清单可能被替换）。"
            _boot_warn "  期望：$want"
            _boot_warn "  实际：${got:-<解析失败>}"
            _boot_die "已中止。确认无误后可更新 TMOE_MANIFEST_SHA256。"
        fi
    fi
    if [ -f "$TMOE_ANCHOR" ]; then
        local last; last=$(cat "$TMOE_ANCHOR" 2>/dev/null || true)
        if [ -n "$last" ] && [ -n "$got" ] && [ "$got" != "$last" ]; then
            _boot_warn "上游清单与本机记录不一致（可能是正常更新）。"
            _boot_warn "  本机：$last"
            _boot_warn "  本次：$got"
        fi
    fi
    return 0
}

# 从清单输出 "模块名 sha256" 行（需要 jq 或 python3 之一）
_boot_manifest_pairs() {
    local f="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -r '.modules[] | "\(.name) \(.sha256)"' "$f" 2>/dev/null && return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$f" <<'PY' 2>/dev/null && return 0
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
if doc.get("format") != 1:
    sys.exit("清单格式不支持")
for m in doc.get("modules", []):
    name, sha = m.get("name", ""), m.get("sha256", "")
    if not name or len(sha) != 64:
        sys.exit("清单条目非法：%r" % name)
    print("%s %s" % (name, sha))
PY
    fi
    return 1
}

# 下载单个模块：0 成功 / 1 网络失败 / 2 校验失败
_boot_fetch_module() {
    local url="$1" dest="$2" want="$3" got=""
    if ! curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 5 --max-time 60 \
            -o "$dest" "$url" 2>/dev/null; then
        rm -f "$dest"
        return 1
    fi
    if [ -n "$want" ]; then
        got=$(_boot_sha256 "$dest") || { rm -f "$dest"; return 2; }
        if [ "$got" != "$want" ]; then
            rm -f "$dest"
            return 2
        fi
    fi
    return 0
}

_boot_lib_ok() {
    local dir="$1" m
    [ -d "$dir" ] || return 1
    for m in "${TMOE_MODULES[@]}"; do
        [ -f "${dir}/${m}.sh" ] || return 1
    done
    return 0
}

# ---------- 下载并原子安装全部模块 ----------
_boot_install_lib() {
    local dest="$1"
    local force="${TMOE_REFRESH_LIB:-0}"

    if [ "$force" != "1" ] && _boot_lib_ok "$dest"; then
        return 0
    fi
    if [ "${TMOE_NO_FETCH:-0}" = "1" ]; then
        _boot_die "本地模块不完整，且已设置 TMOE_NO_FETCH=1（离线模式）。
可手动准备模块目录后这样启动：
  TMOE_LIB=/path/to/lib $0"
    fi
    command -v curl >/dev/null 2>&1 || _boot_die "缺少 curl，无法下载模块（pkg install curl）"

    mkdir -p "$TMOE_CACHE_DIR"
    local tmp; tmp=$(mktemp -d)

    _boot_info "首次运行：正在探测下载源速度…"
    local best; best=$(_boot_speedtest)
    if [ -z "$best" ]; then
        _boot_die "无法连接任何下载源（GitHub / Gitee 均不可达）。
可检查网络后重试，或手动准备 lib/ 目录：
  TMOE_LIB=/path/to/lib $0"
    fi
    local sname surl stime
    IFS='|' read -r sname surl stime <<< "$best"
    _boot_info "已选源：$sname（$(awk "BEGIN{printf \"%.2f\", $stime}")s）"

    # --- 清单 ---
    local mok=0
    if curl -fsSL --connect-timeout 5 --max-time 20 -o "$tmp/manifest.json" \
            "${surl}/lib/manifest.json" 2>/dev/null; then
        mok=1
    else
        _boot_warn "从 $sname 获取清单失败，尝试其他源…"
        local an am
        while IFS='|' read -r an am; do
            [ "$an" = "$sname" ] && continue
            if curl -fsSL --connect-timeout 5 --max-time 20 -o "$tmp/manifest.json" \
                    "${am}/lib/manifest.json" 2>/dev/null; then
                sname="$an"; surl="$am"; mok=1; break
            fi
        done < <(_boot_sources)
    fi
    [ "$mok" = "1" ] || _boot_die "无法获取模块清单（lib/manifest.json）。"
    _boot_check_manifest "$tmp/manifest.json"

    local pairs; pairs=$(_boot_manifest_pairs "$tmp/manifest.json") || \
        _boot_die "清单解析失败（需要 jq 或 python3）。"
    [ -n "$pairs" ] || _boot_die "清单为空：lib/manifest.json"

    # --- 逐模块下载 + 校验 ---
    mkdir -p "$tmp/lib"
    local name sha rc
    while read -r name sha; do
        [ -n "$name" ] || continue
        case "$name" in
            */*|*..*|"") _boot_die "清单包含非法模块名：$name" ;;
        esac
        rc=0
        _boot_fetch_module "${surl}/lib/${name}.sh" "${tmp}/lib/${name}.sh" "$sha" || rc=$?
        if [ "$rc" -ne 0 ]; then
            local ok=0 n2 u2
            while IFS='|' read -r n2 u2; do
                [ "$n2" = "$sname" ] && continue
                rc=0
                _boot_fetch_module "${u2}/lib/${name}.sh" "${tmp}/lib/${name}.sh" "$sha" || rc=$?
                [ "$rc" -eq 0 ] && { ok=1; break; }
            done < <(_boot_sources)
            if [ "$ok" -ne 1 ]; then
                if [ "$rc" -eq 2 ]; then
                    _boot_die "模块 ${name}.sh 的 SHA256 校验失败：文件可能被篡改，或源未同步。
已中止（不会写入缓存）。"
                fi
                _boot_die "模块 ${name}.sh 下载失败（所有源均不可用）。"
            fi
        fi
        printf '  下载 %-14s ok\n' "${name}.sh" >&2
    done <<< "$pairs"

    # --- 完整性确认后原子替换 ---
    local m
    for m in "${TMOE_MODULES[@]}"; do
        [ -s "${tmp}/lib/${m}.sh" ] || _boot_die "下载结果缺少模块：${m}.sh"
    done

    local bak="${dest}.old.$$"
    mkdir -p "$(dirname "$dest")"
    [ -d "$dest" ] && mv "$dest" "$bak" 2>/dev/null || true
    if mv "$tmp/lib" "$dest" 2>/dev/null; then
        rm -rf "$bak"
    else
        [ -d "$bak" ] && mv "$bak" "$dest" 2>/dev/null || true
        rm -rf "$tmp"
        _boot_die "安装模块失败（无法写入 $dest）。"
    fi

    cp -f "$tmp/manifest.json" "$TMOE_MANIFEST" 2>/dev/null || true
    local mh; mh=$(_boot_manifest_hash "$tmp/manifest.json")
    [ -n "$mh" ] && printf '%s' "$mh" > "$TMOE_ANCHOR" 2>/dev/null || true

    rm -rf "$tmp"
    _boot_info "模块已安装到：$dest"
    return 0
}

# ---------- 更新提示（每天最多检查一次，不阻塞启动） ----------
_boot_maybe_update_notice() {
    [ "${TMOE_NO_FETCH:-0}" = "1" ] && return 0
    local now last
    now=$(date +%s)
    if [ -f "$TMOE_UPDATE_STAMP" ]; then
        last=$(cat "$TMOE_UPDATE_STAMP" 2>/dev/null || echo 0)
        case "$last" in ''|*[!0-9]*) last=0 ;; esac
        [ $((now - last)) -lt 86400 ] && return 0
    fi
    printf '%s' "$now" > "$TMOE_UPDATE_STAMP" 2>/dev/null || true

    local best; best=$(_boot_speedtest 2>/dev/null) || return 0
    [ -n "$best" ] || return 0
    local name url t tmp
    IFS='|' read -r name url t <<< "$best"
    tmp=$(mktemp)
    if curl -fsSL --connect-timeout 3 --max-time 12 -o "$tmp" \
            "${url}/lib/manifest.json" 2>/dev/null; then
        local got want
        got=$(_boot_manifest_hash "$tmp")
        want=$(cat "$TMOE_ANCHOR" 2>/dev/null || true)
        if [ -n "$want" ] && [ -n "$got" ] && [ "$got" != "$want" ]; then
            _boot_warn "上游模块有更新。执行 '$0 --refresh-lib' 可升级。"
        fi
    fi
    rm -f "$tmp"
    return 0
}

# ---------- 剥离引导专属参数 ----------
TMOE_EXTRA_ARGS=()
for _a in "$@"; do
    case "$_a" in
        --refresh-lib)        export TMOE_REFRESH_LIB=1 ;;
        --offline|--no-fetch) export TMOE_NO_FETCH=1 ;;
        *) TMOE_EXTRA_ARGS+=("$_a") ;;
    esac
done
set -- ${TMOE_EXTRA_ARGS[@]+"${TMOE_EXTRA_ARGS[@]}"}
unset _a TMOE_EXTRA_ARGS

# ---------- 启动依赖：jq 或 python3（解析模块清单用） ----------
# 为什么在加载前就问：下载模块需要先解析 manifest，此时还没有 lib/，
# 不能复用 lib/deps.sh 的检查；这里缺失就直接引导安装，而不是报错退出。
# 注意：不能只用 command -v 判断——命令"存在"不等于"可用"。
# jq 可能是损坏的二进制、缺动态库、或被一个错误包装脚本遮蔽，
# 那种情况 command -v 会通过，但真正解析时失败。所以这里实测一次：
#   jq     -> 能否输出版本号（兼容 1.5 及更早的 --version 写法）
#   python3-> 能否真正执行
_boot_jq_usable() {
    command -v jq >/dev/null 2>&1 || return 1
    jq --version >/dev/null 2>&1 || jq -V >/dev/null 2>&1
}

_boot_python_usable() {
    command -v python3 >/dev/null 2>&1 || return 1
    python3 -c 'import sys' >/dev/null 2>&1
}

_boot_have_parser() {
    _boot_jq_usable && return 0
    _boot_python_usable && return 0
    return 1
}

_boot_missing_parsers() {
    local miss=()
    _boot_jq_usable     || miss+=(jq)
    _boot_python_usable || miss+=(python3)
    printf '%s\n' "${miss[@]}"
}

_boot_ensure_parser() {
    # 语义：jq 是首选（启动更快、依赖更小）。缺 jq 时若有 python3 则继续
    # （可用但稍慢），两者都没有就必须先装上，否则连清单都解析不了。
    if ! _boot_jq_usable; then
        if _boot_python_usable; then
            _boot_info "提示：未安装 jq，将改用 python3 解析清单（可用但稍慢）。"
        else
            _boot_warn "缺少 jq 与 python3，无法解析模块清单。"
        fi
    fi
    _boot_jq_usable && return 0

    local miss_s; miss_s=$(_boot_missing_parsers | tr '\n' ' ')
    miss_s=${miss_s% }

    local pkgs; pkgs=$(_boot_missing_parsers | tr '\n' ' ')
    pkgs=${pkgs% }

    # 有 pkg（Termux/Android）就自动安装，不再询问——用户明确要求“自动下载”。
    # 安装失败或没有 pkg 时，再给出可复制的指引并中止（绝不静默继续）。
    if command -v pkg >/dev/null 2>&1; then
        _boot_info "正在自动安装：pkg install -y ${pkgs}"
        if pkg install -y ${pkgs}; then
            # 关键：bash 会缓存命令路径。安装前若探测过（解析到旧的/不存在的路径），
            # 安装后仍会用缓存，导致"装好了却判定不可用"。这里清缓存再检测。
            hash -r 2>/dev/null || true
            if _boot_have_parser; then
                _boot_info "已安装：${pkgs}"
                return 0
            fi
        fi
        _boot_warn "自动安装 ${pkgs} 未成功（详见上方 pkg 输出）。"
    fi

    _boot_die "缺少 ${miss_s}，已中止。
请手动安装后重试：
  Termux:        pkg install ${pkgs}
  Debian/Ubuntu: apt install ${pkgs}
  Alpine:        apk add ${pkgs}
（或设置 TMOE_LIB=<本地模块目录> 离线运行）"
}

# ---------- 解析器就绪（必须在下载之前！） ----------
# 下载模块的第一步就是取回并解析 lib/manifest.json，而解析需要 jq 或 python3。
# 若把它放在 _boot_install_lib 之后，首次运行（无缓存且无 jq/python3）会在
# 解析清单时报 "清单解析失败（需要 jq 或 python3）"，根本走不到自动安装。
_boot_ensure_parser

# ---------- 决定模块目录：显式 > 同目录 lib/ > 缓存 ----------
if [ -z "${TMOE_LIB:-}" ]; then
    if [ -n "$_tmo_self" ] && [ -f "$_tmo_self" ] && \
       _boot_lib_ok "$(dirname "$_tmo_self")/lib"; then
        TMOE_LIB="$(cd "$(dirname "$_tmo_self")/lib" && pwd -P)"
    else
        _boot_install_lib "$TMOE_CACHE_LIB"
        if [ -n "$_tmo_self" ] && [ -f "$_tmo_self" ]; then
            _boot_maybe_update_notice
        fi
        TMOE_LIB="$TMOE_CACHE_LIB"
    fi
fi
export TMOE_LIB

# ---------- 加载模块 ----------
for _m in "${TMOE_MODULES[@]}"; do
    if [ ! -f "${TMOE_LIB}/${_m}.sh" ]; then
        _boot_die "缺少模块：${TMOE_LIB}/${_m}.sh
可执行 '$0 --refresh-lib' 重新下载。"
    fi
    # shellcheck source=/dev/null
    source "${TMOE_LIB}/${_m}.sh"
done
unset _m _tmo_self

main "$@"
