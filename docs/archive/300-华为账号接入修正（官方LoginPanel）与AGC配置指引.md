# 300 · 华为账号接入修正（官方 LoginPanel 标准）+ AGC 配置操作指引

> 日期：2026-10-29 ｜ 状态：**代码已按官方标准修正，等 AGC 配置后真机验证**
>
> 用户口径：「AGC 需要的操作告诉我怎么操作，然后把入口移到顶栏新建一个菜单，
> 刚才的版本很难点到，而且登录华为账号不是这样的样式，**官方有一套接入的标准**，重新落实」
>
> 前序：[`299`](299-P0可行性验证（华为账号与云盘）.md)（P0 验证页与左下角入口）。

---

## 0. 一句话

用户指出的三个问题全部成立，已修：

| 问题 | 我原来做的 | 改成 |
|---|---|---|
| 入口难点击 | 左下角固定定位浮动按钮 | **顶栏「应用」菜单里一个「华为账号与云同步」项** |
| 登录样式不对 | 裸 `LoginWithHuaweiIDButton`（自定义登录页里的按钮） | **官方标准 `LoginPanel`**（自带协议勾选 + 其他登录方式） |
| 官方接入标准 | 只用了组件、没按官方三步法 | 按 SDK 头注释的**三步接入**落实 |

---

## 1. 为什么原来那个不算"官方标准接入"

SDK 头注释（`@hms.core.account.LoginComponent.d.ets`）逐字写明两个组件的分工：

> - **LoginPanel**: a standard sign-in panel that integrates HUAWEI ID sign-in,
>   **agreement check box**, and **other sign-in methods**.
> - **LoginWithHuaweiIDButton**: used **to embed a HUAWEI ID sign-in button in a custom
>   sign-in screen**.

⇒ 两个组件是**两种场景**：

- **LoginPanel** = 官方标准登录面板，**应用没有自建账号体系时用它**；
- **LoginWithHuaweiIDButton** = 给"已有自定义登录页"的应用嵌一颗按钮。

DSHM 没有自建账号体系，也没有自定义登录页 ⇒ **标准答案是 LoginPanel**。
上一版用了裸按钮：用户看不到协议勾选，也看不到系统提供的其他登录方式 —— 观感与官方不一致，
这才是我做错的地方。

### 1.1 官方三步接入（照 SDK 头注释逐条落）

| 步 | 官方原文 | 本仓落点 |
|---|---|---|
| 1 | Create a `LoginPanelController` object, set `setAgreementStatus` through method chaining, and register the callback functions for various events | `HuaweiCloudProbe.ets` 的 `loginPanelController`：`new LoginPanelController().setAgreementStatus(...).onClickLoginWithHuaweiIDButton(...).onClickCloseButton(...)` |
| 2 | Construct a `LoginPanelParams` object and set `LoginType`, `privacyText`, `appInfo` … | `loginPanelParams`：`appInfo`（图标 `app.media.layered_image` + 名称 `app.string.EntryAbility_label`）、`loginType: LoginType.ID`、`privacyText` |
| 3 | Set the variable `show` to control whether to display the LoginPanel component | `@State showLoginPanel`，页面用 `Stack` 覆盖层承载 |

### 1.2 一个硬约束（为什么不是弹窗）

SDK 逐字：

> **LoginPanel can be used only on pages, not on dialog boxes or sub-windows.**

⇒ 不能塞进 `CustomDialog` / 子窗。实现上用 `Stack` 在本页内浮起一层全屏 `Column` 承载它。

---

## 2. 入口：顶栏「应用」菜单

### 2.1 改动

```text
顶栏「应用」菜单
  主页
  刷新
  关于
  会议模式（默认隐藏）
  华为账号与云同步   ← 新增
```

- 落在 `WebApp.appMenu()` 里，与「关于」「会议模式」同一档；
- 点击 → `openHuaweiCloudProbe()` → `router.pushUrl('pages/HuaweiCloudProbe')`。

### 2.2 为什么放菜单里（用户实测反馈）

用户原话"刚才的版本很难点到"。左下角固定定位按钮的实际问题是：
它压在官方账号区/系统手势条附近，位置不稳定、可点区域小，且没有视觉提示。
顶栏菜单是**成熟入口**：位置稳定、可键盘聚焦、有明确点击区域。

