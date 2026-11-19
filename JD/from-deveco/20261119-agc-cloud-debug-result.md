# JD-004 复核：AGC 包云调试安装不上（日志与包体分析）

- **ID**：JD-004
- **交接单**：[`../from-workbuddy/20261119-0032-agc-cloud-debug-issues.md`](../from-workbuddy/20261119-0032-agc-cloud-debug-issues.md)
- **执行方**：DevEco
- **时间**：2026-11-19 01:00
- **结论**：**日志未覆盖安装现场，暂不能定位到代码/包体缺陷**；包体本身校验通过。给出 4 个可执行排查点与下一步。

---

## 1. 用户提供的两份日志（最新）

```text
~/Download/com.huawei.hmos.browser/2026-11-19 00_54_57.log
~/Download/com.huawei.hmos.browser/2026-11-19 00_51_39.log
```

实测：

| 项 | 结果 |
|---|---|
| 时间跨度 | `00:50:30–00:51:03`、`00:53:47–00:54:42`（各约 30–55 秒） |
| `dshm` / `dshclient` 命中 | **0** |
| `BundleInstaller` / `installBundle` / `安装失败` 命中 | **0** |
| `9568xxx` | 仅有 PID/哈希误命中，不是错误码 |
| 主要噪声 | `com.ohos.devicetest` RPC、`DHDP`、`bms_behavior`（电池） |

⇒ 这两份日志是**设备运行期系统日志**，没有覆盖"上传/安装包"的那一刻，无法据此判定安装失败原因。

## 2. 包体核验（本次被测包）

```text
dist/release-test/dshm-1.1.8-1010017-dshm.1-AGC-invite-20261118T164204.app
size   663,657,474 B（≤ 云调试 4 GB 上限）
sha256 82565754…（与 .app.sha256 一致）
```

| 项 | 值 |
|---|---|
| `unzip -t` | **No errors detected** |
| `hap-sign-tool verify-app <app>` | **success** |
| 模块 | `entry-default.hap`（tablet+2in1）、`phone-default.hap`（phone）、`hostruntime-default.hsp`（三端） |
| bundle / 版本 | `com.dshm.dshclient` / 1.1.8 / 1010017 / release |
| minAPIVersion | **60100023（API 23）**；targetAPI 260000026 |
| 核心容器 | 1 份，sha `5b07f484…` |

补充事实：`.app` 内的 HAP/HSP **没有独立 HAP Signing Block**（`verify-app` 对单模块报 `-106 No HAP Signing Block`），
签名在 APP 层；这是当前 `devecocli build --build-mode release` 的产出形态，AppGallery 接受。
若云调试对"模块级签名"有额外要求，这一层需要单独确认（见 §3.4）。

## 3. 最可能原因与排查顺序

### 3.1 上传耗时（最可能）

包体 663 MB，其中 HSP 约 **610 MB**。云调试"本地上传"会把整包传完才安装；
如果是在**调试会话内**上传，进度条会长时间不动，免费时长容易被耗尽。

**处置（官方 FAQ 问题五）**：先在 **云调试 → 我的信息 → 应用** 里上传并等待完成，再进会话点"安装"。
上传期间不要断网/切页。

### 3.2 云设备 API 低于包的最低 API

`minAPIVersion = 60100023（API 23）`。若所选平板是 API 22 及以下，会报
`9568297 install failed due to older sdk version in the device`，表现也可能是卡住。

**处置**：云调试机型筛选选 **HarmonyOS 6.1.0 / API 23 及以上** 的平板。

### 3.3 设备形态与 product 选择

包里有 **两个 entry HAP**（tablet+2in1 / phone）。官方 FAQ 问题七称云调试已支持多 HAP，
但两个 entry 属于边界形态；若安装器只取第一个或按所选设备过滤失败，会卡在安装阶段。

**处置**：先确认所选设备是 **tablet**（不是 2in1-only 机型）。
若仍失败，我可以另出一个**只含 tablet 单 entry** 的云测 APP（见 §4）。

### 3.4 签名形态（APP 级 vs 模块级）

APP 整体验签通过，但模块无独立签名块。若云调试安装器走"逐模块安装"并要求模块签名，
会出现"进度条转但装不上"。

**处置**：请把云调试弹窗里的**错误码/提示原文**（或截图）发回；
必要时我可以按"模块级签名"重出一次云测包做 A/B。

## 4. 建议的下一步（需要用户配合）

1. **先在"我的信息 → 应用"预上传**（663 MB，请等到 100%），再开会话安装。
2. 确认云设备 **API ≥ 23**、形态为 **tablet**。
3. 若仍失败：点提示框的"参考文档"或复制错误码；同时**在安装进行中**导出设备日志，
   过滤 `bms|BundleInstaller|install|9568|dshm`（云调试 → 查看和导出日志）。
