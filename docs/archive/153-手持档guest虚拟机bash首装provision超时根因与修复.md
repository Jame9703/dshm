# 153 · 手持档 guest VM bash「首装 provision 超时」的根因与修复（一进程一 VM 闸门被毒化 · 权限面首次落到 8 条）

> 本轮用户原话：
>
> 「终端都起不来了，看下是什么问题」「不要修好一个坏一个」
> 「之前就写个侧边栏和无法创建工作目录这个事儿，就把原本好的终端给整坏了，你没想过为什么吗？」
>
> 前置硬口径（继续遵守）：
>
> 「后续都只做 release 的版本 …… 只做 release 且与 agc 上传的包一致，并且包里面都不要包含 apk 相关的文件。」
>
> 症状：手持档（手机 / 平板）与 **release 档的 PC** 上，**终端一直「正在启动」/ 打不开**。
> 改动面：核心树**只动 2 个文件**（`dshm-vm-bash/lib/{vm.js,qga.js}`）⇒ `coreVersion` 升
> `0.2.1-alpha.2+dshm.39`；宿主侧 ArkTS **一字未动**。

---

## 0. 一句话结论

| # | 问题 | 结论 | 依据 |
|---|---|---|---|
| 1 | 终端「一直正在启动」/ 打不开 | 真因在 **VM 层首装超时**，**不是**侧边栏补丁或「不再创建默认工作区」那两个改动弄坏的 | §1（真机读数差两个数量级）|
| 2 | 为什么「修好一个坏一个」 | 每轮改完都**卸载重装** ⇒ 每次都是**首装** ⇒ 首装 `apk add` 必然 > 120 s ⇒ 判死 + 闸门毒化，是一颗**长期潜伏的定时炸弹**，本轮到点引爆 | §2 |
| 3 | 修法 | `provision()` 按「这一段在干什么」**拆两段**（探测 30 s + 安装 600 s）；QGA 超时判死前 best-effort `kill -TERM` | §3 |
| 4 | 权限面 | 本件是**第一份「8 条权限」的正式侧载件**，且 `.app` 上架件同权限面、零 `.apk` | §4 / §5 |

---

## 1. 症状是真机读数，不是观感

**同一台手机**（`62T0225B18039433`，UA `Phone; OpenHarmony 7.0`）、**同一个端点**
`POST /api/terminal/create`，两次验收的读数差了两个数量级：

| 验收批次（日志原文） | 读数 |
|---|---|
| `dist/acceptance/20261011-044246/device-dshm-host.log` | `IN-DONE POST /api/terminal/create` **47,736 / 13,463 / 12,858 / 13,692 / 12,163 / 14,617 ms**（也有 546 ms 的快路径）|
| `dist/acceptance/20261013-204454/device-dshm-host.log` | `IN-DONE POST /api/terminal/create` **587 ms** / **266 ms** |

`terminal/create` 在手持档要**先确保 guest VM 就绪并完成 provision**（`/bin/bash` 在不在），
所以这个端点耗时就是「VM 侧到底顺不顺」的代理读数。

### 1.1 为什么**不是**那两个 ArkTS 改动弄坏的

那两处的改动面与终端链路**不相交**，而且都改不出上面这种读数：

- **「不再创建默认工作区」**：只改自带插件 `dsh-client-ui-workspace` 的 `catch` 体 —— 把
  `this.notify({kind:"defaultWorkspaceFailed"})` 换成 `return`。**不建会话、不改注册表、不阻断启动**。
- **侧边栏**：全是 ArkTS / Web 层注入（`entry/src/main/ets/pages/WebApp.ets` 的垫片 +
  `entry/src/main/resources/base/media/sidebar_toggle.svg`），`hostcore/**` 与核心树一字未动。

而终端坏的现场证据**只可能来自 VM 层**：`terminal/create` 单次 **13~48 s**、
旧代码里那条**一整段 120 s** 的 provision 超时。UI 层改不出这些读数。

---

## 2. 根因

### 2.1 一整段 120 s 把「已经装成功」的首装判死

旧实现把三件事压在**同一次 `exec`、同一个 120 s 上限**里：

1. 挂 9p 共享（幂等）；
2. 建 `EL2_FILES` 符号链接；
3. `apk add` 离线装 `bash`。

而**首装**（随包闭包刚解出、guest 镜像里还没有 bash）的 `apk add` 在**真机上就能超过 120 s**。
PC 真机实证（源码注释原文，`vm.js:75-79`）：

