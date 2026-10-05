# 2026-10-05 — psd2live 升到 2.0.4、open-vt 跟进上游、Auto_Vtb 退役

本次是一个大版本：psd2live 从 0.7.1 跳到 2.0.4（上游自带 MCP，于是下架了下游包 `auto-vtb-bin`），
open-vt 跟进上游 `89f2f0f`（VRM/XR 追踪大改），并重新生成了 GPL 对应源码。

## 包一览

| 包 | 上游 | 版本 | 说明 |
|---|---|---|---|
| `open-vt-bin` | [erodozer/open-vt](https://github.com/erodozer/open-vt) | `0.1.0.r15.89f2f0f-2` | 原生 VTuber 应用（Godot + ayagami 直接解析 moc3）。含桌面项与两个 systemd 用户单元 |
| `openseeface` | [emilianavt/OpenSeeFace](https://github.com/emilianavt/OpenSeeFace) | `1.20.5-2` | 面捕后端，提供 `/usr/bin/facetracker`（模型随包） |
| `psd2live-bin` | [tsunehimatoi/psd2live](https://github.com/tsunehimatoi/psd2live) | `2.0.4.r1.506156c-1` | PSD → Live2D 的 GUI（Compose Desktop 自带 JRE；内置 MCP 服务监听 `127.0.0.1:23871`） |
| `bililive` | — | `0.1.0-1` | Bilibili 直播弹幕 TUI 客户端（Rust 重写版） |
| `open-frp-cross-platform-launcher` | [ZGIT-Network/OpenFrp-CrossPlatformLauncher](https://github.com/ZGIT-Network/OpenFrp-CrossPlatformLauncher) | `0.9.1-1` | 跨平台 frpc 启动器（重打包上游 deb） |

**已下架：`auto-vtb-bin`（2026-10-05）。** Auto_Vtb 是 psd2live 的下游衍生版，
选它的唯一理由是内置 MCP 服务；psd2live 2.0 上游已内置 MCP（26 个工具），
改用上游，不再维护下游包。配方目录已删除，`pacman -Syu` 会把它从源上带走。

## 安装

```bash
# 追加到 /etc/pacman.conf 末尾
[tc191]
SigLevel = Optional TrustAll
Server = https://tc1911.github.io/tc191-pkgs/

# 整体更新（别只 -Sy）
sudo pacman -Syu

# 安装
sudo pacman -S open-vt-bin openseeface psd2live-bin
```

`SigLevel = Optional TrustAll` 是因为这个仓库不做 gpg 签名。请只在你信任本仓库内容的前提下使用。

## 校验

每个发布都带 `SHA256SUMS`，覆盖全部 `.pkg.tar.zst` 以及 psd2live 的对应源码归档：

```bash
cd /var/cache/pacman/pkg   # 或你下载的目录
sha256sum -c SHA256SUMS
```

## 许可与对应源码

| 上游 | 许可 | 是否修改上游 |
|---|---|---|
| open-vt | MIT（含 Godot 引擎 MIT）+ `license/` 下四个第三方许可 | 否 |
| OpenSeeFace | BSD-2（代码**与模型**）+ `Licenses/` 下 12 个第三方库许可 | 否 |
| psd2live | GPL-3.0-only | **是，2 行** |
| OpenFrp-CrossPlatformLauncher | Apache-2.0 + Commons Clause（**仅限非商业**） | 否（重打包 deb） |

`psd2live-bin` 不是上游原样二进制：构建时工作树相对 `v2.0.4`（`506156c`）有 2 处改动 ——
`Moc3RenderOrderLowering.kt` 的 ArtMesh 叶子 `groupIndex`（`0` → `-1`，不改 OpenVT 会拒载模型）、
`gradle-wrapper.properties` 的下载镜像（只影响构建速度）。
（0.7.1 时代还需要改 `RigBuilder.kt` 与 `gradlew` 权限位，2.0.4 上游已自洽，不需要了。）

按 GPL-3 第 6 条，同时提供**对应源码**：

```
psd2live-2.0.4.r1.506156c-corresponding-source.tar.zst
```

内含 `git archive 506156c` 的完整源码树 + 覆盖上述改动后的文件 + 补丁副本 +
`README-corresponding-source.txt`（上游地址、基准提交、改动清单、重建命令）。

各包的许可证都装到 `/usr/share/licenses/<pkgname>/`。

> 本仓库不包含任何 Live2D 模型。OpenVT 上游声明它是 *"built in Godot with entirely open source
> solutions"*，未链接 Cubism SDK，因此不涉及 Live2D 的 SDK 授权条款。

## psd2live 2.0 的两点变化

1. **内置 MCP**：GUI 起来后 `127.0.0.1:23871/mcp`，`asset` / `skeleton` / `swing` / `export` 等 26 个工具。
   token 从 `~/.java/.userPrefs/io/github/psd2live/agent/prefs.xml` 取。
2. **尾巴摆动要建骨架**：CLI 管道（`--input`）不建骨架，出的模型只有约 20 个参数、没有尾巴；
   要 `ParamTail1..4` / `ParamSkelTailSwing` 和摆锤链，必须走 GUI/MCP 的 `skeleton auto`。
   这是上游行为，不是本包的改动。

## 已知坑

1. **`/usr/bin/openvt` 已被 `kbd` 包占用**（kbd 的虚拟终端工具）。所以这里的命令叫 **`open-vt`**，
   包名是 `open-vt-bin` —— 不能叫 `openvt`，否则 pacman 会以文件冲突拒绝安装整批包。
2. **先删掉用户级遮蔽**，否则装的包不生效：
   ```bash
   rm -f ~/.local/bin/openvt
   rm -f ~/.local/share/applications/openvt.desktop
   rm -f ~/.config/systemd/user/openvt.service ~/.config/systemd/user/openseeface.service
   systemctl --user daemon-reload
   ```
3. **`openseeface` 的依赖名是 `python-onnxruntime-cpu`**。官方仓库没有 `python-onnxruntime`
   （那是 AUR 包），写错会让 `pacman -U` 直接拒绝。
4. `open-vt-bin` 的 `optdepends` 指向 `openseeface-git`（AUR）。本仓库的 `openseeface` 包
   `provides`/`conflicts` 了它，两者装一个即可。

## 从源码重建

```bash
./open-vt-bin/make_openvt_pkg.sh      # 需要一份已编译的 OpenVT 构建树
./psd2live-bin/make_psd2live_pkg.sh   # 需要 psd2live 2.0.4 源码树 + gradle（先 createDistributable）
cd openseeface && makepkg -f
./scripts/release_github.sh           # 汇总 dist/ + repo-add + 生成对应源码 + SHA256SUMS
./scripts/publish_pages.sh            # 推 gh-pages
```
