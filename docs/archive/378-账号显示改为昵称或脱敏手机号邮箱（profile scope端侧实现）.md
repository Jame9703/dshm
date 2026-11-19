# 378 · 账号显示：从「内部代号」改为用户认识的账号

> 日期：2026-11-05
> 触发：客户反馈「显示的登陆账号并非实际账号，很多人都是手机号或者邮箱，但是显示的很像是内部代号」；用户口径「不走默认登陆华为账号，弹框给用户确认，登陆成功后**脱敏显示当前华为账号**」
> 关联：`docs/371`（反馈 ①）、`docs/373`（云同步四条需求）、`docs/313 §4.1a`（账号卡）、`docs/322`（静默登录）、`docs/300`/`302`（Client ID）
> 边界：**只改账号显示**，不动云同步链路、不动权限面、不动 AGC 配置、不动核心版本

---

## 0. 根因：显示的是脱敏 UnionID，不是账号

旧 UI 三处显示 `华为账号 ****abcd`。这个值来自 `maskUnionId(unionID)` —— UnionID 是**同一开发者账号下跨应用稳定的内部标识**，用户当然不认识它。它不是「脱敏手机号」，只是「脱敏内部代号」。

数据链：

```text
SyncEngine.state().maskedUnionId
  → SyncState.encodeCloudState()
  → 插件 readState() 的 state.maskedUnionId
  → ① CloudSyncSettings.ets 的 subtitle
    ② hostcore/plugins/dshm-cloud-sync/src/client.src.js 的 Row.hint
    ③ 生成物 lib/client.js（由 tools/gen-cloud-sync-client.mjs 产出，勿手改）
```

用户要的是「登录成功后显示自己认识的账号」，所以必须换数据源，而不是把 `****abcd` 换个糊法。

---

## 1. 官方资料查证：三条路，只有一条不越权

本机三份资料（`~/data/harmonyos-docs`、`HarmonyOS-KB`、`AGC-operations`）交叉核对结论：

| 路线 | 端侧能否直接拿到 | 是否需 AGC 申请账号权限 | 是否需开发者服务器 | 结论 |
|---|---|---|---|---|
| **`profile` scope** → `nickName` | ✅ 是 | ❌ **不需要** | ❌ 不需要 | **采用** |
| `phone` / `quickLoginAnonymousPhone` scope | 端侧只给匿名号；明文要 REST | ✅ 需要，且「获取您的手机号」**仅游戏类应用 + 企业开发者** | 明文路径需要 | 不接 |
| REST `GOpen.User.getInfo` 取明文手机号 | ❌ 否 | ✅ 需要 phone scope | ✅ **开发者服务器 → 华为账号服务器** | 不接 |

### 逐条证据

| # | 出处 | 原文要点 |
|---|---|---|
| 1 | `guides/应用服务/Account Kit（华为账号服务）/获取华为账号用户信息/获取头像昵称/获取头像昵称.md:62` | 「**未设置昵称默认返回华为账号绑定的匿名手机号/邮箱**」 |
| 2 | 同文件 `:66` | 「此场景**无需申请账号权限**」（前置只需配置签名指纹与 Client ID） |
| 3 | 同文件 `:88-93`、`:116-119` | `authRequest.scopes = ['profile']`；从 `AuthorizationWithHuaweiIDResponse.data` 读 `nickName` |
| 4 | `api/应用服务/Account Kit（华为账号服务）/ArkTS API/authentication (华为账号应用统一认证服务).md:1337-1353` | 合法 scope 列表中，只有 `phone` / `quickLoginAnonymousPhone` / `riskLevel` / `realNameAgeRange` 标注「使用该 scope 前需要申请账号权限」；**`profile` 没有这句** |
| 5 | 同文件 `:1898-1907` | `AuthorizationWithHuaweiIDCredential.nickName`（profile 时返回）、`email`（email scope 时返回） |
| 6 | `guides/.../开发准备/申请账号权限.md:15-21` | 权限申请**仅对企业开发者开放**；「获取您的手机号」自检表写明**仅支持游戏类应用** |
| 7 | `api/.../REST API/获取用户信息/获取华为账号用户信息-获取手机号.md:20/35/48` | 接口方向「**开发者服务器 → 华为账号服务器**」，需 `access_token` 且 Authorization Code 要带 phone scope |
| 8 | `docs/302` | `Client ID = 6917614360926110054`（= App ID，按官方规则无需配 `client_id`）；静默登录真机已成功 ⇒ 签名指纹/Client ID 前置已就绪 |

