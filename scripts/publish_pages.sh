#!/usr/bin/env bash
# 把 dist/ 里的包发布成 pacman 源（走 GitHub Pages 的 gh-pages 分支）。
#
# 为什么不用 GitHub Release：Release 页面是用来放「版本说明+附件」的，
# 当软件源用会把附件区堆成一堆二进制，乱；而且每次发版都在仓库里多存一份。
# Pages 直接当静态源更干净，地址也稳定。
#
# 提交叠在本地缓存的 gh-pages 之上（增量推送）：git 只传新增/变化的 blob。
# 以前是每次在 /tmp 里 init 一个全新历史再 --force 推，历史里没得比，每次都 355M 全量重传。
# 代价：远端历史会累积，仓库体积随发版增长（不变的 blob 会复用，涨得慢）。
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

# 增量发布：本地留一份 gh-pages 克隆做基底（放缓存目录，不碰 main 工作区），
# 新提交直接叠在远端 head 上，git 只传变化的 blob。
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/tc191-pkgs/gh-pages"
if [ -d "$CACHE/.git" ]; then
	git -C "$CACHE" fetch -q --force "$REMOTE" gh-pages
	git -C "$CACHE" reset -q --hard FETCH_HEAD
else
	mkdir -p "$(dirname "$CACHE")"   # git clone 不会替你建父目录
	git clone -q --branch gh-pages --single-branch "$REMOTE" "$CACHE" 2>/dev/null ||
		git -C "$CACHE" init -q -b gh-pages   # 远端还没有 gh-pages 分支时的降级
fi
# 镜像 dist/ 到工作区：先清掉旧的（保留 .git），再拷新的一批
find "$CACHE" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -p "$DIST"/* "$CACHE/"
touch "$CACHE/.nojekyll"   # 不加这个，Pages 会拿 Jekyll 处理这个纯二进制镜像站

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
	for f in $(cd "$CACHE" && ls *.pkg.tar.zst *.tar.zst *.db *.files SHA256SUMS 2>/dev/null | sort -u); do
		printf '  <li><a href="%s">%s</a> — %s</li>\n' "$f" "$f" "$(du -h "$CACHE/$f" | cut -f1)"
	done
	echo '</ul><p><a href="https://github.com/tc1911/tc191-pkgs">源码与配方</a></p>'
} > "$CACHE/index.html"

VER=$(cd "$CACHE" && ls *.pkg.tar.zst | sed 's/^.*-\([0-9][^-]*-[0-9]*\)-x86_64.*/\1/' | tr '\n' ' ')
git -C "$CACHE" add -A -f
if git -C "$CACHE" diff --cached --quiet; then
	echo "== 内容和远端一致，没什么可推的 =="
else
	git -C "$CACHE" commit -q -m "发布包: $VER"
	echo "== 推送 gh-pages（工作区 $(du -sh --exclude=.git "$CACHE" | cut -f1)，只传增量）=="
	git -C "$CACHE" push "$REMOTE" gh-pages 2>&1 | sed 's/^/  /'
fi

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
