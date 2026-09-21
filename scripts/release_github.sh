#!/usr/bin/env bash
# 准备 GitHub Release 的发布资源到 dist/：
#   四个 .pkg.tar.zst + ${DBNAME}.db(.tar.gz) + ${DBNAME}.files(.tar.gz) + SHA256SUMS
#
# 为什么要同时放 <repo>.db 和 <repo>.db.tar.gz：
#   pacman 会先找 `<repo>.db`，找不到才回落 `<repo>.db.tar.gz`。
#   repo-add 产出的 `.db` 是**符号链接**，而 GitHub Release 存不了符号链接，
#   所以这里额外做一份真实文件副本（内容相同）。
#
# 用法: bash scripts/release_github.sh [tag]
#       默认 tag 直接用三个包的版本拼出来
set -euo pipefail

# 数据库文件名。默认 tc191；设 DBNAME=vtb 可以切回旧名（客户端 pacman.conf 的 [节名] 与 Server 要同步改）
DBNAME="${DBNAME:-tc191}"

# 仓库根目录从脚本自身位置推导（本脚本在 <root>/scripts/ 下），搬目录不用改脚本
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$REPO/dist"
OUT=/home/tc191/vtb/归档
OPENSEEFACE_DIR=/home/tc191/opt/openvt-pkg/openseeface

echo "== 1/5 清空 dist/ =="
rm -rf "$DIST"; mkdir -p "$DIST"

echo "== 2/5 收集包 =="
shopt -s nullglob
PKGS=()
# 每加一个包只需在这里添一行目录
PKGDIRS=("$OUT/open-vt-bin" "$OUT/psd2live-bin" "$OUT/auto-vtb-bin" "$OPENSEEFACE_DIR")
for d in "${PKGDIRS[@]}"; do
	for f in "$d"/*.pkg.tar.zst; do
		install -m644 "$f" "$DIST/"
		PKGS+=("$DIST/$(basename "$f")")
		echo "  + $(basename "$f")  ($(stat -c%s "$f") 字节)"
	done
done
[ ${#PKGS[@]} -eq ${#PKGDIRS[@]} ] || { echo "只找到 ${#PKGS[@]} 个包，应当是 ${#PKGDIRS[@]} 个"; exit 1; }

echo "== 3/5 生成仓库索引 =="
cd "$DIST"
repo-add ${DBNAME}.db.tar.gz ./*.pkg.tar.zst | sed 's/^/  /'
# GitHub Release 不能存符号链接 → 做成真实副本
for x in db files; do
	[ -f "${DBNAME}.$x.tar.gz" ] || { echo "  缺 ${DBNAME}.$x.tar.gz"; exit 1; }
	rm -f "${DBNAME}.$x"          # repo-add 把 .db/.files 做成指向 .tar.gz 的符号链接，
	cp -f "${DBNAME}.$x.tar.gz" "${DBNAME}.$x"   # 不先删就会 cp 到自己身上（同一文件）
	echo "  ${DBNAME}.$x  ← ${DBNAME}.$x.tar.gz 的实体副本"
done

echo "== 4/5 校验索引与文件一致 =="
field() { bsdtar -xOf ${DBNAME}.db.tar.gz "$1/desc" | sed -n "/^%$2%$/{n;p}"; }
FAIL=0
for p in ./*.pkg.tar.zst; do
	key=$(basename "$p" .pkg.tar.zst)
	key=${key%-x86_64}   # 索引里的目录名是 <name>-<ver>-<rel>，**不带架构**；而文件名带
	idx_sha=$(field "$key" SHA256SUM)
	idx_size=$(field "$key" CSIZE)
	[ -n "$idx_sha" ] || { echo "  ✗ $key 索引里没有 SHA256SUM（字段名写错？）"; FAIL=1; continue; }
	real_sha=$(sha256sum "$p" | cut -d' ' -f1)
	real_size=$(stat -c%s "$p")
	if [ "$idx_sha" = "$real_sha" ] && [ "$idx_size" = "$real_size" ]; then
		echo "  ✓ $key  $(printf '%s' "$idx_sha" | cut -c1-12)…  $idx_size 字节"
	else
		echo "  ✗ $key 索引与实际不符"; FAIL=1
	fi
done
[ "$FAIL" = 0 ] || exit 1

echo "== 4.5/5 生成 psd2live 的对应源码（GPL-3 第 6 条义务，不是可选项）=="
bash "$REPO/scripts/make_corresponding_source.sh" 2>&1 | sed 's/^/  /'

echo "== 5/5 写 SHA256SUMS =="
sha256sum ./*.pkg.tar.zst ./*-corresponding-source.tar.zst > SHA256SUMS
cat SHA256SUMS | sed 's/^/  /'

echo
 echo "================ dist/ 就绪 ================"
ls -lh "$DIST" | sed 's/^/  /'
TAG="${TAG:-v0.1.0}"   # 可用环境变量覆盖；与 RELEASE_NOTES.md 的版本号一致
echo
echo "  tag: $TAG"
echo
echo "===== 发布 ====="
echo "  bash $REPO/scripts/publish_pages.sh --no-build"
echo "  （把 dist/ 整体推到 gh-pages 分支，用 GitHub Pages 当 pacman 源；"
echo "    不用 GitHub Release，附件区不会堆一堆二进制）"
