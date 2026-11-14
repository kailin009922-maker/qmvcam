# 千面 VCam · 自编译版（iOS 16 – 26）

基线：`【发这个】千面摇杆_iOS15-17.3_98d.deb`（vendor 98d 二进制）
产出：`com.taokk3.qianmian_3.0.0-src_{roothide,rootless}.deb` —— 由本仓库源码编译，**不是**对原 deb 的换签。

---

## 1. 与原包（98d）的对应关系

| 维度 | 98d 原包 | 本仓库 3.0.0 |
|---|---|---|
| 注入进程 | mediaserverd / SpringBoard | 同上 + `cameracaptured`（iOS 18+ 相机守护进程） |
| 帧替换 | 原地改写真实相机 `CVPixelBuffer` | 同一手法（`-[QMCore processSampleBuffer:]`） |
| 钩点 | `BWNodeOutput.emitSampleBuffer:` 等 12 处 | 同名钩点，全部 `objc_getClass` 运行时探测 |
| UI | 悬浮球 + 摇杆 + 六键 + 三页面板 | 悬浮球 + 摇杆 + 六键（▲▼◀▶＋－）+ 三页 |
| 配置 | `/DCIM/vc.plist`、`/DCIM/vc.lighting.plist`、槽位 `/DCIM/2`、`/DCIM/4` | **键名/路径/通知名全沿用**，老配置可直接用 |
| 授权 | ECDSA P-256，公钥指纹 `556D71361578ED37` | **同一把公钥、同一格式**，你现有 `千面_发卡器.exe` 出的码直接可用 |
| 打光 | Metal kernel（内嵌 MSL） | 同数学结构 kernel；原 MSL 原文见 `shaders_original.metal` |
| minos | 15.0 | **16.0**（iOS 16–26） |
| 架构 | arm64 + arm64e | arm64（arm64e 设备可正常加载；LLD 暂不支持 arm64e 重定位） |

## 2. 授权（已对齐你的发卡器）

- 公钥：`src/vcam_license.m` 里的 65 字节未压缩点，与 `千面_发卡器.exe` 私钥配对
  （`SHA256(pub)[0:8] = 556D71361578ED37`，`--keyinfo` 同值）。
- 激活码格式（与 98d / 你的发卡器一致，已用真码回验）：

```
code    = base64( payload(65B) | sigLen(1B) | DER sig )
payload = [0]=0x01 | [1:17) 指纹16B | [17:21) 到期u32LE(0=永久)
          | [21:25) 功能位u32LE | [25:65) 40B 随机/运行密钥
签名覆盖前 65 字节；长度校验 = 66 + sigLen
```

- 授权文件：`/var/mobile/Media/DCIM/vc_license.txt`（明文，≤184 字符）。
- 设备指纹：`SHA256(IOPlatformUUID|Serial|ChipID)[0:16]`，小写 hex，面板「复制指纹」直接给买家。

发码（PC）：

```powershell
.\千面_发卡器_CLI.exe --issue <32位指纹> 30 7
.\千面_发卡器_CLI.exe --verify <激活码>
```

## 3. 构建

### Windows（本机已验证）

```powershell
# 依赖：C:\Program Files\LLVM\bin\clang.exe（含 ld64.lld）、..\qm\toolchain\iPhoneOS16.5.sdk
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Arch arm64
python tools\mkdeb.py build\qmvcam-arm64.dylib dist
```

产物：`dist/` 两支 deb（单目录 payload，不含 pkgmirror —— 双份 dylib 在 roothide 下会白苹果）。

### Theos

```bash
make package     # ARCHS = arm64 arm64e（arm64e 需 Xcode 的 ld64）
```

## 4. 目录

```
qm-vcam/
├─ Makefile / control / layout/…/qmvcam.plist
├─ build.ps1                      # Windows 一键构建
├─ shaders_original.metal         # 从 98d 二进制提取的原始 MSL（0xcfd02）
├─ src/
│  ├─ vcam_common.h               路径/通知/键名/接口
│  ├─ vcam_state.m                rootless 前缀 + vc.plist / vc.lighting.plist
│  ├─ vcam_source.m/.h            图片/视频 → 连续 BGRA 帧（AVAssetReader 循环）
│  ├─ vcam_core.m                 帧替换核心 + 池 + 快路径 + 文件监听
│  ├─ vcam_hooks.m                mediaserverd / cameracaptured 钩子
│  ├─ vcam_ui.m                   悬浮球 / 摇杆 / 六键 / 三页 / 授权 UI
│  ├─ vcam_license.m              66B 载荷 + DER 验签（你的公钥）
│  ├─ vcam_lighting.m             Metal 人脸补光 + 屏幕取色
│  ├─ vcam_notify.m               Darwin 通知 + 状态轮询
│  ├─ main.m                      进程分流
│  └─ shim/IOKit/*.h              SDK 缺 IOKit 头的补齐
└─ tools/
   ├─ mkdeb.py                    打 deb（单目录 payload）
   ├─ makefat.py                  合并 fat
   ├─ check_sign.py               逐页校验 ad-hoc 签名
   └─ keygen.py                   备用密钥生成（当前用的是你的公钥，不需要跑）
```

## 5. iOS 16 – 26 做了什么

1. `minos = 16.0`，SDK 16.5 编译；只用到 iOS 16.0 就有的 API。
2. 私有类全部运行时探测（`objc_getClass` + `class_getInstanceMethod`），iOS 18 新增的
   `cameracaptured` 也纳入注入面；某个类改名只会降级，不会整体失效。
3. rootless：`QMRoot()` 探测 `/var/jb`，`/Library`、`/usr` 前缀自动补；`/var/mobile` 不动。
4. roothide：不依赖 `.jbroot` rpath（本 dylib 不链 CydiaSubstrate，`MSHookMessageEx` 走动态查找）。
5. 帧管线优化：同尺寸同格式且无编辑时走**逐行直拷快路径**，跳过 CIImage 渲染；
   池化目标 buffer 按相机格式复用；解码在独立队列、按 fps 节流，落后丢帧不堆积。
6. 媒体文件监听：inode/mtime/size 变化即重载（对齐 98d 的「换文件立即生效」）。

## 6. 回滚

```bash
dpkg -r com.taokk3.qianmian
killall -9 SpringBoard mediaserverd cameracaptured
```