**左下角那个浮动按钮已整条移除**（常量、样式注入、创建函数、tick 调用全部删除），
不是"藏起来"——避免留下两套入口互相打架。

---

## 3. AGC 需要操作什么（照做即可）

> ⚠️ 以下步骤基于 SDK 与 AGC 的既有事实整理；**AGC 控制台的具体菜单名以你看到的为准**，
> 若某一步找不到入口，把截图发我，我按实际界面再对一遍。

### 3.1 前置：确认应用身份

| 项 | 值 | 在哪看 |
|---|---|---|
| 应用包名 | `com.dshm.dshclient` | AppScope/app.json5 |
| AGC App ID | `6917614360926110054` | 已有记录 |
| 签名证书指纹 | `.certs/release1012/dshm.cer` 的 SHA-256 | 见 §3.4 |

### 3.2 Account Kit —— **它不在 AGC 开关里，而在代码的 metadata 里**（2026-10-29 重要更正）

> 用户反馈「AGC 里没找到 Account Kit 在哪里设置」，并给出官方说明：
> **Account Kit 的配置位置是 `entry/module.json5` 的 `metadata`，不是 AGC 的一个开关页。**

#### 官方口径（逐条）

| 项 | 内容 |
|---|---|
| 配在哪 | **`entry` 模块**（`type: "entry"`）的 `module.json5`，新增 metadata：`name: "client_id"` |
| Client ID 从哪来 | AGC →「我的项目」→ 项目 → 应用 → **项目设置 > 常规 > 应用** → **Client ID** |
| **可以不配的条件** | **若 Client ID 与 App ID 相同，则无需配置** |
| 配错的后果 | 报 `1001500001`（指纹证书校验失败）或 `401`（参数检查失败） |
| 必须用哪个 | **应用级 Client ID**，不是项目级 |
| 配套 | 仍要配好**公钥（证书）指纹**，并按需申请 scopes |

#### 本仓当前状态（实测）

```text
entry/src/main/module.json5 的 metadata 只有一条：
  { "name": "ohos.arkui.UIMaterial.state", "value": "enable" }
⇒ **没有 client_id 条目**
```

App ID **已知**：`6917614360926110054`（CLI `publish app-id` 实查）。
**Client ID 未知** —— 它是 AGC 网页「项目设置 > 常规 > 应用」里的字段，
Connect API CLI 的 `app-info` / `project list` 都不返回它（实测字段表里没有 `clientId`）。

#### 你要做的（只有两步）

1. 打开 AGC →「我的项目」→ `com.dshm.dshclient` → 应用 → **项目设置 > 常规 > 应用**
2. 找 **Client ID**，把它发我（或自己判断）：

   - **若等于 `6917614360926110054`** ⇒ **什么都不用配**，直接测登录；
   - **若不等于** ⇒ 把值发我，我在 `entry/module.json5` 的 metadata 里加：
     ```json5
     { "name": "client_id", "value": "<你给的 Client ID>" }
     ```

#### 为什么之前登录会失败（推断）

没配 `client_id` 且 Client ID ≠ App ID 时，Account Kit 拿不到正确的应用标识，
最典型表现就是 `1001500001 应用指纹证书校验失败` —— 它会**伪装成"指纹没登记"**，
让人误以为要去 AGC 补证书指纹。**这正是我们绕圈的地方。**

### 3.2b 证书指纹（仍然要，但先确认 client_id）

见 §3.4 的实测值；两项都可能报 `1001500001`，所以**先确认 client_id，再看指纹**。

### 3.3 CloudFoundationKit / Drive（云盘）——P0 第②步必需

1. AGC 项目 → 「API 管理」→ 启用 **Cloud Foundation Kit**（或「云存储 / CloudStorage」条目）
2. 按提示**签署云空间隐私通知与用户协议**（账号级一次性，签过可跳过）
3. 若控制台要求创建 **存储实例（bucket）**：
   - 实例名规则（SDK 原文）：只用小写字母、数字、连字符；首尾必须是字母或数字；
     长度 9–63；不能出现连续两个连字符
   - 建完后我们代码里调 `cloudStorage.bucket()`（不传名 = 用默认实例），所以
     **建议让默认实例生效**；若只能用命名实例，告诉我名字，我把它加进配置

