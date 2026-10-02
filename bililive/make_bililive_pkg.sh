#!/usr/bin/env bash
# 构建 bililive 的 pacman 包（源码包，走标准 makepkg）。
#
# 依赖：cargo + rust（PKGBUILD 的 makedepends）、git、base-devel、fakeroot。
# 源码是私有仓，走 git+ssh：本机 ~/.ssh/config 里 github.com 指向 ssh.github.com
# 并挂了 ProxyCommand，所以这里**不用**导 http(s)_proxy；crates 走
# ~/.cargo/config.toml 里的 rsproxy 镜像（别动那个文件）。
# 源码拉的是 tag：GitHub 上没有 v<版本> 这个 tag 就会失败，先推 tag 再打包。
#
# 用法：bash bililive/make_bililive_pkg.sh
# 产物：~/vtb/归档/bililive/*.pkg.tar.zst（release_github.sh 从这里收集）
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT=/home/tc191/vtb/归档/bililive
# git 源的裸克隆放缓存目录：默认 SRCDEST 是配方目录，会在里面留一个叫
# bililive 的仓库，跟配方目录同名，看着像把自己 clone 了一遍。
export SRCDEST="${SRCDEST:-$HOME/.cache/tc191-pkgs/src}"

for c in cargo git makepkg; do
	command -v "$c" >/dev/null || {
		echo "缺少 $c。装一下："
		echo "  sudo pacman -S --needed base-devel rust git"
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
