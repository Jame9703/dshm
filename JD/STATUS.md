# JD 看板（唯一状态来源）

> 每项一个 ID；状态取值见 `README.md`。更新时间用 `YYYY-MM-DD HH:MM`。
> **规则**：交接单在 `from-workbuddy/`，结论在 `from-deveco/`；双方 PASS 后移入 `archive/`。

| ID | 主题 | 提交方 | 状态 | 更新时间 | 交接 / 结论 |
|---|---|---|---|---|---|
| JD-001 | 文档「基础问题」落实与复核（13 项清单） | DevEco → WorkBuddy | 完成 | 2026-11-18 23:00 | 13 项全部落地；WorkBuddy 复核 PASS（详见证阅记录）；闭环 |
| JD-002 | guest 终端生命周期门禁不可复现 | WorkBuddy ↔ DevEco | 阻塞（复跑仍红） | 2026-11-19 00:34 | 交接单 `from-workbuddy/20261118-2320-terminal-lifecycle-gate.md`；WorkBuddy 00:34 复跑仍 3 FAIL（shellExitWithChildOwner / ignoredTermForeground / ownerRecheck），DevEco 的 133/0 本机不可复现 |
| JD-003 | Beta 本机可侧载包构建 + 覆盖安装（+ AGC 云测包） | WorkBuddy → DevEco/设备 | 待测试 | 2026-11-19 00:45 | [`from-deveco/20261119-agc-rebuild-result.md`](from-deveco/20261119-agc-rebuild-result.md)：Beta local 已装 2in1 + Mate 80；**云测包换新** `…T164204.app`（sha `82565754…`） |
| JD-004 | AGC 云调试：平板登录/跳转/插件、手机装不上 | WorkBuddy → DevEco | 待测试 | 2026-11-19 01:45 | [`from-workbuddy/20261119-0032-agc-cloud-debug-issues.md`](from-workbuddy/20261119-0032-agc-cloud-debug-issues.md) · [`from-deveco/20261119-agc-cloud-debug-result.md`](from-deveco/20261119-agc-cloud-debug-result.md)：1010018 已作废；回退 1010017 重出 `…T173822.app`（sha `0d197b3d…`），待云调试复测 |
| JD-005 | Guest VM 资源放开（2 vCPU + 内存上调） | WorkBuddy → DevEco | 待测试 | 2026-11-19 00:45 | [`from-workbuddy/20261119-0036-vm-resources.md`](from-workbuddy/20261119-0036-vm-resources.md) · [`from-deveco/20261119-agc-rebuild-result.md`](from-deveco/20261119-agc-rebuild-result.md)：容器 `5b07f484…` 与源码一致，包已出，待云测耗时/CPU/内存 |
| JD-006 | 平板系统标题栏淡化（三键缩小）+ 竖屏适配核查 | WorkBuddy → DevEco | 待测试 | 2026-11-19 00:45 | [`from-workbuddy/20261119-0040-tablet-titlebar.md`](from-workbuddy/20261119-0040-tablet-titlebar.md) · [`from-deveco/20261119-agc-rebuild-result.md`](from-deveco/20261119-agc-rebuild-result.md)：已编译入包，待平板视觉/缩放/分屏验收 |
| JD-007 | AGC 云调试安装失败根因（版本登记 vs 全盘权限） | WorkBuddy → DevEco | 待验证 | 2026-11-19 01:45 | [`from-workbuddy/20261119-0122-agc-install-full-disk.md`](from-workbuddy/20261119-0122-agc-install-full-disk.md) · [`from-deveco/20261119-agc-rebuild-1010017-result.md`](from-deveco/20261119-agc-rebuild-1010017-result.md)：1010017/1010018 两包仅 `versionCode` 不同，证书/Profile/18·9 权限逐字节一致 ⇒ 排除权限面回归；已回退 1010017 重编 |
| JD-008 | 核心同步到 0.2.2-rc.5 + 版本升 1.1.8 / 1010018 | WorkBuddy → DevEco | 已编译入包/真机落盘已证 | 2026-11-19 12:50 | [`from-workbuddy/20261119-0852-core-rc5-sync.md`](from-workbuddy/20261119-0852-core-rc5-sync.md)；容器 `61749b16…`；随 JD-011 入包；2in1 真机 `dsh/cores/0.2.2-rc.5+dshm.1` 落盘 + 宿主运行已证；koffi 待核已闭环（占位符 by design，`libkoffi.so` 在 HSP libs） |
| JD-009 | 响应 AGC 驳回项①：全盘权限 reason/usedScene 合规化 | WorkBuddy → DevEco | 已编译入包/待 AGC 重提 | 2026-11-19 12:50 | [`from-workbuddy/20261119-1045-full-disk-reason.md`](from-workbuddy/20261119-1045-full-disk-reason.md)；reason/when=inuse 已随 JD-011 入 AGC 包（`…T040320.app`），待用户上传重提 |
| JD-010 | dsh-pet 桌宠接入方案（PC/2in1 悬浮窗） | WorkBuddy → 用户决策 | 暂缓（正式上架后再做） | 2026-11-19 11:39 | [`from-workbuddy/20261119-1130-pet-floatwindow-plan.md`](from-workbuddy/20261119-1130-pet-floatwindow-plan.md)；方案 v2（三端矩阵）；PC 全功能 / 平板浮窗不置顶 / 手机应用内；9–15 人日 |
| JD-011 | 编译出包任务：1.1.8 / 1010018（核心 rc.5） | WorkBuddy → DevEco | 完成（1010018 邀测已推送；插件走查阻塞/平板待自测） | 2026-11-19 15:10 | [`from-workbuddy/20261119-1140-deveco-build-task.md`](from-workbuddy/20261119-1140-deveco-build-task.md) · [`from-deveco/20261119-rc5-1010018-build-result.md`](from-deveco/20261119-rc5-1010018-build-result.md)：AGC 包 `…T040320.app`（sha `6f04f690…`）；门禁 13 项绿 + 全量 133/0；2in1 rc.5 落盘已证；Beta 已按用户要求重出 `dist/beta/…20261119T053148/`（含 JD-009，SHA256SUMS/验签过）；§6.4 插件走查因 verify_ui 服务端故障（3 次）未执行，待人工/工具修复 |

