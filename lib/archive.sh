#!/usr/bin/env bash
# ------------------------------------------------------------
#  tmoelike archive.sh
#  ⚠️ AI 生成代码（AI-Generated）—— 需求与验收来自人类，实现由 AI 完成。
#  本文件由入口 tmoelike.sh 通过 source 加载，不单独执行。
# ------------------------------------------------------------
# 按魔数识别压缩格式（避免依赖 file 命令）
detect_compress_cmd() {
    local f="$1"
    local m1 m2
    m1=$(od -An -tx1 -N2 "$f" 2>/dev/null | tr -d ' \n')
    case "$m1" in
        1f8b) echo "gzip" ;;
        fd37) echo "xz" ;;
        425a) echo "bzip2" ;;
    esac
    m2=$(od -An -tx1 -N4 "$f" 2>/dev/null | tr -d ' \n')
    case "$m2" in
        28b52ffd) echo "zstd" ;;
    esac
}

# tar 防路径穿越：先预检条目，再带 --no-same-owner 解压
# 支持：纯 tar、.tar.gz / .tar.xz / .tar.bz2 / .tar.zst
safe_untar() {
    local archive="$1" dest="$2"
    [ -f "$archive" ] || { warn "压缩包不存在：$archive"; return 1; }

    # 先解出纯 tar 流（不落盘则直接用 tar 管道）
    local comp; comp=$(detect_compress_cmd "$archive")
    local dec=()  # 解压命令（空数组 = 无需解压）
    if [ -n "$comp" ]; then
        command -v "$comp" >/dev/null 2>&1 || { warn "缺少解压工具：$comp"; return 1; }
        case "$comp" in
            gzip)  dec=(gzip -dc) ;;
            xz)    dec=(xz -dc) ;;
            bzip2) dec=(bzip2 -dc) ;;
            zstd)  dec=(zstd -q -dc) ;;
        esac
    fi

    # 预检条目：拦截绝对路径与 ../
    local bad
    if [ ${#dec[@]} -gt 0 ]; then
        bad=$("${dec[@]}" "$archive" 2>/dev/null | tar -tf - 2>/dev/null | \
              awk '/^\// || /(^|\/)\.\.(\/|$)/ {print; exit}' || true)
    else
        bad=$(tar -tf "$archive" 2>/dev/null | \
              awk '/^\// || /(^|\/)\.\.(\/|$)/ {print; exit}' || true)
    fi
    if [ -n "$bad" ]; then
        warn "压缩包包含危险路径，已拒绝：$bad"
        return 1
    fi

    mkdir -p "$dest"
    local xrc=0
    if [ ${#dec[@]} -gt 0 ]; then
        "${dec[@]}" "$archive" | tar -xf - -C "$dest" --no-same-owner --no-same-permissions || xrc=$?
    else
        tar -xf "$archive" -C "$dest" --no-same-owner --no-same-permissions || xrc=$?
    fi
    if [ "$xrc" -ne 0 ]; then
        # 注意：GNU tar 对「成员名含 ../ 被拒」的退出码随构建不同（1 或 2），
        # 这里统一归一为 1，让调用方只需判断「非 0 即失败」。
        warn "解压失败（tar 退出码 ${xrc}）：$archive"
        return 1
    fi
    return 0
}

# ---------- 压缩兼容层 ----------
# 某些环境（受限 sandbox / 精简 tar）下 tar 无法 fork 外部压缩程序
# （tar -I/--zstd/-z 报 "Cannot exec"），此时退化为「先打 tar 再压缩」。
TAR_CAN_EXEC_COMPRESSOR=""
tar_can_exec_compressor() {
    [ -n "$TAR_CAN_EXEC_COMPRESSOR" ] && return "$TAR_CAN_EXEC_COMPRESSOR"
    local d out
    d=$(mktemp -d)
    out=0
    if printf 'x\n' > "$d/f" 2>/dev/null && \
       tar -I 'zstd -q -1' -cf "$d/a.tar.zst" -C "$d" f >/dev/null 2>&1; then
        out=1
    fi
    rm -rf "$d"
    if [ "$out" -eq 1 ]; then
        TAR_CAN_EXEC_COMPRESSOR=0
    else
        TAR_CAN_EXEC_COMPRESSOR=1
        log "提示：tar 无法调用外部压缩程序，改用两段式压缩管道"
    fi
    return "$TAR_CAN_EXEC_COMPRESSOR"
}

# 把目录打包成 zstd 压缩的 tar
#   zstd_create <src_dir> <out.tar.zst> <zstd 级别>
zstd_create() {
    local src="$1" out="$2" level="${3:-3}"
    if tar_can_exec_compressor; then
        ( cd "$src" && tar -I "zstd -T0 -${level}" -cf "$out" . )
    else
        local raw; raw=$(mktemp)
        ( cd "$src" && tar -cf "$raw" . ) || { rm -f "$raw"; return 1; }
        zstd -q -T0 "-${level}" -f -o "$out" "$raw" || { rm -f "$raw"; return 1; }
        rm -f "$raw"
    fi
}

# 用 xz / gzip 打包目录（tar 无法调用外部压缩程序时同样两段式回退）
#   tar_create_xz <src_dir> <out> | tar_create_gz <src_dir> <out>
tar_create_stream() {
    local prog="$1" level_flag="$2" src="$3" out="$4"
    if tar_can_exec_compressor; then
        ( cd "$src" && tar -I "${prog} ${level_flag}" -cf "$out" . )
    else
        local raw; raw=$(mktemp)
        ( cd "$src" && tar -cf "$raw" . ) || { rm -f "$raw"; return 1; }
        "$prog" $level_flag -c "$raw" > "$out" 2>/dev/null || { rm -f "$raw"; return 1; }
        rm -f "$raw"
    fi
}

# 解开 zstd 压缩的 tar 到目录（带路径穿越防护）
#   zstd_extract <in.tar.zst> <dest_dir>
zstd_extract() {
    local arc="$1" dest="$2"
    mkdir -p "$dest"
    if tar_can_exec_compressor; then
        tar -I 'zstd -T0 -d' -xf "$arc" -C "$dest" --no-same-owner --no-same-permissions
    else
        local raw; raw=$(mktemp)
        if ! zstd -q -dc "$arc" > "$raw"; then rm -f "$raw"; return 1; fi
        safe_untar "$raw" "$dest"
        local rc=$?
        rm -f "$raw"
        return $rc
    fi
}

# 校验 zstd 包完整性
zstd_test() {
    zstd -t "$1" >/dev/null 2>&1
}
