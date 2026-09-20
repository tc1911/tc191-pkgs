# tc191-pkgs

tc1911 的个人 Arch Linux 软件源。

**仓库本身只存配方**（PKGBUILD、构建脚本、补丁）；打包好的二进制放在
`gh-pages` 分支上，由 GitHub Pages 直接当 pacman 源提供。

## 客户端接入

`/etc/pacman.conf` 末尾加：

```ini
[tc191]
SigLevel = Optional TrustAll
Server = https://tc1911.github.io/tc191-pkgs/
```

然后：

```bash
sudo pacman -Syu
sudo pacman -S open-vt-bin        # 例如
```

> 不用 Release 当源：Release 的附件区是用来放「版本说明+附件」的，当软件源用会堆一屏二进制，
> 而且每次发版仓库里都多囤一份。`gh-pages` 分支是滚动覆盖的，体积不随发版增长。

## 里面的包

| 包 | 说明 |
|---|---|
| `open-vt-bin` | [OpenVT](https://github.com/erodozer/open-vt) 虚拟主播软件。打了补丁：虚拟摄像头输出、双摄支持 |
| `openseeface` | OpenSeeFace 面捕（facetracker） |
| `psd2live-bin` | psd2live：PSD → Live2D 自动绑定的桌面版 |

补丁明细见 `docs/PATCHES.md`。

## 构建

每个包各自独立，产物都是 `.pkg.tar.zst`：

```bash
bash open-vt-bin/make_openvt_pkg.sh     # → /home/tc191/vtb/归档/open-vt-bin/
bash psd2live-bin/make_psd2live_pkg.sh  # → /home/tc191/vtb/归档/psd2live-bin/
cd openseeface && makepkg -f            # → /home/tc191/opt/openvt-pkg/openseeface/
```

## 发布

```bash
bash scripts/publish_pages.sh           # 生成 dist/ → 推 gh-pages → 打印源地址并自验
bash scripts/publish_pages.sh --no-build # 直接用现有 dist/
```

`publish_pages.sh` 会先调 `release_github.sh`：收集三个包 → `repo-add` 生成仓库索引 →
校验索引里的 SHA256/CSIZE 与实际文件一致 → 生成 GPL 义务要求的 corresponding-source
→ 写 `SHA256SUMS`；然后把这一整套推到 `gh-pages` 分支（滚动 `--force` 覆盖）。

首次发布后要去仓库 Settings → Pages 确认源是 `gh-pages` 分支根目录（通常会自动识别）。

### 数据库文件名

由 `DBNAME` 控制，默认 `tc191`：

```bash
DBNAME=vtb bash scripts/release_github.sh   # 切回旧名（客户端 [节名] 与 Server 要同步改）
```

### 两个容易踩的坑

- **GitHub Release 不能存符号链接**，而 `repo-add` 产出的 `<db>.db` / `<db>.files` 是指向
  `.tar.gz` 的软链 → 脚本额外做了一份实体副本，两个都要上传，否则 pacman 报错。
- pacman 会先找 `<db>.db`，找不到才回落 `<db>.db.tar.gz`。
