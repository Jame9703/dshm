# JD-007 复核：AGC 云调试装不上——权限面排除，按 1010017 重编

- **ID**：JD-007
- **交接单**：[`../from-workbuddy/20261119-0122-agc-install-full-disk.md`](../from-workbuddy/20261119-0122-agc-install-full-disk.md)
- **执行方**：DevEco
- **时间**：2026-11-19 01:45
- **结论**：1010017 与 1010018 两包**除 `versionCode` 外没有差异**（含权限面、证书、Profile）；
  1010018 装不上不是权限面回归。已回退 1010017 重编并核验。

---

## 1. 逐字节复核（实测）

被测两包：

```text
dist/release-test/dshm-1.1.8-1010017-dshm.1-AGC-invite-20261118T164204.app
dist/release-test/dshm-1.1.8-1010018-dshm.1-AGC-invite-20261118T170734.app
```

| 维度 | 1010017 | 1010018 | 结论 |
|---|---|---|---|
| `.app` 内文件 | 5 个，逐个大小一致 | 同 | 一致 |
| `pack.info` | `code=1010017` | `code=1010018` | **唯一差异** |
| entry `module.json` | 18 条权限 / `[tablet,2in1]` | 同（逐条同名同序） | 一致 |
| phone `module.json` | 9 条权限 / `[phone]` | 同 | 一致 |
| 签名证书 | `ca94d463b759…` | `ca94d463b759…` | **二进制一致** |
| 发布 Profile | `ea6fe380a140…`（8 ACL） | `ea6fe380a140…` | **二进制一致** |
| `hap-sign-tool verify-app` | success | success | 均通过 |

⇒ `ACCESS_USER_FULL_DISK` 在两包里都在，且 Profile 都批了；两包权限面没有任何增减。
**1010018 相对 1010017 不存在权限面变化**，不能用"新增权限导致拒装"解释本次差异。

## 2. 重编结果（1010017）

```text
dist/release-test/dshm-1.1.8-1010017-dshm.1-AGC-invite-20261118T173822.app
size   663,657,473 B
sha256 0d197b3d7189077c4ee7810ab23a72860ffc9cb93925c617cb908b21ed70dacc
```

| 项 | 结果 |
|---|---|
| `pack.info` | `com.dshm.dshclient` / 1.1.8 / **1010017** |
| 模块 | entry(tablet,2in1) + phone(phone) + hostruntime(三端 shared) |
| 权限 | entry **18** / phone **9**（与旧包逐条一致） |
| 核心容器 | `dsh-core-0.2.2-rc.4+dshm.1`，1 份，sha `5b07f484…` |
| `hap-sign-tool verify-app` | success；证书/Profile 与历史包一致 |
| 其它 | 无 `dsh-bili-whale`；`.app.sha256` 与实测一致；`SHA256SUMS.txt` 已收录 |

## 3. 处置建议（云调试侧）

1. 云调试请用 `…T173822.app`（1010017）。
2. 若仍拒装：先确认 AGC 侧 `1.1.8` 版本记录（versionCode 1010017）下的包是否已换成这一份；
   **同版本换包仍被拒时，属 AGC 版本登记问题**，应以新 `versionCode` 在 AGC 创建/上传版本后再云调试，
   不要继续在本地反复重编。
3. 需要定位时请给**安装失败弹窗的错误码/原文**（9568xxx），或安装进行中的 `bms|BundleInstaller` 日志；
   现有两份设备日志时间窗内无安装事件，不能作判据。

## 4. 边界

- 未改源码、版本号（`AppScope/app.json5` 已由交接方回退为 1010017）、权限、设备面。
- 未上传 AGC、未提审、未操作设备；release 包不可本地侧载。
- 未删除任何交付件。