## 阻塞项说明

- **JD-002**：DevEco 侧 3/3 rc=0、`--self-test` rc=0、全量 133/0；WorkBuddy 00:34 复跑仍 3 FAIL（只剩 `WAIT`）。门禁已加两条自证：`pickShell()` 探测 shell 函数覆盖 + `tr/grep` 桩调用标记（未执行会显式报错）。请 WorkBuddy 回填**完整 stderr**，并跑 `node -p "require('fs').readFileSync('tools/check-guest-terminal-lifecycle.mjs','utf8').includes('门禁桩未被执行')"`；若为 false，说明跑的是旧文件。
- **JD-003**：已完成 Beta local 构建并在 2in1 / Mate 80（`192.168.2.3:45595`）覆盖安装、启动成功（数据保留）；AGC 云测包 `dist/release-test/dshm-1.1.8-1010017-dshm.1-AGC-invite-20261118T155513.app`（sha `a1ea67ef…`，profile_acls=8）已构建，待平板云测。源码 16 文件已逐字还原，全量门禁 133/0。
- **JD-007**：DevEco 复核 1010017（`…T164204`）与 1010018（`…T170734`）两包：内层 HAP/HSP 大小逐个一致；`pack.info` 与各模块 `module.json` 只有 `versionCode` 不同；签名证书 `ca94d463…`、Profile `ea6fe380…` 二进制一致；entry 18 / phone 9 权限逐条一致。⇒ **权限面不是 1010018 的变化项**。剩余差异只有 `versionCode`/AGC 登记。已按 1010017 重出 `…T173822.app`（sha `0d197b3d…`）；若云调试仍拒装，先确认 AGC 侧 1.1.8 版本是否已换成该包，必要时以新 `versionCode` 在 AGC 登记后再云调试。

## 已闭环

- JD-001（见 `archive/`，若有归档时补链）。
