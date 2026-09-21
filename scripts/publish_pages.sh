#!/usr/bin/env bash
# 把 dist/ 里的包发布成 pacman 源（走 GitHub Pages 的 gh-pages 分支）。
#
# 为什么不用 GitHub Release：Release 页面是用来放「版本说明+附件」的，
# 当软件源用会把附件区堆成一堆二进制，乱；而且每次发版都在仓库里多存一份。
# Pages 直接当静态源更干净，地址也稳定。
#
# 分支是**滚动覆盖**的（--force），所以仓库体积不会随发版增长，
# 始终只有当前这一批包的大小。
#
# 用法: bash scripts/publish_pages.sh [--no-build]
#   --no-build  直接用现有 dist/，不重新生成
set -euo pipefail

DBNAME="${DBNAME:-tc191}"
# 仓库根目录从脚本自身位置推导（本脚本在 <root>/scripts/ 下），搬目录不用改脚本
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE=git@github.com:tc1911/tc191-pkgs.git
DIST="$REPO/dist"
PAGES="https://tc1911.github.io/tc191-pkgs"

[ "${1:-}" = "--no-build" ] || bash "$REPO/scripts/release_github.sh"

# 在独立临时目录里建分支，完全不碰 main 的工作区
B=$(mktemp -d /tmp/pkgs-publish.XXXXXX)
trap 'rm -rf "$B"' EXIT
cp -p "$DIST"/* "$B/"
touch "$B/.nojekyll"   # 不加这个，Pages 会拿 Jekyll 处理这个纯二进制镜像站

{
	cat <<HTML
<!doctype html><meta charset=utf-8><title>${DBNAME}</title>
<style>body{font:14px/1.6 system-ui,sans-serif;max-width:52em;margin:3em auto;padding:0 1em}
code{background:#f2f2f2;padding:.1em .4em;border-radius:3px}li{margin:.2em 0}</style>
<h1>${DBNAME}</h1>
<p>tc1911 的个人 Arch Linux 软件源。</p>
<pre>[${DBNAME}]
SigLevel = Optional TrustAll
Server = ${PAGES}/</pre>
<p>然后是 <code>sudo pacman -Sy</code>。包列表见 <a href="${DBNAME}.db.tar.gz">${DBNAME}.db.tar.gz</a>，
校验见 <a href="SHA256SUMS">SHA256SUMS</a>。</p>
<h2>文件</h2><ul>
HTML
	for f in $(cd "$B" && ls *.pkg.tar.zst *.tar.zst *.db *.files SHA256SUMS 2>/dev/null | sort -u); do
		printf '  <li><a href="%s">%s</a> — %s</li>\n' "$f" "$f" "$(du -h "$B/$f" | cut -f1)"
	done
	echo '</ul><p><a href="https://github.com/tc1911/tc191-pkgs">源码与配方</a></p>'
} > "$B/index.html"

VER=$(cd "$B" && ls *.pkg.tar.zst | sed 's/^.*-\([0-9][^-]*-[0-9]*\)-x86_64.*/\1/' | tr '\n' ' ')
git -C "$B" init -q -b gh-pages
git -C "$B" add -A -f
git -C "$B" commit -q -m "发布包: $VER"
echo "== 推送 gh-pages（$(du -sh --exclude=.git "$B" | cut -f1)）=="
git -C "$B" push --force "$REMOTE" gh-pages 2>&1 | sed 's/^/  /'

echo
echo "================ 源地址 ================"
echo "  把 /etc/pacman.conf 里换成："
echo "    [${DBNAME}]"
echo "    SigLevel = Optional TrustAll"
echo "    Server = ${PAGES}/"
echo
echo "  验证（都应当是 200）："
for f in "${DBNAME}.db" "${DBNAME}.files" SHA256SUMS; do
	printf '    %-24s %s\n' "$f" "$(curl -s -o /dev/null -w '%{http_code}' "${PAGES}/${f}")"
done
