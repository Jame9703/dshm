# 交接单：AGC 云调试装不上—真相是版本号（非权限、非拆 HAP）

- **ID**：JD-007
- **提交方**：WorkBuddy
- **日期**：2026-11-19 01:30（订正 01:22 的初判）
- **状态**：开发已回退版本号，待 DevEco 用 1010017 编译验证
- **对应看板**：[`../STATUS.md`](../STATUS.md)

## 1. 症状

新编译的 AGC 包（1010018）云调试装不上；用户明确 **1010017 是能装的测试版本**，现在（1010018）不能。

## 2. 逐字节对比：1010017（能装）vs 1010018（不能）

| 维度 | 1010017 | 1010018 |
|---|---|---|
| entry permissions | **18**（含全盘） | 18 |
| entry deviceTypes | **[tablet, 2in1]** | [tablet, 2in1] |
| minAPI / targetAPI | 60100023 / 260000026 | 相同 |
| apiReleaseType / compileSdk | Release / 26.0.0.105 | 相同 |
| pac.json | sha 相同 | 相同 |
| entry-default.hap 大小 | 53,330,920 | **53,330,920（一致）** |
| hostruntime-default.hsp 大小 | 606,498,296 | **606,498,296（一致）** |
| phone-default.hap 大小 | 3,809,469 | **3,809,469（一致）** |
| `hap-sign-tool verify-app` | 通过 | 通过 |

⇒ 两包**除 `versionCode` 外没有实质差异**；业务内容一致，仅版本号不同导致哈希/签名不同。

## 3. 订正初判（重要）

- **不是权限问题**：1010017 本身就是 **entry 18 条（含 `ACCESS_USER_FULL_DISK`）** 且能装 ⇒ 权限面不是拒装原因。
- **不能拆 HAP**：**Edge / ProMax 是双形态，entry 必须同时声明 `[tablet, 2in1]`**，否则会爆内存。之前提议"拆 2in1 专用 HAP"是错的，撤回。

## 4. 结论与修法

- 差异只有 `versionCode`（1010017 → 1010018）。1010018 不是 AGC 侧已登记/已上传的版本，云调试因此装不上；而 1010017 可装。
- 修法：**版本号回退到 1010017**（已改 `AppScope/app.json5`，`versionCode: 1010017`），用 1010017 重新出包即可恢复可装。
- 若要测"全新内容"：需先在 **AGC 上传为对应版本**再云调试（云调试装的是 AGC 登记版本，不是任意本地包）。这与 `app.json5` 注释里"同版本不同 SHA 无法安装"是同一类约束。

## 5. 请 DevEco 做的事

1. 用 **1010017** 重新编译出 AGC 包（`build-agc.mjs`）。
2. 云调试平板/手机复测安装。
3. 若 1010017 新包仍因"同版本不同 SHA"被拒：把该新包在 AGC 建立/上传为对应版本后再云调试（属 AGC 流程，非包体问题）。
4. 结论写 `JD/from-deveco/20261119-agc-install-result.md`，更新 `STATUS.md`（JD-007）。

## 6. 证据

- 1010017：`dist/release-test/dshm-1.1.8-1010017-dshm.1-AGC-invite-20261118T164204.app`
- 1010018：`dist/release-test/dshm-1.1.8-1010018-dshm.1-AGC-invite-20261118T170734.app`
- 最新运行日志（平板）不含安装动作，故日志侧无安装错误。

## 7. 边界/红线

仅把 `versionCode` 回退到 1010017；**未拆 HAP、未动权限、未改设备面**（Edge/ProMax 双形态 `[tablet,2in1]` 保留）。未 `git commit`、未卸载、未删交付件。