> 这台 PC 上 rootfs 其实装成了（**48631808 → 54087680 B**、`/bin/bash` 后来可执行），命令却已按超时判死。

即：**探测（快路径）只要 ~200 ms，而安装段是分钟级** —— 把两者绑在同一个时限上，
等于让慢路径去决定快路径的时限。

### 2.2 更重的后果：一进程一 VM 的闸门被**永久**毒化

`dshm-vm-bash` 有一条硬闸门 `startGate()`（`vm.js:140`，`state.spawned`）：
**本进程已经拉起过 QEMU，就拒绝再拉**（手持档**同一进程只能初始化一次 QEMU**，见 `docs/119`）。

于是首装超时判死后：

- 闸门状态**已经被置位**，此后**每一条** `terminal/create` 都撞 `startGate`；
- 用户**必须重启应用**才可能恢复 —— 而重启后又回到「首装」，再次超时 ⇒ **死循环**。

这就是用户看到的「终端都起不来了」。

### 2.3 超时不杀 = 让 `apk add` 在 guest 里空转

旧 QGA 客户端在 `Date.now() - started > timeoutMs` 分支里**只抛错、不杀进程**。
provision 的 `apk add` 在判死后**继续写盘 / 烧 CPU**（源码注释原文 `qga.js:502-503`：
「rootfs 从 48.6 MB 涨到 54.1 MB 才停」）⇒ 越修越慢。

---

## 3. 修法

### 3.1 `provision()` 拆两段（`vm.js`）

新增两个常量取代旧的一整段 120 s（`vm.js:83-84`）：

```js
const PROVISION_PROBE_MS = 30000;
const PROVISION_INSTALL_MS = 600000;
```

第一段「探测」（`vm.js:774-796`）**只做挂载 + 建链 + 判 `/bin/bash`**，
命中即 `DSHM_PROVISION_OK` 快路径（~200 ms 早退）；未命中就 `echo DSHM_PROVISION_NEEDS_INSTALL`，
**不算错误**：

```js
probeLines.push(
  'if [ -x /bin/bash ]; then echo DSHM_PROVISION_OK; exit 0; fi',
  // 没命中不是错误：交给第二段去装（两条路径的判据都是同一件事 —— `/bin/bash` 可执行）。
  'echo DSHM_PROVISION_NEEDS_INSTALL',
);
```

第二段「安装」（`vm.js:805-836`）才发 `apk add`，上限 600 s；
失败时把 `dshm-apk.log` **复制到 9p 共享根**（宿主侧 = 沙箱根）再 `tail -n 20` 进日志 ——
让真机排障拿得到 guest 侧原文：

```js
'cp -f /tmp/dshm-apk.log /mnt/share/dshm-vm-apk.log 2>/dev/null || true',
'tail -n 20 /tmp/dshm-apk.log 2>/dev/null || true',
```

**为什么是 600 s 而不是「更大一点的 120 s」**：安装段是**后台预热**在跑，不挡 UI；
装完跨启动保留，下次直接走 30 s 的探测段。给足时间是消除「没超时是运气」
（手机端首装实测也要 **150~200 s**）。

### 3.2 超时判死前 best-effort 杀进程（`qga.js`）

在 `Date.now() - started > timeoutMs` 分支抛错**之前**，新增一次 best-effort kill（`qga.js:497-510`）：

```js
// 【超时不杀 = 让它在 guest 里空转】……
try {
  await this.kill(pid, 'TERM');
} catch {
  /* 杀不动就照原样抛超时 */
}
throw error;
```

`kill()`（`qga.js:519-524`）走 guest 自己的 `/bin/busybox kill -TERM <pid>`；
**它自身失败不许盖掉那条超时报文**（`catch {}` 只兜底）。

### 3.3 与 `+dshm.38` 的差异面

核心树只动 `dshm-vm-bash/lib/vm.js` 与 `lib/qga.js` 两个文件
（manifest `generatedAt` = `2026-10-13T14:04:02.567Z`、`coreVersion` = `0.2.1-alpha.2+dshm.39`、
`nodeModules.fileCount` = `13605`）。**没有**新插件、**没有**新契约、**没有**改宿主 ArkTS。

---

## 4. 权限面首次落到 8 条

本件是**第一份「8 条权限」的正式侧载件**（此前 r17 侧载件仍声明 11 条）——
三端同一权限面、**与 AGC 上传件一致**。8 条实读：

