#!/usr/bin/env bash
# 把 dist/ 里已经构建好的 pacman 包，反向打成通用 tar.gz，发到归档仓库（tc1911/vtb-bin）的 Release。
# 用途：pacman 用户走 tc1911.github.io/tc191-pkgs；其它发行版/其它机器可以下这里的
#       tar.gz，`sudo tar xzf xxx.tar.gz -C /` 就装好了（内容就是包里的 usr/ 树）。
#
# 用法：
#   bash scripts/release_binaries.sh              # TAG 默认 = v<UTC 日期>，如 v2026.09.21
#   TAG=v0.3.0 bash scripts/release_binaries.sh   # 显式指定版本号
#   COMPRESSOR=pigz bash scripts/release_binaries.sh   # 装过 pigz 会快很多
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DIST=${DIST:-$REPO_DIR/dist}
REPO=${REPO:-tc1911/vtb-bin}           # 归档仓库
# TAG 默认按 UTC 日期归档：同一天重跑会复用同一个 Release（幂等），跳天自动另起。
# 不要写死一个固定 tag —— 那样新包只会 --clobber 覆盖掉历史版本，归档就白做了。
TAG=${TAG:-v$(date -u +%Y.%m.%d)}
COMPRESSOR=${COMPRESSOR:-gzip}
OUT=${OUT:-/tmp/vtb-bin-tarballs}

# github.com 直连不通，gh 必须走代理（与本会话里其它 gh 调用保持一致）
export HTTPS_PROXY=${HTTPS_PROXY:-http://127.0.0.1:7890}
export HTTP_PROXY=${HTTP_PROXY:-http://127.0.0.1:7890}
export NO_PROXY=${NO_PROXY:-127.0.0.1,localhost}
# 代理会偶发抖动，一次不过就放弃太脆 —— 探测三次
for i in 1 2 3; do
  gh auth status >/dev/null 2>&1 && break
  echo "  gh 探测失败（第 $i 次），3 秒后重试…"; sleep 3
done
gh auth status >/dev/null 2>&1 || { echo "gh 未登录或代理不通 —— 先 gh auth login"; exit 1; }

[ -d "$DIST" ] || { echo "找不到 $DIST —— 先跑 scripts/release_github.sh"; exit 1; }
command -v zstd >/dev/null || { echo "缺 zstd（sudo pacman -S zstd）"; exit 1; }
command -v "$COMPRESSOR" >/dev/null || COMPRESSOR=gzip

mkdir -p "$OUT"
OUTPUTS=()   # 只收录 dist/ 里真有对应包的那几个，$OUT 里的陈年残体不会被发出去
echo "=== 打包目录: $OUT  压缩器: $COMPRESSOR ==="

shopt -s nullglob
n=0
for pkg in "$DIST"/*.pkg.tar.zst; do
  base=${pkg##*/}
  name=${base%-x86_64.pkg.tar.zst}
  case "$name" in *corresponding-source*|*src*) continue;; esac
  # 已经打过而且能完整解包就跳过：mtime 不可靠（发布流程用 install 会刷新包的 mtime，
  # 那样每次都重压 6 分钟），用“存在 + tar 能列”当判决，需要重打时 FORCE_REBUILD=1
  out="$OUT/$name-x86_64.tar.gz"
  if [ -f "$out" ] && [ -z "${FORCE_REBUILD:-}" ] && tar -tzf "$out" >/dev/null 2>&1; then
    echo "  ↻ $name-x86_64.tar.gz 已存在且可解包，跳过"
    OUTPUTS+=("$out")
    n=$((n+1)); continue
  fi
  work=$(mktemp -d)
  tar --zstd -xf "$pkg" -C "$work"
  # 去掉 pacman 自己的元数据，只留真正安装的文件树
  rm -f "$work"/.PKGINFO "$work"/.BUILDINFO "$work"/.MTREE "$work"/.INSTALL
  tar -C "$work" --use-compress-program="$COMPRESSOR" -cf "$OUT/$name-x86_64.tar.gz" .
  rm -rf "$work"
  echo "  ✓ $name-x86_64.tar.gz"
  OUTPUTS+=("$OUT/$name-x86_64.tar.gz")
  n=$((n+1))
