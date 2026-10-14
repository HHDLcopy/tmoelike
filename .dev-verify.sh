#!/data/data/com.termux/files/usr/bin/bash
# 设备侧验证脚本：拉取修复后的模块 + 重部署容器助手 + 在容器内真实执行
set -u
cd "$HOME" || exit 1
echo "== 1) --refresh-lib（真实下载路径：测速 + 逐模块 SHA256 校验） =="
bash ./tmoelike.sh --refresh-lib 2>&1 | tail -25
echo "refresh_rc=${PIPESTATUS[0]}"
echo
echo "== 2) 缓存里的 helper.sh 是否已含修复 =="
grep -n 'shift 2; \$TUI' "$HOME/.tmoelike/cache/lib/helper.sh" || echo "!! 未找到修复"
echo
echo "== 3) 重部署容器助手（container_helper_ensure） =="
timeout 30 bash ./tmoelike.sh helper ubuntu </dev/null 2>&1 | tail -12
echo "helper_rc=$?"
echo
echo "== 4) 容器内助手文件位置与内容 =="
H="$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs/usr/local/bin/tmoelike-tui"
ls -l "$H" 2>&1
sed -n '93,98p' "$H" 2>&1