**关键洞察**：`profile` 返回的 `nickName` 在用户没设昵称时就是官方的「匿名手机号/邮箱」（形如 `182******74`），这正好命中用户诉求；用户设了昵称则显示昵称，同样是用户自己认识的账号。

### 权限面铁律落地

用户 2026-11-05 定：「**没有的权限就不要接入**」——不得设计依赖未获批权限的能力，也不预留「先写代码等权限批了再开」的分支。

⇒ `phone` / `email` / `quickLoginAnonymousPhone` 等需 AGC 审批的 scope **一律不接、不预留分支**；明文手机号 REST 需要开发者服务器（DSHM 是纯端侧）且用户要的本来就是脱敏显示，同样不接。

⇒ **不需要新增任何 `ohos.permission.*`、不改 `module.json5`、不重签 Profile、不提 ACL 申请。entry 17 条 / phone 9 条权限面保持不变。**

> 注：`email` 虽然在 API 参考字段表里出现过（`:1905`），但**不在 `scopes` 合法取值列表**里，且需账号权限申请 ⇒ 按铁律不接。

---

## 2. 交互变化（必须让用户知道）

```text
用户点「登录」
  → App 内 showAlertDialog 确认框（不变，仍可「取消」）
  → silentSignIn(forceLogin=false) 拿 UnionID（零弹窗，不变）
  → 【新增】fetchAccountDisplayName(profile scope, forceAuthorization=true)
        ├─ 首次未授权过 profile ⇒ 系统拉起**一次**授权页
        └─ 已授权过 ⇒ 静默返回
  → SyncEngine.adoptAccountLabel(label) ⇒ 三端 UI 显示
```

- 官方业务流程原文：「如用户已给应用授权，则开发者能直接获取用户头像昵称；如用户未授权，则授权请求会**拉起授权页面**」⇒ **首次会多一次系统授权页**，之后每次登录都静默。该调用只发生在用户点过「登录」之后，不是启动即弹，也不改变「不默认登录」的口径。
- **确认框文案已如实订正**：旧文案「本应用只读取账号标识用于同步归属，**不会获取头像、昵称等资料**」在新行为下是说谎，已改为「读取账号标识用于同步归属，并会再请求一次授权，以显示您的昵称或脱敏手机号/邮箱；**可以拒绝，拒绝后仍可正常同步**」。两端 `WebApp.ets` 与门禁同步钉住。
- **降级路径**（任何一步失败都不阻断登录）：拒绝授权 / 设备不支持 / Client ID 或指纹未生效 / 回包校验失败 ⇒ 显示「华为账号 已登录」，**绝不退回 `****abcd`**，也不弹错误提示。
- 登录仍以 UnionID 为准：资料读取是**独立异步步骤**，失败不影响已登录态、开关与云同步能力。

---

## 3. 改动清单

