#!/usr/bin/env bash
# 构建 open-frp-cross-platform-launcher 的 pacman 包（重打包上游 .deb，不重编）。
#
# 依赖：base-devel（makepkg）、bsdtar（libarchive，拆 deb 用）。
# 源在 GitHub Release 上，本机 github.com 直连不通，所以这里导出 http(s)_proxy 给
# makepkg 下载用（代理抖的时候重跑一次就行）。AUR 服务器不参与，也不碰 AUR。
#
# 用法：bash open-frp-cross-platform-launcher/make_openfrp_pkg.sh
# 产物：~/vtb/归档/open-frp-cross-platform-launcher/*.pkg.tar.zst（release_github.sh 从这里收集）
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT=/home/tc191/vtb/归档/open-frp-cross-platform-launcher
export SRCDEST="${SRCDEST:-$HOME/.cache/tc191-pkgs/src}"

export https_proxy=http://127.0.0.1:7890
export http_proxy="$https_proxy"
export NO_PROXY=127.0.0.1,localhost

for c in makepkg bsdtar; do
	command -v "$c" >/dev/null || {
		echo "缺少 $c。装一下："
		echo "  sudo pacman -S --needed base-devel libarchive"
		exit 1
	}
done

mkdir -p "$SRCDEST"
cd "$HERE"
makepkg -f

# 归档目录必须只留本次产物：release_github.sh 按「一个目录一个包」计数，
# 残留旧版本会让它报「只找到 N 个包」直接退出。
rm -f "$OUT"/*.pkg.tar.zst
mkdir -p "$OUT"
install -m644 ./*.pkg.tar.zst "$OUT/"

echo
echo "归档副本: $OUT"
ls -lh "$OUT"/*.pkg.tar.zst | sed 's/^/  /'
