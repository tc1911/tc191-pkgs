# tc191-pkgs

tc1911 的个人 Arch Linux 软件源。

**仓库本身只存配方**（PKGBUILD、构建脚本、补丁）；打包好的二进制放在
[GitHub Release](https://github.com/tc1911/tc191-pkgs/releases) 里直接当 pacman 源用。

## 客户端接入

`/etc/pacman.conf` 末尾加：

```ini
[tc191]
SigLevel = Optional TrustAll
Server = https://github.com/tc1911/tc191-pkgs/releases/latest/download
```

然后：

```bash
sudo pacman -Sy
sudo pacman -S open-vt-bin        # 例如
```

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
bash scripts/release_github.sh          # 生成 dist/ 里的全部发布资源并自校验
```

脚本会：收集三个包 → `repo-add` 生成仓库索引 → 校验索引里的 SHA256/CSIZE 与实际文件一致
→ 生成 GPL 义务要求的 corresponding-source → 写 `SHA256SUMS`，最后打印两条上传路线
（`gh release create` 或网页拖拽）。

### 数据库文件名

由 `DBNAME` 控制，默认 `tc191`：

```bash
DBNAME=vtb bash scripts/release_github.sh   # 切回旧名（客户端 [节名] 与 Server 要同步改）
```

### 两个容易踩的坑

- **GitHub Release 不能存符号链接**，而 `repo-add` 产出的 `<db>.db` / `<db>.files` 是指向
  `.tar.gz` 的软链 → 脚本额外做了一份实体副本，两个都要上传，否则 pacman 报错。
- pacman 会先找 `<db>.db`，找不到才回落 `<db>.db.tar.gz`。