done
[ "$n" -gt 0 ] || { echo "dist/ 里没有 .pkg.tar.zst"; exit 1; }

# GPL-3 的对应源码（Corresponding Source）也要走这条通道一起发：
# 只分发 GPL 二进制、不提供源码是不合规的。直接当附件传，不再重新包装。
SRC_ASSETS=()
for f in "$DIST"/*corresponding-source.tar.zst; do
  SRC_ASSETS+=("$f")
done
if [ ${#SRC_ASSETS[@]} -gt 0 ]; then
  echo "  含对应源码附件 ${#SRC_ASSETS[@]} 个"
fi

echo
echo "=== 产出 ==="
ls -lh "$OUT" | sed 's/^/  /'

# 自检：每个 tar.gz 能不能完整列出、里面有没有 usr/
# 不要写成 `tar -tzf "$f" | grep -q ...`：grep -q 找到即退，tar 接着写会吃 SIGPIPE，
# 在 `set -o pipefail` 下整条管道判失败 —— 会误报“打包异常”（踩过）。
for f in "${OUTPUTS[@]}"; do
  listing=$(tar -tzf "$f") || { echo "!! $f 解不开（tar 报错）"; exit 1; }
  case "$listing" in
    *"./usr/"*) ;;
    *) echo "!! $f 里没有 ./usr/ —— 打包异常"; exit 1 ;;
  esac
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
for f in "${OUTPUTS[@]}"; do printf '* `%s` (%s)\n' "${f##*/}" "$(du -h "$f" | cut -f1)"; done
cat <<'EOF'

### Arch 用户请直接用 pacman 源

能自动处理依赖和升级：

```ini
[tc191]
SigLevel = Optional TrustAll
Server = https://tc1911.github.io/tc191-pkgs/
```
EOF
if [ ${#SRC_ASSETS[@]} -gt 0 ]; then
cat <<'EOF'

### 对应源码（GPL-3 第 6 条）

`psd2live-bin` 构建时的源码相对上游有改动，按 GPL-3 必须随二进制一同提供 Corresponding Source：

EOF
for f in "${SRC_ASSETS[@]}"; do printf '* `%s` (%s)\n' "${f##*/}" "$(du -h "$f" | cut -f1)"; done
fi
} > "$NOTES"
cat "$NOTES" | sed 's/^/  | /'

# 幂等：Release 已存在就复用，再 --clobber 覆盖上传（重跑不会卡在“已存在”）
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 \
  || gh release create "$TAG" --repo "$REPO" --title "Linux 二进制归档 $TAG" --notes-file "$NOTES"
# 已存在的 Release 也要刷新说明（否则新加的包不会出现在描述里）
gh release edit "$TAG" --repo "$REPO" --notes-file "$NOTES"
# 只传 Release 里缺的（或大小对不上的），避免每次发布重传几百 MB
EXISTING=$(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[] | "\(.name) \(.size)"' 2>/dev/null || true)
# 二进制 tar.gz 和对应源码都要发
ALL_ASSETS=("${OUTPUTS[@]}")
if [ ${#SRC_ASSETS[@]} -gt 0 ]; then ALL_ASSETS+=("${SRC_ASSETS[@]}"); fi
UPLOAD=()
for f in "${ALL_ASSETS[@]}"; do
  n=${f##*/}; sz=$(stat -c%s "$f")
  if grep -qxF "$n $sz" <<< "$EXISTING"; then
    echo "  = $n 已在 Release 且大小一致，跳过上传"
  else
    UPLOAD+=("$f")
  fi
done
if [ ${#UPLOAD[@]} -gt 0 ]; then
  gh release upload "$TAG" --repo "$REPO" --clobber "${UPLOAD[@]}"
else
  echo "  没有需要上传的文件"
fi

rm -f "$NOTES"
echo
echo "=== 验证下载地址 ==="
# 代理在脚本开头已导出，gh / curl 都靠它
for f in "${ALL_ASSETS[@]}"; do
  u="https://github.com/$REPO/releases/download/$TAG/${f##*/}"
  code=$(curl -sIL -o /dev/null -w '%{http_code}' "$u" || echo ERR)
  echo "  $code  ${f##*/}"
done