4. 把上述信息回填到本结论；我据此决定是否出"tablet 单 entry"或"模块级签名"版本。

## 5. 边界

- 未访问 AGC 云调试控制台（无该权限）；以上基于两份日志、包体实读与官方云调试文档。
- 未改任何源码 / 版本 / 权限；未删除交付件。
- `dist/release-test/` 当前只剩 `…T164204.app`（其余历史包已不在目录，非本次操作删除）。

## 6. STATUS 同步

`JD/STATUS.md`：JD-004 保持 **待测试**，阻塞说明更新为"日志未覆盖安装现场；需预上传 + 设备 API/形态确认 + 错误码原文"。

---

## 7. 补充：与"已知能装"的旧包逐项对照（2026-11-19 01:10）

找到一份此前已装成功过的旧 AGC 包（用户 Downloads 内）：

```text
~/Download/com.huawei.hmos.browser/
  dshm-1.1.8-1010015-dshm.1-AGC-invite-20261108T121648.app   (566,227,319 B)
```

与本次 `…T164204.app` 逐项比对结果：

| 项 | 旧（1010015，能装） | 新（1010017，装不上） | 是否可能导致装不上 |
|---|---|---|---|
| APP 结构 | entry + phone + hostruntime.hsp + pac.json + pack.info | 同 | 否 |
| ZIP 压缩方式 | 全部 store | 同 | 否 |
| 模块签名块 | 无（APP 级签名） | 同 | 否 |
| 签名证书 | `ca94d463…` | `ca94d463…`（同一张） | 否 |
| Profile | release / app_gallery / 同一 App ID | 同 | 否 |
| `pack.info` | — | 仅 `version.code` 1010015→1010017 | 低 |
| entry 权限 | **17 条** | **18 条（新增 `ACCESS_USER_FULL_DISK`）** | **待验证** |
| versionCode | 1010015 | 1010017（与上一版 T155513 **相同**） | **待验证** |
| HSP / 核心 | 509 MB / rc.1 108 MB | 606 MB / rc.4 203 MB | 低（Beta 同尺寸 HSP 在本机可装） |

结论：包体本身是**合法可安装形态**（结构、证书、验签、压缩方式与旧包一致）；
与旧包的实质差异只剩 **新增受限权限** 与 **versionCode 相同（1010017）** 两处。
要判定是哪一处，必须做对照实验，不能靠猜。

### 建议的二分实验（按顺序）

1. **旧包对照**：把上面那份 1010015 旧包传到云调试安装。
   - 若也装不上 ⇒ 云侧/配额/设备问题，不是新包；
   - 若能装上 ⇒ 新包差异（权限或同版本）坐实。
2. **同版本变量**：新包与上一版 `…T155513` 同为 1010017。若云设备/应用库里已有 1010017，
   同版本不同 SHA 可能被安装器拒绝或卡住。把 `versionCode` 升到 1010018 重出即可验证（**需用户明确批准**）。
3. **权限变量**：`ACCESS_USER_FULL_DISK` 是 2in1 受限 ACL。`build-agc` 硬校验 entry 18 条，
   无法直接产出 17 条包；需要用户同意"临时改权限面做诊断包"（诊断后立即还原）。

### 需要的现场证据

- 云调试弹窗的**错误码/提示原文**（哪怕只有一句）。
- 或安装进行中的设备 HiLog（过滤 `bms|BundleInstaller|install|9568|dshm`）。
  当前两份日志时间窗内没有任何安装事件，不能作为判据。

---

## 8. 1010018 重出（用户授权）

用户确认升版本号，已把 `AppScope/app.json5` 的 `versionCode` 从 1010017 改为 **1010018**（`versionName` 仍 1.1.8），
用于验证"同 versionCode 不同 SHA 导致云调试装不上"的假设。

```text
dist/release-test/dshm-1.1.8-1010018-dshm.1-AGC-invite-20261118T170734.app
size   663,657,474 B
sha256 6b5dae270f3ee9e5849c93a34f6d3528fcb74f2c4a217246db2dd2aa1ff0e952
```

核验：

| 项 | 结果 |
|---|---|
| 模块 versionCode | entry / phone / hostruntime 均为 **1010018** |
| 权限 | entry 18 / phone 9 |
| 核心容器 | `dsh-core-0.2.2-rc.4+dshm.1`，sha `5b07f484…` |
| `hap-sign-tool verify-app` | success |
| `.app.sha256` | 与实测一致 |

**请用本包复测云调试安装。**
- 若能装上 ⇒ 原因就是"同 versionCode 不同 SHA"，后续出包注意 versionCode 递增；
- 若仍装不上 ⇒ 下一个变量是 entry 的 `ACCESS_USER_FULL_DISK`（需用户同意出 17 权限诊断包）。
