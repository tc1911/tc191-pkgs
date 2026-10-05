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
| `psd2live-bin` | psd2live：PSD → Live2D 自动绑定的桌面版（2.0 起上游自带 MCP，**自带 JRE**）|
| `bililive` | Bilibili 直播弹幕 TUI 客户端，Rust 重写版（弹幕 / 扫码登录 / 分区 / 开播取推流码 / OBS 联动）|
| `open-frp-cross-platform-launcher` | [OpenFrp CPL](https://github.com/ZGIT-Network/OpenFrp-CrossPlatformLauncher) 跨平台 frpc 启动器（Rust + Tauri 2）。重打包上游 `.deb`，**许可证是 Apache-2.0 + Commons Clause，仅限非商业** |

> `bilibili-live-tui-plus`（Go 版）2026-10-03 起停更，被 `bililive` 取代：
> 配方留在目录里当参照物，产物不再进源（`pacman -Syu` 会把这个包从源上带走）。
>
> `auto-vtb-bin` 2026-10-05 起下架：Auto_Vtb 是 psd2live 的下游衍生版，选它的唯一理由是内置
> MCP 服务；psd2live 2.0（`psd2live-bin`）上游已内置 MCP，改用上游，不再维护下游包。
> 配方目录已删除，产物留在归档处。

补丁明细见 `docs/PATCHES.md`。

## 构建

每个包各自独立，产物都是 `.pkg.tar.zst`：

```bash
bash open-vt-bin/make_openvt_pkg.sh     # → /home/tc191/vtb/归档/open-vt-bin/
bash psd2live-bin/make_psd2live_pkg.sh  # → /home/tc191/vtb/归档/psd2live-bin/
bash bililive/make_bililive_pkg.sh      # → /home/tc191/vtb/归档/bililive/（GitHub 上得先有对应 tag）
bash open-frp-cross-platform-launcher/make_openfrp_pkg.sh  # → /home/tc191/vtb/归档/open-frp-cross-platform-launcher/（重打包上游 deb）
cd openseeface && makepkg -f            # → /home/tc191/opt/openvt-pkg/openseeface/
```

## 发布

```bash
bash scripts/publish_pages.sh           # 生成 dist/ → 推 gh-pages → 打印源地址并自验
bash scripts/publish_pages.sh --no-build # 直接用现有 dist/
```

`publish_pages.sh` 会先调 `release_github.sh`：收集 `PKGDIRS` 里每个产包目录的 `.pkg.tar.zst` → `repo-add` 生成仓库索引 →
校验索引里的 SHA256/CSIZE 与实际文件一致 → 生成 GPL 义务要求的 corresponding-source
→ 写 `SHA256SUMS`；然后把这一整套推到 `gh-pages` 分支（滚动 `--force` 覆盖）。

首次发布后要去仓库 Settings → Pages 确认源是 `gh-pages` 分支根目录（通常会自动识别）。

### 数据库文件名

由 `DBNAME` 控制，默认 `tc191`：

```bash
DBNAME=vtb bash scripts/release_github.sh   # 切回旧名（客户端 [节名] 与 Server 要同步改）
```

### 二进制 tar.gz：发到归档仓库的 Release

pacman 只服务 Arch。其它发行版 / 其它机器需要的是「能直接解包的 tar.gz」，
这份归档发在归档仓库 `tc1911/vtb-bin` 的 Release 里（那是归档位，不当软件源用）：

```bash
bash scripts/release_binaries.sh               # TAG 默认 = v<UTC 日期>，如 v2026.09.21
TAG=v0.3.0 bash scripts/release_binaries.sh    # 显式指定版本号
```

它**不重新编译**，只把 `dist/` 里已构建的 `.pkg.tar.zst` 拆开、丢掉 pacman 自己的元数据
（`.PKGINFO` / `.BUILDINFO` / `.MTREE` / `.INSTALL`），把剩下的 `usr/` 树重新压成 `.tar.gz`，
建 Release 并上传，最后验证下载地址返回 200：

```bash
sudo tar xzf open-vt-bin-*.tar.gz -C /     # 装法（不进 pacman 数据库）
```

> `github.com` 直连不通，脚本开头就把 `HTTPS_PROXY` 导出了（`gh` 和 `curl` 都靠它）；
> 想换压缩器：`COMPRESSOR=pigz bash scripts/release_binaries.sh`（装过 pigz 快很多）。

> **TAG 的语义**：默认按 UTC 日期归档 —— 同一天重跑复用同一个 Release（幂等），跳天自动另起，
> 所以新包不会 `--clobber` 掉历史归档；要往某个旧 Release 里补东西就显式 `TAG=v0.2.0`。
>
> **对应源码一起发**：`dist/` 里的 `*corresponding-source.tar.zst` 不参与拆包，直接当 Release 附件上传，
> 并在说明里单列一节（GPL-3 第 6 条义务）。

#### 产物去向

| | 放什么 | 为什么 |
|---|---|---|
| **本仓库** `tc191-pkgs` | 配方 + `gh-pages` 上的包 | 配方要跟代码一起演进；产物滚动覆盖，不堆 Release |
| **归档仓库**（Release 附件）| 通用 tar.gz + GPL 对应源码 | 二进制不进 git 历史；非 Arch 用户拿 tar.gz 就能解包 |

归档仓库只是可选的第二条通道，Github slug 由 `REPO=` 决定（默认 `tc1911/vtb-bin`）：

```bash
REPO=tc1911/别的仓库 bash scripts/release_binaries.sh   # 想发去别处就覆盖
```

### 两个容易踩的坑

- **GitHub Release 不能存符号链接**，而 `repo-add` 产出的 `<db>.db` / `<db>.files` 是指向
  `.tar.gz` 的软链 → 脚本额外做了一份实体副本，两个都要上传，否则 pacman 报错。
- pacman 会先找 `<db>.db`，找不到才回落 `<db>.db.tar.gz`。
