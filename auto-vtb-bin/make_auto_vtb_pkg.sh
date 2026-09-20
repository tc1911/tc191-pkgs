#!/usr/bin/env bash
# 把 Auto_Vtb（psd2live 的下游衍生版）的 Compose Desktop app image 打成 pacman 包 auto-vtb-bin。
#
# 为什么这么打：
#   - app image 自带 90M JRE（lib/runtime）→ 不需要 java 运行时依赖，也不需要 gradle 或源码目录
#   - jpackage 启动器按 argv[0] 所在目录定位 lib/，所以 /usr/bin/auto-vtb 必须是绝对路径的包装脚本，
#     不能做符号链接（符号链接会让它去 /usr/lib 找，直接起不来）
#   - 上游 .gitignore 的 `*CubismSdk*` 误吞了作者自己写的
#     src/main/kotlin/io/github/psd2live/core/CubismSdkPreviewSession.kt，因此源码树里多了个
#     libs/cubism-sdk-classes.jar（从官方 v0.6.0 release jar 提取同名 class）。
#     那是本项目自己的 GPL 代码，不是 Live2D 的专有 SDK —— 发布没有许可证问题。
#   - 桌面匹配用 StartupWMClass=java-lang-Thread：Skiko 没设置 Wayland app_id，
#     落到 JVM 线程名的默认值上（实测 `wayland-info`/窗口属性确认）。
set -euo pipefail

SRC=/home/tc191/vtb/仓库/Auto_Vtb_beta-main
GITDIR=/home/tc191/vtb/仓库/avtb-git   # 只用来取版本号（源码树是 zip 解出来的，不是 git 仓库）
APP="$SRC/build/compose/binaries/main/app/Auto_Vtb"
OUT=/home/tc191/vtb/归档/auto-vtb-bin
STAGE=/tmp/auto-vtb-stage
V=0.6.0

if [ ! -x "$APP/bin/Auto_Vtb" ]; then
	echo "缺少 app image。先跑："
	echo "  cd $SRC && ./gradlew --no-daemon createDistributable"
	exit 1
fi

CNT=$(git -C "$GITDIR" rev-list --count HEAD 2>/dev/null || echo 1)
COMMIT=$(git -C "$GITDIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
EXTRA=$( [ -d "$SRC/libs" ] && echo "patch1" || echo "" )
PKGVER="$V.r$CNT.$COMMIT${EXTRA:+.local}"
echo "== 版本: $PKGVER  (上游 commit $COMMIT, 本地补丁: ${EXTRA:-无}) =="

echo "== 1/4 暂存到 $STAGE =="
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -a "$APP/bin" "$APP/lib" "$STAGE/"
install -m644 "$SRC/LICENSE" "$STAGE/LICENSE"

# jpackage 启动器靠 argv[0] 的目录找 lib/，所以必须是绝对路径的包装脚本
cat > "$STAGE/auto-vtb" <<'WRAP'
#!/bin/sh
exec /opt/auto-vtb/bin/Auto_Vtb "$@"
WRAP
chmod 755 "$STAGE/auto-vtb"

cat > "$STAGE/auto-vtb.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Auto_Vtb
Comment=PSD 到 Live2D 的自动绑定流水线（内含绑定/导出 + MCP 服务）
Exec=auto-vtb
Icon=auto-vtb
Terminal=false
Categories=Graphics;
StartupWMClass=java-lang-Thread
DESK

echo "  暂存大小: $(du -sh "$STAGE" | cut -f1)"

echo "== 2/4 打源 tar.zst =="
mkdir -p "$OUT"
rm -f "$OUT/auto-vtb-$PKGVER.tar.zst"
tar -C "$STAGE" --zstd -cf "$OUT/auto-vtb-$PKGVER.tar.zst" .
SUM=$(sha256sum "$OUT/auto-vtb-$PKGVER.tar.zst" | cut -d' ' -f1)
echo "  源包 $(du -h "$OUT/auto-vtb-$PKGVER.tar.zst" | cut -f1)  sha256=$SUM"

echo "== 3/4 写 PKGBUILD =="
P=/tmp/auto-vtb-pkgbuild; rm -rf "$P"; mkdir -p "$P"
cp "$OUT/auto-vtb-$PKGVER.tar.zst" "$P/"
cat > "$P/PKGBUILD" <<PKGBUILD
# 由 $(basename "$0") 生成
pkgname=auto-vtb-bin
pkgver=$PKGVER
pkgrel=1
pkgdesc='PSD 到 Live2D 的自动绑定流水线（Compose Desktop app image，自带 JRE，内含 MCP 服务）'
arch=('x86_64')
url='https://github.com/lTwTlol/Auto_Vtb_beta'
license=('GPL-3.0-only')
# 直接依赖取自 libskiko-linux-x64.so / libawt_xawt.so / libfontmanager.so 的 ldd 结果
# （与 psd2live-bin 同款 Compose/Skiko 版本）。不依赖 java：lib/runtime 里自带 90M JRE。
depends=('glibc' 'gcc-libs' 'libx11' 'libxext' 'libxi' 'libxrender' 'libxtst' 'libglvnd' 'fontconfig' 'freetype2')
optdepends=('hicolor-icon-theme: 桌面图标')
options=('!strip')
source=("auto-vtb-$PKGVER.tar.zst")
sha256sums=('$SUM')

prepare() {
	# 源包是 GNU tar 打的（--zstd），makepkg 默认不认，自己解
	bsdtar -xf "\$srcdir/auto-vtb-$PKGVER.tar.zst" -C "\$srcdir"
}

package() {
	install -dm755 "\$pkgdir/opt/auto-vtb"
	cp -a "\$srcdir/bin" "\$srcdir/lib" "\$pkgdir/opt/auto-vtb/"
	install -Dm755 "\$srcdir/auto-vtb" "\$pkgdir/usr/bin/auto-vtb"
	install -Dm644 "\$srcdir/auto-vtb.desktop" "\$pkgdir/usr/share/applications/auto-vtb.desktop"
	install -Dm644 "\$srcdir/lib/Auto_Vtb.png" "\$pkgdir/usr/share/icons/hicolor/1024x1024/apps/auto-vtb.png"
	install -Dm644 "\$srcdir/LICENSE" "\$pkgdir/usr/share/licenses/auto-vtb-bin/LICENSE"
}
PKGBUILD

echo "== 4/4 makepkg =="
cd "$P"
makepkg -f --nodeps
ls -lh "$P"/*.pkg.tar.zst | sed 's/^/  /'

# /tmp 是 tmpfs，重启就没了 —— 成品包也拷进归档目录
cp -f "$P"/*.pkg.tar.zst "$OUT/"
echo "  成品包已拷到归档目录"
echo
echo "产物目录: $P"
echo "归档副本: $OUT"
