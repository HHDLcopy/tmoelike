#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike download.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# ============================================================
#  下载器：断点续传 + SHA256 校验 + 重试 + 镜像回退（修复 #14）
#  修复：不再做字符串替换（会把 /alpine 变成 /alpine/alpine），
#        改为显式 MIRROR_MAP + mirrorize，只换主机名、保留原路径。
# ============================================================
declare -A MIRROR_MAP=(
    ["dl-cdn.alpinelinux.org"]="mirrors.tuna.tsinghua.edu.cn"
    ["deb.debian.org"]="mirrors.tuna.tsinghua.edu.cn"
    ["archive.ubuntu.com"]="mirrors.tuna.tsinghua.edu.cn"
    ["security.ubuntu.com"]="mirrors.tuna.tsinghua.edu.cn"
    ["github.com"]="mirror.ghproxy.com/github.com"
    ["raw.githubusercontent.com"]="mirror.ghproxy.com/raw.githubusercontent.com"
)

mirrorize() {
    local url="$1"
    local host path mh
    host=$(printf '%s' "$url" | awk -F/ '{print $3}')
    path=$(printf '%s' "$url" | cut -d/ -f4-)
    mh="${MIRROR_MAP[$host]:-}"
    if [ -n "$mh" ]; then
        # 只替换主机名（github 走 ghproxy 前缀），路径原样保留
        printf 'https://%s/%s\n' "$mh" "$path"
    else
        printf '%s\n' "$url"
    fi
}
download_file() {
    local url="$1" dest="$2" sha256="${3:-}"
    local candidates=("$url")
    local mir; mir=$(mirrorize "$url")
    [ "$mir" != "$url" ] && candidates+=("$mir")

    # 去重（不使用 mapfile，保持兼容）
    local uniq=() c u seen
    for c in "${candidates[@]}"; do
        seen=0
        for u in ${uniq[@]+"${uniq[@]}"}; do
            [ "$u" = "$c" ] && { seen=1; break; }
        done
        [ "$seen" -eq 0 ] && uniq+=("$c")
    done

    local tries=0
    for m in "${uniq[@]}"; do
        tries=$((tries+1))
        log "下载尝试 [$tries]: $m"
        if ! curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 \
                -C - -o "$dest" "$m" 2>>"$MAIN_LOG"; then
            continue        # 网络/镜像问题：可以换下一个源
        fi

        if [ -n "$sha256" ]; then
            local actual
            actual=$(sha256sum "$dest" | awk '{print $1}')
            if [ "$actual" != "$sha256" ]; then
                # 安全：哈希不匹配一律硬失败，绝不静默换源重试
                # （换源重试会掩盖 MITM/投毒，并把校验降级为装饰）
                rm -f "$dest"
                printf '错误：SHA256 校验失败（源：%s）\n  期望：%s\n  实际：%s\n' \
                    "$m" "$sha256" "$actual" >&2
                log "SHA256 校验失败，拒绝继续：$m"
                return 2
            fi
        fi
        return 0
    done
    return 1
}

# ---------- 远端校验值获取（SHA256 校验闭环） ----------
# 责任链：① 用户 config/chroot-sha256.json ② 官方 *.sha256 / SHA256SUMS ③ 交还调用方询问
get_chroot_sha_url() {
    local distro="$1" arch="$2"
    local base="" fname=""
    local url; url=$(get_chroot_url "$distro" "$arch")
    [ -n "$url" ] || { echo ""; return; }
    base="${url%/*}"
    fname="${url##*/}"
    case "$distro:$arch" in
        alpine:*)  echo "${base}/${fname}.sha256" ;;
        ubuntu:*)  echo "${base}/SHA256SUMS" ;;
        debian:*)  echo "${base}/SHA256SUMS" ;;
        fedora:*)  echo "" ;;
        *)         echo "" ;;
    esac
}

# 下载并解析远端校验文件，回显 64 位十六进制 sha256（失败回显空）
fetch_chroot_sha() {
    local distro="$1" arch="$2"
    local sha_url; sha_url=$(get_chroot_sha_url "$distro" "$arch")
    [ -n "$sha_url" ] || { echo ""; return; }
    command -v curl >/dev/null 2>&1 || { echo ""; return; }

    local body; body=$(curl -fsSL --connect-timeout 15 "$sha_url" 2>/dev/null)
    [ -n "$body" ] || { echo ""; return; }

    local fname; fname=$(basename "$(get_chroot_url "$distro" "$arch")")
    local got=""
    # sums 文件：按文件名匹配；单文件 .sha256：取第一个字段
    got=$(printf '%s\n' "$body" | awk -v f="$fname" '
        $0 ~ f && $1 ~ /^[0-9a-f]{64}$/ {print $1; exit}
    ')
    if [ -z "$got" ]; then
        got=$(printf '%s\n' "$body" | awk '
            $1 ~ /^[0-9a-f]{64}$/ {print $1; exit}
        ')
    fi
    printf '%s\n' "$got"
}

# 综合取校验值：用户配置优先，其次远端官方文件
resolve_chroot_sha() {
    local distro="$1" arch="$2"
    local sha; sha=$(get_chroot_sha "$distro" "$arch")
    if [ -n "$sha" ]; then
        printf '%s\n' "$sha"; return 0
    fi
    fetch_chroot_sha "$distro" "$arch"
}
