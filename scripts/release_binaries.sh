#!/usr/bin/env bash
# 把 dist/ 里已经构建好的 pacman 包，反向打成通用 tar.gz，发到旧仓库的 Release。
# 用途：pacman 用户走 tc1911.github.io/tc191-pkgs；其它发行版/其它机器可以下这里的
#       tar.gz，`sudo tar xzf xxx.tar.gz -C /` 就装好了（内容就是包里的 usr/ 树）。
#
# 用法：
#   bash scripts/release_binaries.sh              # 默认 TAG=v0.2.0
#   TAG=v0.3.0 bash scripts/release_binaries.sh   # 换版本
#   COMPRESSOR=pigz bash scripts/release_binaries.sh   # 装过 pigz 会快很多
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DIST=${DIST:-$REPO_DIR/dist}
REPO=${REPO:-tc1911/vtb-pkgs}          # 旧仓库
TAG=${TAG:-v0.2.0}
COMPRESSOR=${COMPRESSOR:-gzip}
OUT=${OUT:-/tmp/vtb-bin-tarballs}

# github.com 直连不通，gh 必须走代理（与本会话里其它 gh 调用保持一致）
export HTTPS_PROXY=${HTTPS_PROXY:-http://127.0.0.1:7890}
export HTTP_PROXY=${HTTP_PROXY:-http://127.0.0.1:7890}
export NO_PROXY=${NO_PROXY:-127.0.0.1,localhost}
gh auth status >/dev/null 2>&1 || { echo "gh 未登录或代理不通 —— 先 gh auth login"; exit 1; }

[ -d "$DIST" ] || { echo "找不到 $DIST —— 先跑 scripts/release_github.sh"; exit 1; }
command -v zstd >/dev/null || { echo "缺 zstd（sudo pacman -S zstd）"; exit 1; }
command -v "$COMPRESSOR" >/dev/null || COMPRESSOR=gzip

rm -rf "$OUT"; mkdir -p "$OUT"
echo "=== 打包目录: $OUT  压缩器: $COMPRESSOR ==="

shopt -s nullglob
n=0
for pkg in "$DIST"/*.pkg.tar.zst; do
  base=${pkg##*/}
  name=${base%-x86_64.pkg.tar.zst}
  case "$name" in *corresponding-source*|*src*) continue;; esac
  work=$(mktemp -d)
  tar --zstd -xf "$pkg" -C "$work"
  # 去掉 pacman 自己的元数据，只留真正安装的文件树
  rm -f "$work"/.PKGINFO "$work"/.BUILDINFO "$work"/.MTREE "$work"/.INSTALL
  tar -C "$work" --use-compress-program="$COMPRESSOR" -cf "$OUT/$name-x86_64.tar.gz" .
  rm -rf "$work"
  echo "  ✓ $name-x86_64.tar.gz"
  n=$((n+1))
done
[ "$n" -gt 0 ] || { echo "dist/ 里没有 .pkg.tar.zst"; exit 1; }

echo
echo "=== 产出 ==="
ls -lh "$OUT" | sed 's/^/  /'

# 自检：每个 tar.gz 能不能列出来、里面有没有 usr/
for f in "$OUT"/*.tar.gz; do
  tar -tzf "$f" | grep -q '^\./usr/' || { echo "!! $f 里没有 ./usr/ —— 打包异常"; exit 1; }
done
echo "  ✓ 自检通过（都含 ./usr/ 文件树）"

if [ "${SKIP_UPLOAD:-0}" = 1 ]; then
  echo; echo "SKIP_UPLOAD=1，未上传。"; exit 0
fi

echo
echo "=== 上传到 $REPO 的 Release ($TAG) ==="
NOTES=$(mktemp)
{
cat <<'EOF'
可直接解包的 Linux 二进制 tar.gz。

内容就是对应 pacman 包里的 `usr/` 文件树，不经过包管理器直接装：

```bash
sudo tar xzf <文件>.tar.gz -C /
```

注意：这样装不会登记到 pacman 数据库（升级/卸载要走 pacman 源）。

### 文件

EOF
for f in "$OUT"/*.tar.gz; do printf '* `%s` (%s)\n' "${f##*/}" "$(du -h "$f" | cut -f1)"; done
cat <<'EOF'

### Arch 用户请直接用 pacman 源

能自动处理依赖和升级：

```ini
[tc191]
SigLevel = Optional TrustAll
Server = https://tc1911.github.io/tc191-pkgs/
```
EOF
} > "$NOTES"
cat "$NOTES" | sed 's/^/  | '

gh release create "$TAG" --repo "$REPO" \
  --title "Linux 二进制归档 $TAG" \
  --notes-file "$NOTES" \
  "$OUT"/*.tar.gz

rm -f "$NOTES"
echo
echo "=== 验证下载地址 ==="
# 代理在脚本开头已导出，gh / curl 都靠它
for f in "$OUT"/*.tar.gz; do
  u="https://github.com/$REPO/releases/download/$TAG/${f##*/}"
  code=$(curl -sIL -o /dev/null -w '%{http_code}' "$u" || echo ERR)
  echo "  $code  ${f##*/}"
done