```
INTERNET · GET_NETWORK_INFO · KEEP_BACKGROUND_RUNNING · PREPARE_APP_TERMINATE ·
ALLOW_EXTERNAL_NATIVE_CODE · FILE_ACCESS_PERSIST · STORE_PERSISTENT_DATA · MICROPHONE
```

其中 `ALLOW_EXTERNAL_NATIVE_CODE` / `FILE_ACCESS_PERSIST` 是**已审批的 ACL**，其余为**免申请**项。
此前那 3 条 `system_basic`（用户文件读写权限 / 全盘访问权限 / 域权限）
**不再进任何交付包**；源码声明面与出包面的一致性由 `tools/sign-release-hap.ps1` 的 `[0]` 步保证
（对着 profile 比、幂等；`.app` 分支 fail-closed），见 `docs/145`。

---

## 5. 产物读数（全部用 `tar` 直读复核）

| 文件 | 大小 | sha256 |
|---|---|---|
| `dist/sideload/DSHM-1.1.0-core0.2.1-alpha.2+dshm.39-arm64-signed.hap` | 398,846,519 B | `6263f535e7ff5210cfa5a54e6b34ce89798514e016c54258ecad9561e6777a2b` |
| `dist/release-test/…+dshm.39-arm64-release-signed.hap` | 398,846,418 B | `8706e9fac3d73c8171a4b5c16761bb6ebbea9e507ac3dec105d6134303124fea` |
| `dist/release-test/…+dshm.39-arm64-release-signed.app` | 195,373,416 B | `9baa7938357272ae7edae38b537396579db5b65af202958d5e8fb7a63e87b287` |
| `dist/release-test/…+dshm.39-arm64-release-buildMode-signed.hap` | 398,846,519 B | `6263f535…`（与侧载件**逐字节相同**）|
| `dist/core/dsh-core-0.2.1-alpha.2+dshm.39-openharmony-arm64.zip` | 60,834,954 B | `f678e73c39ea4f7f6b7b445ccddca3b095000a7c98c9714019dc067ca5e3e6e2`（entries 17083）|

三个 HAP 共同读数：`entries=127` / `debug=false`（`buildMode=release`）/ **权限 8 条** /
**包内 `.apk` 命中 0** / `resources/resfile/**/*.tar.gz` = 20 /
`minAPIVersion=60101024` / `targetAPIVersion=260000026` / `deviceTypes=phone,tablet,2in1`。

`.app` 上架件：外层 3 条目（`pac.json` / `pack.info` / `entry-default.hap`），
内层 396,494,793 B / 126 条目 / `debug=false` / **权限 8 条** / `.apk` 0。

---

## 6. 验证与门禁

- **出包口径复核（`tar` 直读，非解压）**：三个 HAP + `.app` 内层逐一核对
  `entries / debug / requestPermissions / .apk 命中` —— 全部符合 §5。
- **签名物料**用 `D:\desktop\release\`（用户本轮纠正）：`dshm.p12` / `dshm.cer` / `dshmRelease.p7b`；
  **`-KeyAlias` 必须显式给 `ohosdshm`**（默认 `ohosdsh` 报 `11014001`）。
- **`entry/build` 现常驻 release 档**（`entry-default-signed.hap` 398,846,519 B / `debug=false` / 8 条）
  ⇒ 按用户新口径**不再跑 debug 复位**，`tools/update-device.ps1 -SkipRebuild` 装的即与本包一致。
- `tools/check-doc-refs.mjs` 在改完 `docs/` 后复跑通过（见本轮收尾）。

---

## 7. 未做 / 待办

- **本件未做真机验收**：`+dshm.39` 的 provision 拆两段已在源码与门禁层面对齐，
  但**首装 600 s 上限的真机效果**（尤其手机端首装 150~200 s 是否落在新窗口内）
  要等设备回归确认。**这是本轮最需要真机补的一条。**
- `dist/sideload/` 里仍并排躺着 `+dshm.33/37/38` 三个旧 HAP、`dist/release-test/`
  里仍有 `+dshm.33` 三件与 `+dshm.38` 的 `-buildMode-signed.hap`
  （前例 `+dshm.31` 当年被移除以免 AGC 传错包）；是否移走**待用户拍板**。
- `D:\desktop\release\新建文本文档.txt`（签名口令备注）**已不在**原处，
  只在 `D:\DSHM-signing-backup\release-20261010\` 有 —— 出包时用 `-NoteFile` 指定。
- **未 commit / 未 push**（用户明说推送由他决定）。
