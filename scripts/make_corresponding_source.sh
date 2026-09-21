#!/usr/bin/env bash
# 生成 psd2live 的「对应源码」（GPL-3.0 第 6 条要求的 Corresponding Source）。
#
# 为什么必须单独做：psd2live-bin 不是上游原样二进制 —— 构建它的工作树相对上游
# 提交 c8ad876 有改动（RigBuilder.kt / Moc3RenderOrderLowering.kt /
# gradle-wrapper.properties 各一行，外加 gradlew 的权限位）。GPL-3 要求在分发目标
# 代码时提供**实际用于构建的那份源码**，只给上游仓库链接不满足该义务。
#
# 产出: dist/psd2live-<ver>.r1.<commit>-corresponding-source.tar.zst
#       内含 git archive HEAD 的完整树 + 覆盖上工作树的改动 + 补丁副本 + 说明文件
#
# 用法: bash scripts/make_corresponding_source.sh
set -euo pipefail

TREE=/home/tc191/opt/probe-psd2live/psd2live
PATCH=/home/tc191/opt/psd2live-groupindex-fix.patch
# 仓库根目录从脚本自身位置推导（本脚本在 <root>/scripts/ 下）
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$REPO/dist"
# 源码树被清掉之后，已生成的对应源码归档放这里，下次发布直接复用
ARCHIVE_DIR=/home/tc191/vtb/归档/corresponding-source

# 源码树不在时退回复用归档：对应源码是**按包版本**固定的东西，
# 同一个 psd2live-bin 0.7.1.r1.c8ad876 对应的源码永远是同一份归档，
# 为了重新上传到新仓库而重新生成一遍没有意义（重建还可能引入差异）。
if [ ! -d "$TREE/.git" ]; then
	shopt -s nullglob
	CAND=("$ARCHIVE_DIR"/psd2live-*-corresponding-source.tar.zst)
	if [ ${#CAND[@]} -eq 1 ] && [ -f "${CAND[0]}" ]; then
		echo "  源码树不在（$TREE）"
		echo "  复用已归档的对应源码：$(basename "${CAND[0]}")"
		echo "    $(stat -c%s "${CAND[0]}") 字节  sha256 $(sha256sum "${CAND[0]}" | cut -c1-12)…"
		install -m644 "${CAND[0]}" "$DIST/"
		exit 0
	fi
	echo "  ✗ 源码树不在（$TREE），且 $ARCHIVE_DIR 里没有可复用的归档"
	echo "    要么重新 clone 到 $TREE，要么把归档放进 $ARCHIVE_DIR"
	exit 1
fi

VER=$(grep -m1 'packageVersion' "$TREE/build.gradle.kts" | sed 's/.*"\(.*\)".*/\1/')
COMMIT=$(git -C "$TREE" rev-parse --short HEAD)
NAME="psd2live-${VER}.r1.${COMMIT}"
STAGE="/tmp/p2lsrc/$NAME"

echo "== 生成 $NAME 的对应源码 =="
rm -rf /tmp/p2lsrc; mkdir -p "$STAGE"

echo "  git archive HEAD（$COMMIT）"
git -C "$TREE" archive HEAD | tar -x -C "$STAGE"

echo "  覆盖工作树里的改动："
MODIFIED=$(git -C "$TREE" diff --name-only)
for f in $MODIFIED; do
	install -Dm644 "$TREE/$f" "$STAGE/$f"
	printf '    + %-70s %s\n' "$f" "$(git -C "$TREE" diff --numstat -- "$f" | awk '{print $1"+/"$2"-"}')"
done
chmod 755 "$STAGE/gradlew" 2>/dev/null || true

[ -f "$PATCH" ] && install -m644 "$PATCH" "$STAGE/psd2live-groupindex-fix.patch"

cat > "$STAGE/README-corresponding-source.txt" <<EOF
这是 psd2live-bin ${VER} 包的对应源码（GPL-3.0 第 6 条）。

上游仓库: https://github.com/tsunehimatoi/psd2live
基准提交: ${COMMIT}

本包并非上游原样构建。构建时的工作树相对 ${COMMIT} 有以下改动：

$(git -C "$TREE" diff --stat | sed 's/^/  /')

改动内容同时以补丁形式给出：psd2live-groupindex-fix.patch
本归档即构建 psd2live-bin 时实际所用源码的完整副本。

重建方式（与原包一致）:
  cd $NAME
  ./gradlew --no-daemon createDistributable
  # 产出 build/compose/binaries/main/app/PSD2Live/，再由 make_psd2live_pkg.sh 打成 pacman 包

许可: GPL-3.0-only（完整文本见上游仓库的 LICENSE）
EOF

mkdir -p "$DIST"
( cd /tmp/p2lsrc && tar -cf - "$NAME" ) | zstd -19 -T0 -q -o "$DIST/$NAME-corresponding-source.tar.zst"
rm -rf /tmp/p2lsrc

echo "  产出: $DIST/$NAME-corresponding-source.tar.zst"
echo "        $(stat -c%s "$DIST/$NAME-corresponding-source.tar.zst") 字节"
echo "  自检:"
tar -tf "$DIST/$NAME-corresponding-source.tar.zst" | wc -l | sed 's/^/    归档条目数: /'
tar -tf "$DIST/$NAME-corresponding-source.tar.zst" | grep -E 'README-corresponding|groupindex-fix|RigBuilder\.kt|Moc3RenderOrder' | sed 's/^/    /'
