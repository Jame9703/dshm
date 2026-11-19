# 交接单：AGC 云调试（平板登录/跳转/插件、手机安装不上）

- **ID**：JD-004
- **提交方**：WorkBuddy
- **日期**：2026-11-19 00:32
- **状态**：待 DevEco 复核定位（日志无直接证据）
- **对应看板**：[`../STATUS.md`](../STATUS.md)

## 1. 症状（用户实测）

被测 AGC 包：`dist/release-test/dshm-1.1.8-1010017-dshm.1-AGC-invite-20261118T155513.app`（sha `a1ea67ef…`，profile_acls=8；见 JD-003 结论）。

AGC 包在 **云调试**环境：

- **平板端**：无法登录、点登录不会跳转浏览器、不能安装插件。
- **手机端**：一直安装不上。
- 对照：**Beta 包**直接推送到**手机真机**可以打开，只是**打开很慢**。

## 2. 日志分析结论（两份日志）

日志：`~/Download/com.huawei.hmos.browser/2026-11-19 00_05_22.log`、`2026-11-19 00_11_47.log`（整机 hilog，非纯浏览器日志）。

WorkBuddy 已逐项扫描，**未找到**与故障直接相关的证据：

| 检索项 | 结果 |
|---|---|
| `net::ERR` / `ERR_` / dns / socket 异常 | 无相关 |
| `AccountKit` / `hwid` / `login` / `HuaweiAccount` | 无 |
| `startAbility` / `Want` / `browsable` / `OpenLink` | 无（DSHM 相关） |
| 插件安装 / `BundleInstaller` / `installBundle` / `9568xxx` | 无 |
| `127.0.0.1`（16 处） | 全部是 `com.ohos.devicetest` 的 RPC，与 DSHM 无关 |
| `dshm/dshclient`（77 处） | 均为 ArkWeb/AutoFill/Imsa/cef 的框架级 warning（`No icon sizes`、`input_element is null`、`listener is nullptr`），非登录/安装失败证据 |

结论：**这两份日志不覆盖故障现场**（大概率是"打开应用后"的整机日志，没抓到"点登录/装插件/安装"那一刻的关键链路）。需要 DevEco 重新按链路抓日志。

## 3. 建议 DevEco 定位的方向（按症状）

**A. 平板"不会跳转浏览器登录 / 无法登录"**
- 登录外链应通过 `entry/src/main/ets/system/OpenLinkBridge.ets`（`startAbility` 拉起浏览器）与账号桥（`platform/` 下华为账号/`HuaweiCloud`）。
- 云调试平板上重点看：`startAbility` 是否被拒（无浏览器 Ability / want 不匹配 / 权限）、账号 SDK 是否因云环境无华为账号而直接失败、release 身份下 Client ID/Profile 是否与包名一致。
- 需抓：点"登录"瞬间的 `AbilityManagerService` / `Want` / `AccountKit` / `com.huawei.hwid` 相关行。

**B. 平板"不能安装插件"**
- 插件通道：`hostcore/app/dshm-installer.js` / `dshm-install-command.js`，市场桥为 `hostcore/plugins/dshm-market-bridge`。
- 重点看：云调试网络能否访问市场源、沙箱目录写权限、安装清单校验失败。
- 需抓：点"安装插件"瞬间的 installer/网络/文件权限日志。

**C. 手机"AGC 包一直装不上"**
- AGC 为 release 签名、经云调试下发；重点看错误码：`9568287`（多 entry）/ `9568286`（provision 类型）/ `9568322`（签名来源）/ 存储不足 / ABI 不匹配。
- 需提供：云调试手机端的**安装失败错误码原文**。

**D. Beta 手机"打开很慢"**
- 首次启动需解包 ~640 MB 核心（已知，`AGENT-HANDOFF` §7 FAQ#11），二次启动应回落；若非首启仍慢，需抓启动阶段耗时（宿主就绪 / Web 首帧）。

## 4. 请 DevEco 做的事

1. 在 AGC 云调试**重放**上述 4 个动作，按链路抓日志（不要只交"打开后"的整机日志）。
2. 给出每个症状的**第一失败点**与错误码（尤其手机安装失败码）。
3. 若确为代码问题，写回结论交 WorkBuddy 修；若为云调试环境限制，写清边界。
4. 结论写入 `JD/from-deveco/20261119-agc-cloud-debug-result.md`，更新 `STATUS.md`（JD-004）。

## 5. 边界

WorkBuddy 只做日志分析与方向建议，**未改任何登录/安装代码**（缺证据，避免盲改）。

## 6. 红线

未 `git commit`；未 `hdc uninstall`；未删交付件；未改版本/权限。