| 文件 | 改动 |
|---|---|
| `platform/src/main/ets/system/HuaweiCloud.ets` | 新增 `maskAccountLabel()`（二次脱敏）、`AccountDisplayNameResult`、`fetchAccountDisplayName()`；`import { util } from '@kit.ArkTS'` 用于一次性 `state`；顶部注释补权限面铁律 |
| `platform/src/main/ets/Index.ets` | 导出 `fetchAccountDisplayName` / `maskAccountLabel` / `AccountDisplayNameResult` |
| `platform/src/main/ets/sync/SyncEngine.ets` | `SyncEngineState` 新增 `accountLabel`；新增 `adoptAccountLabel()`；`adoptLogin()` / `signOut()` 清空（防串号）；`state()` 读不到资料时兜底 `'已登录'` |
| `platform/src/main/ets/sync/SyncState.ets` | `encodeCloudState()` 新增 `"accountLabel"` 字段（**只增不改**，老插件按缺字段回退） |
| `platform/src/main/ets/view/CloudSyncSettings.ets` | 账号卡 `subtitle` 改读 `accountLabel`；`signIn()` 补传 context（docs/322 早已实证不传会 401）+ 登录后异步拉展示名 |
| `entry/src/main/ets/pages/WebApp.ets` | import + 确认框文案订正 + `runSilentLogin()` 成功后异步 `fetchAccountDisplayName` → `adoptAccountLabel` |
| `phone/src/main/ets/pages/WebApp.ets` | 同上（手机壳同口径） |
| `hostcore/plugins/dshm-cloud-sync/src/client.src.js` | `emptyState()` / `readState()` 增 `accountLabel`；`Row.hint` 改读 `state.accountLabel \|\| '已登录'` |
| `hostcore/plugins/dshm-cloud-sync/lib/client.js` | 由 `node tools/gen-cloud-sync-client.mjs` 重新生成（**未手改**） |
| `tools/check-cloud-sync-policy.mjs` | 从 3 条口径扩到 **6 条 / 10 个变异体**（见 §5） |
| `tools/check-cloud-sync-plugin.mjs` | mock 增 `accountLabel`；断言改成「新值必须出现 + `****abcd` 必须不再出现」；补测试脚手架（见 §5） |
| `.github/workflows/gates.yml` | 门禁步骤描述更新 |

### `maskAccountLabel()` 形态规则（不信任上游返回值）

| 输入形态 | 输出 | 说明 |
|---|---|---|
| 含 `@` | `a***@example.com` | 邮箱；官方匿名邮箱本身已含 `***`，走同一分支后仍是脱敏串（幂等） |
| 纯数字 / 带国际冠码，数字位 ≥ 7 | `138****5678` | 明文手机号兜底 |
| 官方已脱敏串 `182******74` | 原样 | 数字位不足 7，不会被再糊一次 |
| 昵称 | 原样限长 24 | 用户设了昵称时显示昵称 |

`fetchAccountDisplayName()` 还做了：`canIUse` 探测、**不设 `permissions`**（因此连 `authorizationCode` / `idToken` 都不会返回，守住凭据纪律）、`state` 一次性随机串 + 回包一致性校验、**永不抛异常**（全 catch 后返回结果对象）。

---

## 4. 状态兼容

`maskedUnionId` **保留**在 `SyncEngineState` 与 `encodeCloudState()` 里，但：
- 只作诊断与状态快照向后兼容（网页侧按「缺字段回退缺省」解析，老插件配新壳不会崩）；
- 三端 UI 一律不再消费它；
- 门禁继续钉住「原始 unionId 不外泄」这条。

---

## 5. 门禁

### `tools/check-cloud-sync-policy.mjs`（主测 OK，10 个变异体全判红）

| # | 口径 | 变异体 |
|---|---|---|
| ① | 登录必须经 `showAlertDialog` 确认框，且有「取消 / 登录」 | 去掉确认框、去掉「取消」 |
| ② | 恢复不覆盖本机（FAILED / SKIPPED / 会话去重） | 改成覆盖本机 |
| ③ | `SyncEngine` 仍必须 `maskUnionId` 脱敏 | — |
| ④ | **账号显示非内部代号**：UI 不得再拼 `maskedUnionId`，状态必须有 `accountLabel` 链路与「已登录」兜底，桥必须序列化 | 面板/插件退回 `****abcd`、去掉兜底、停止序列化 |
| ⑤ | **只用 `profile` scope**，不申请需 AGC 审批的 scope、不设 `permissions` | 加 `phone` scope、加 `serviceauthcode` permission |
| ⑥ | **确认框文案如实**，不得留「不会获取头像、昵称等资料」旧承诺 | 恢复旧承诺 |

