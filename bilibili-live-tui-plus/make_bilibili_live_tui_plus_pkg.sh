#!/usr/bin/env bash
# 构建 bilibili-live-tui-plus 的 pacman 包（源码包，走标准 makepkg）。
#
# 依赖：go（PKGBUILD 的 makedepends）、base-devel、fakeroot。
# 代理：本机 github.com 直连不通，makepkg 下源码 tarball 要走 http(s)_proxy；
#       proxy.golang.org 同样不通，所以 go 的模块代理走 goproxy.cn。
#
# 用法：bash bilibili-live-tui-plus/make_bilibili_live_tui_plus_pkg.sh
# 产物：~/vtb/归档/bilibili-live-tui-plus/*.pkg.tar.zst（release_github.sh 从这里收集）
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT=/home/tc191/vtb/归档/bilibili-live-tui-plus

export https_proxy=http://127.0.0.1:7890
export http_proxy="$https_proxy"
export NO_PROXY=127.0.0.1,localhost
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"

if ! command -v go >/dev/null; then
	echo "缺少 go。装一下："
	echo "  sudo pacman -S --needed go"
	exit 1
fi

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
