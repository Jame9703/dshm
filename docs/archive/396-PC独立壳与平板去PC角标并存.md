# 396-PC 独立壳（pc=2in1）与平板去 PC 角标并存

- 日期：2026-11-07
- 决策：用户「先 A」——复制一个薄壳给 PC，平板继续不带「PC 应用」角标
- 状态：**已落地**（新模块 + 构建/门禁 + AGC 包）

---

## 1. 为什么可以"再加一个 HAP"

官方唯一硬约束是**同一设备类型最多一个 entry 类型 HAP**（docs/239 §3）。本方案两个 entry 壳的
设备面**不相交**：

| 模块 | 类型 | deviceTypes | 服务对象 |
| --- | --- | --- | --- |
| `entry` | entry | `["tablet"]` | 普通平板（不再被标 PC 应用） |
| `pc` | entry | `["2in1"]` | PC / 2in1 |
| `phone` | entry | `["phone"]` | 手机 |
| `hostruntime` | shared | 三面齐全 | 共享运行时 |

包内已有 `entry`+`phone` 两个 entry 先例，再加一个 `pc` 不改变这条规则。

## 2. 体积：只增 ~7MB（不是 53MB）

`entry` 里 45MB 是 **ffmpeg**，而它是 **PC 专用**：`RuntimePort` 只在 `nativeTerminalOnly`
档注入 `DSHM_PC_RESFILE_DIR`，Host 的 `ensureBundledFfmpeg({ resRoot: … })` 才去读。

所以：ffmpeg 从 `entry` 移到 `pc`（`tools/place-ffmpeg.mjs` 的 DEST 改指 `pc/`），
平板壳只留 ArkTS 与基础资源。

| 模块 | 拆分前 | 拆分后 |
| --- | --- | --- |
| entry（平板） | 53 MB | **7.2 MB** |
| pc（2in1） | — | **53.2 MB** |
| phone | 3.76 MB | 3.76 MB |
| 整包 | 566.2 MB | **573.4 MB** |

## 3. 实现

1. `pc/` = `entry/` 的薄副本（`cp -a`，去掉 `build` / `oh_modules`）；
2. `pc/src/main/module.json5`：`name=pc`、`deviceTypes=["2in1"]`；
3. `pc` 的 `shortcuts_config.json` / `agent_config.json`：`moduleName=pc`；
4. `pc/oh-package.json5`：`name=pc`；
5. `entry` 删除 `resources/resfile/toolchain/ffmpeg`；
6. `build-profile.json5`：新增 `pc` product 与 `pc` 模块（target→`pc`）；
7. `build-agc`：product 模块列表、unzip 清单、entry 断言（`['entry','pc','phone']`）、
   deviceTypes 断言、ffmpeg 断言改到 pc、权限条数（pc 与 entry 同 17 条）；
8. **依赖软链自愈**：`pc/oh_modules` 指回同一批 HAR，两个 cpp 类型包指向 `pc/src/main/cpp/types/*`。
   构建前由 `build-agc` 幂等补齐（离线，不依赖 ohpm 网络）——否则全新检出时 ArkTS 会把
   `platform`/`appstate` 解析成 `any`，报 `arkts-no-any-unknown`（本轮真机前实际踩到）。

## 4. 防漂移门禁

新增 `tools/check-pc-tablet-parity.mjs`：`entry/src/main` 与 `pc/src/main` **逐字节比对**，
仅允许三类差异：

- `module.json5`（name / deviceTypes）；
- `resources/base/profile/{shortcuts,agent}_config.json`（moduleName）；
- `resources/resfile/toolchain/ffmpeg/**`（PC 专用，entry 必须没有）。

当前实测：2972 个文件一致。
**改一边必须同步另一边**，否则门禁红。

## 5. 其他门禁同步

`check-permission-surface`（pc 17 条）、`check-pc-api26`（modulePc=2in1）、
`check-store-readiness`（pc=2in1）、`check-pc-only-surface`（模块表）均已纳入 `pc`；
`check-core-openharmony-patches` 249/0 不变。

## 6. 包

```
dist/release-test/dshm-1.1.8-1010015-dshm.1-AGC-invite-20261107T124125.app
size   = 573411964
sha256 = 27189de1a797789aeaa6bab05e217635b1db4dcd021fb4397e68d2255625b029
```

复核：`hap-sign-tool verify-app` → **success**；profile `"type":"release"`、
`"bundle-name":"com.dshm.dshclient"`；模块表 `entry(tablet) / pc(2in1) / phone(phone) / hostruntime(shared)`。

## 7. 边界

- MatePad Edge / ProMax 上报 `tablet`，装的是 **tablet 壳**，系统不会把它们标成「PC 应用」；
  运行时仍由 `desktopForced` 走 PC 形态（顶栏、原生终端）。这是 docs/239「单包不可兼得」的既定取舍。
- `pc` 与 `entry` 是**两份源码**，靠 `check-pc-tablet-parity` 防漂移；后续若要彻底消除重复，
  可把 ArkTS UI 抽成 HSP（页面生命周期 `onPageShow` 需迁移），单独立项。