### `tools/check-cloud-sync-plugin.mjs`（50 条判据 / 5 变异体判红）

- 断言从 `text.includes('****abcd')` 改为 `text.includes('138****5678') && !text.includes('****abcd')` —— 同时钉住「新值出现」与「旧内部代号不再出现」。
- **顺手修了一个既有脚手架漂移**（与本次账号改动无关）：核心 `0.2.2-rc.1` 物化后的官方设置骨架在 inject 列表里新增 `remoteAccess`，并在 `apply()` 调 `ctx.remoteAccess.whenAccess("settings/describe", cb)`；测试台没有该字段 ⇒ `Cannot read properties of undefined`，五个分支全挂。补 `remoteAccess.whenAccess` mock（按「远程访问立即可用」直接执行回调，否则 `settings.section` 槽位根本不会声明）后恢复全绿。**这是测试脚手架对齐，不改产品代码。**

---

## 6. 验证结果（最终版）

> ⚠️ **首轮三个包已作废**：`…T143104.app`、`…T143341/`、`…T142627/` 虽编译通过，但**核心容器里的云同步插件仍是旧版**（见 §6.1）。**只用本节列出的最终产物**。

| 项 | 结果 |
|---|---|
| ArkTS 编译 | ✅ 三次构建全部 `hvigor BUILD SUCCESSFUL`（`SignHap` / `SignHsp` / `SignApp` 全过）。**新增的 `AuthorizationWithHuaweiIDRequest/Response/Credential`、`util.generateRandomUUID()` 类型全部成立**；只有既有 `getContext deprecated` 等警告 |
| **核心容器重打** | ✅ `CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/pack-core.mjs --skip-install --place-in-app`：44,871 条目 / 103.5 MB / sha256 `e1d2ec0a2aaa73da2d8b93124c0820423444b523d85adc9f90d002b7ce415225`；`check-resfile-core-zip`（resfile ↔ 配方 ↔ 产出三者一致）、`check-core-openharmony-patches`（244/0）均通过 |
| 云同步产品口径门禁 | ✅ 主测通过；10 变异体全判红 |
| 云同步插件门禁 | ✅ 主测 50 条判据；自检 5 变异体全判红 |
| 文档导航门禁 | ✅ `check-doc-refs`（311 篇 / 221 条带行号引用）、`check-doc-index`（296 篇编号文档全收录）均通过 |
| **全量回归** | ✅ `dist/acceptance/20261105-post-account-label-final.txt`：**total=99 / failed=0**（容器更新后重跑） |
| **AGC 上架/邀请测试包（最终）** | ✅ `dist/release-test/dshm-1.1.7-1010014-dshm.1-AGC-invite-20261105T144058.app`<br>**602,135,140 B** / sha256 `89f927669e254ba2536b64ae2dbf626a47d1fc66108159b823ae70a261505770`<br>`BUILD SUCCESSFUL in 1m11s275ms`、`profile_acls=7` |
| **AGC 包三层核验** | ✅ `pack.info` bundle `com.dshm.dshclient` / `releaseType=Release`；entry HAP **17 条**权限、phone HAP **9 条**权限；`APP → hostruntime-default.hsp → dsh-core-0.2.2-rc.1+dshm.1…zip → @deepseek-ai/dshm-cloud-sync/lib/client.js` **含 `accountLabel`、含新 hint、不含旧 `****abcd` 显示、与源码逐字节一致**；`libnode.so.137`（155,413,312 B / sha `dfe298d0…`、含 `.codesign`）与源码逐字节一致 |
| **手机 / PC 侧载包（最终）** | ✅ `dist/beta/DSHM-beta-1.1.7-1010014-20261105T144232/`：两个 `.app`（pc / phone）+ `pc/`、`phone/` 各一套 HAP+HSP + `SHA256SUMS` |
| **PC 单 2in1 包（最终）** | ✅ `dist/beta/DSHM-beta-1.1.7-1010014-20261105T144445/DSHM-beta-1.1.7-1010014-pc-only-debug.app` |
| 构建身份回滚 | ✅ 三次 beta 构建后 `AppScope/app.json5` 仍 `com.dshm.dshclient`，源码树 `com.dshm.dshmbeta` 零残留 |