### 3.4 证书指纹（本机已取，直接抄）

**已验证：调试证书与发布证书是同一套，指纹相同，AGC 只登记这一个即可。**

```text
DF:21:A3:C0:9F:79:54:57:93:05:F8:5C:64:F8:0C:AD:86:F7:98:53:EE:3A:88:7C:1D:EC:95:D2:18:DF:3A:37
```

`openssl` 实测来源：

```text
.certs/release1012/dshm.cer      → DF:21:A3:C0:…:DF:3A:37
.certs/debug-local/xiaobai-debug.cer → DF:21:A3:C0:…:DF:3A:37   （完全相同）
```

> ⚠️ 换证书这件事要留意：将来若调试与发布用**不同证书**，两个指纹都得登记，
> 否则换包即报 `1001500001 应用指纹校验失败`。本仓 `build-beta.mjs` 出 Beta 时
> 会临时切换 profile，签名用的是同一张证书，所以当前只需一个。

### 3.5 配置完成后怎么验证

配置好之后直接跑 P0 验证页（§4），看读数：

- 登录成功且 `authorizationCode` 非空 ⇒ §3.2 配对了
- 第②步「云盘连通」通过 ⇒ §3.3 配对了
- 报 `1001502014` / `1001500003` ⇒ §3.2 的 scope 没配或少配
- 报 `1001500001` ⇒ §3.4 的指纹不对

---

## 4. 真机测试步骤（本版）

1. 覆盖安装（**不要卸载**）：`hdc install -r <包>`
2. 顶栏 → **应用** → **华为账号与云同步**
3. 点「登录华为账号」→ 应弹出**官方标准登录面板**（带协议勾选）
4. 完成登录 → 按钮区显示 `已登录 ****xxxx` 与授权码长度
5. 点「运行 P0 验证链」→ 看七行读数
6. 截图回传

### 判读

| 现象 | 含义 |
|---|---|
| 登录面板没弹出 | 桥或路由问题，看 hilog `page/cloud-probe` |
| 面板弹出但报 `1001500001` | AGC 证书指纹未登记或与实际签名不符 |
| 报 `1001502014` / `1001500003` | AGC 的 scope 未开通 |
| 第②步失败 | CloudFoundationKit 未启用或 bucket 未建 |
| 第③–⑦ 任一步失败 | 把该行完整原因（含 `[code]`）回传 |

---

## 5. 本轮改动清单

| 文件 | 改动 |
|---|---|
| `entry/src/main/ets/pages/HuaweiCloudProbe.ets` | 登录改为官方 `LoginPanel`（三步接入 + `Stack` 承载）；补 `onClickCloseButton`；错误码分类保留 |
| `entry/src/main/ets/pages/WebApp.ets` | 顶栏「应用」菜单新增「华为账号与云同步」；**移除**左下角浮动入口的全部代码（常量/样式/函数/tick 调用） |

### 验证

```text
编译                       BUILD SUCCESSFUL
check-bridge-methodlist    通过
check-sidebar-shim-css     通过（确认移除浮动入口后样式表仍配平）
check-permission-surface   通过（entry 17 / phone 9，未新增权限）
check-feature-wiring       通过
check-doc-index / refs     通过
check-dead-code            通过
```

---

## 6. 交付件

```text
dist/beta/DSHM-beta-1.1.6-1010007-20261029T141804/DSHM-beta-1.1.6-1010007-combined-debug.app
512,115,724 B
sha256 09941619bde0f1e23994f178ff4f8af3a5a7e13dfe929f41367832dba7617075
```

---

## 7. 一句话交接

三处都改到位了：**入口进顶栏菜单**（左下角浮动按钮整条移除）、
**登录换成官方标准 `LoginPanel`**（自带协议勾选与其他登录方式，按 SDK 三步法接）、
**AGC 操作按 §3 逐条给**。配好 AGC 后跑 P0 验证页，七行读数决定能不能进 P1。