### 6.1 交付前抓到的「静态容器」缺口（重要经验）

**现象**：首轮 AGC 包编译、权限面、libnode、回归全绿，但解到第三层发现
`…/dshm-cloud-sync/lib/client.js` 是 **28062 B 的旧版**（不含 `accountLabel`），
源码已是 28372 B ⇒ 真机上账号卡仍会显示 `****abcd`，等于**改了但没交付**。

**根因**：随包插件不是由 `build-agc.mjs` / `build-beta.mjs` 从源码读取的。它由
`pack-core.mjs` 的 `embedDshmToolPackages()` 从 `hostcore/plugins/` 复制进
`dist/core/work/dsh-core-*/node_modules/@deepseek-ai/`，再打成**静态 zip** 放进
`hostruntime/src/main/resources/resfile/`；出包脚本只把这个 zip 物化进 HSP，**不重打容器**。

**修法（标准路径）**：
```bash
node tools/gen-cloud-sync-client.mjs                    # 由 src 生成 lib（本次已做）
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/pack-core.mjs --skip-install --place-in-app
# 然后重出 AGC + 手机/PC 侧载 + PC 单包
```
`--skip-install` 复用 work 树但**照常重跑插件/profile/补丁/清单**（脚本 255–263 行注释明确），
各补丁幂等（日志全为「已存在（跳过）」）；`--place-in-app` 才把新 zip 写进 resfile 并清旧容器。

**固定纪律**：以后任何随包插件 / 核心树内容改动，必须走
「改源码 → 重生成产物 → 重打容器 → 重出全部包 → **三层核验包内插件标记** → 重跑回归」。
只改源码直接出包 = 假交付。

---

## 7. 真机验收清单（本机无 hdc，需用户在 AGC 邀请测试包上做）

1. **首次登录**：确认框文案是否如实、是否出现一次系统授权页、授权页能否拒绝。
2. **授权后**：三端账号卡是否显示用户认识的账号（`138****5678` / `a***@example.com` / 昵称），而非 `****abcd`。
3. **拒绝授权**：账号卡是否显示「华为账号 已登录」，且同步开关 / 上传 / 拉取仍可用。
4. **退出再登录**：是否不串号（`adoptLogin` / `signOut` 已清空 `accountLabel`）。
5. **三端一致**：PC / 平板 / 手机的网页分区与原生面板显示是否一致。
6. **AGC 云同步联调**：仍按 `docs/377` 的 5 条判定（系统「设置 → 云空间」开关、`cloud_gid` 非空等），与本文改动无关。

> ⚠️ 本机 hdc 服务端 UDS 绑定被拒（`docs/352`）、无 java 独立验签 ⇒ **离线门禁 + 包结构核验通过 ≠ 真机可用**。安装 / hilog / UI 验证只能由用户在设备上完成。

---

## 8. 边界与风险

- 只改显示；云同步链路、`setDistributedTables`、`cloudStructuredDataSyncEnabled`、AGC 容器/表/字段、权限面、核心版本全部未动。
- 若华为账号返回昵称而非手机号，显示昵称 —— 这是官方行为，同样是用户认识的账号，不是缺陷。
- 若 AGC 侧 Client ID / 指纹配置变化，`profile` 授权会失败 ⇒ 降级「已登录」，不会崩、不影响同步。
- `email` scope 未接（不在合法 scope 列表且需审批）；将来若确需「精确显示邮箱」，须先走 AGC 账号权限申请，按权限面铁律**当前不预留分支**。
- **仍未做**（与本文无关，不要重复劳动）：「设备 ▸ 日期」列表 UI（云端未通时是空表）、平板移动化布局、账号资料持久化（当前只在内存，退出即清）。
