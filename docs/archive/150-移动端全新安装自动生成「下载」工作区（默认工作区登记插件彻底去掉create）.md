# 150 · 移动端全新安装自动生成「下载」工作区（默认工作区登记插件**彻底去掉 create**）

> 本文是 **2026-10-13** 这一轮的落实记录。用户原话：
> **「移动端全新安装自己建了一个下载的工作区目录，这个不应该」**
> 用户口径（硬约束，历史多次重申）：**「不要替用户做选择」**「不要私自加工作区」。
> 这是同类事故**第三次**复报：`docs/113` 记过那条 `com.dshm.dshclient`，
> `docs/124` 收窄过一次（"只在注册表为空时登记一次"）——**收窄等于没修**，
> 因为"全新安装首启"正好就是"注册表为空"。

## 0. 一句话结论

- **症状**：手机（`62T0225B18039433`）**全新安装**首启之后，工作区列表里凭空多出一条
  标题 `下载`、路径 `~/Download/com.dshm.dshclient` 的工作区，
  用户自己从没选过那个目录。
- **根因**：自带插件 `dshm-workspace-claim` 的 `reconcile()` 里那条
  「**注册表为空 ⇒ `registry.create(target, "下载")`**」分支。
  全新安装首启注册表**必然为空** ⇒ **必然命中** ⇒ 自动登记一条。
- **修法**：**把"登记"整段删掉**。插件以后**只撤不建** —— 只撤回本插件**早先**
  注入的那条（路径末两段 = `Download/<包名>`），自己绝不再新增任何工作区。
- **安全性**：删登记是**官方语义**。官方客户端的默认工作区本来就在端侧**必失败**
  （`xdg-user-dir DOCUMENTS` 拿不到 ⇒ 只弹一条 `defaultWorkspaceFailed` 的 warning，
  **不阻断、不建会话**）；"选择工作区"这条路在本端是好的（系统目录选择器）。
  注册表为空从此是**正常状态**。

---

## 1. 根因与上游逐行

插件代码在 `hostcore/plugins/dshm-workspace-claim/lib/index.js`。它 2026-10-03 引入时的功能是
「**每次启动**把 ArkTS 认领到的 `Download/<包名>/`（env `DSHM_PUBLIC_DOWNLOAD`）经官方
`workspaceRegistry.create()` 登记进注册表」；2026-10-07（`docs/113`）收窄成
「**只在注册表为空时登记一次**」。收窄之后"全新安装"这个场景**反而成了必然命中**：
首启注册表就是空的。

### 1.1 官方客户端：默认工作区这条路在端侧必失败，且**不阻断**

`@deepseek-ai/dsh-client-ui-workspace/lib/client.js`（设备实读版本 `0.2.1-alpha.2`）：

```
1598  let target = workspace?.workspaceId ?? recentWorkspace(workspaces.items, sessions.byId);
1599  if (target === void 0 && workspaces.items.length === 0 && sessions.ids.length === 0) {
1600      const prepared = await this.initializeDefaultWorkspace(navigation);
1601      if (navigation.aborted) return;
1602      target = prepared?.workspaceId;
1603  }
1604  if (sessionId === void 0 && target !== void 0) sessionId = await this.connectWorkspace(target);
```

只有「**没有可恢复的选择 且 注册表空 且 会话历史空**」这三条同时成立，才会去调
`initializeDefaultWorkspace()`；它的 `catch` 只发一条通知：

```
1607  async initializeDefaultWorkspace(signal) {
1608      try {
1609          return await this.workspaces.initializeDefault(signal);
1610      } catch (_error) {
1611          if (!signal.aborted) this.notify({ kind: "defaultWorkspaceFailed" });
1612          return;
1613      }
1614  }
```

`defaultWorkspaceFailed` 的文案落在 `client.js:4519` 的
`t("defaultWorkspace.failed")` —— 即"无法创建默认工作区，请通过'选择工作区'选择文件夹"
（**warning 级、不阻断启动、不建会话**）。

### 1.2 官方 Host：`initializeDefault()` 的资格判据与目录来源

`@deepseek-ai/dsh-workspace/lib/index.js`：

- `:406-410` `create(path, title)`：`realpath` 规范化 + `stat().isDirectory()` 校验，
  然后进 `enqueueOperation` 串行队列。
- `:423-437` `initializeDefault(resolveDirectory)`：**资格判据**在 `:429` ——
  `workspaceIds.length > 0 || archivedSessionIds.length > 0 || sessions.list().length > 0
  || listStoredHeaders().length > 0` 任一成立就 **`return void 0`**（不建）。
- `:452` `list()` 读注册表；`:467` `delete(id)` 删一条登记（**保留目录与全部会话日志**，
  注释原文："Delete one workspace registration while retaining its directory and every session log"）。

目录来源在 `@deepseek-ai/dsh-api-workspace-controller/lib/index.js`：

```
609  async function defaultWorkspaceDirectory(documentsDirectory, signal, internals = {}) {
610      const platform = internals.platform ?? process.platform;
617      switch (platform) {
619          case "darwin": ... osascript ...
621          case "win32":  ... powershell ...
630          case "linux":  ({stdout} = await run("xdg-user-dir", ["DOCUMENTS"], signal, "hidden"));
633          default: throw new Error(`system Documents directory is unavailable on ${platform}`);
634      }
```

端侧 Node 上 `process.platform` 读作 `linux` ⇒ 走 `:631` 的 `xdg-user-dir`，
**设备上没有这个命令** ⇒ 抛错；即便读成别的值，也会落到 `:633` 的 `default: throw`。
**两条路都抛** ⇒ `initializeDefault` 在本端必失败 ⇒ 客户端只弹那条 warning。
**这正是官方语义：工作区由用户自己选。**

### 1.3 "选择工作区"这条路在本端是好的

`hostcore/profile/ondevice/cordis.patch.yml` 的 ⑤ 段把官方 auto 目录面禁掉，
改挂 `ui-directory-picker-native`（读 `WebApp.ets` 注入的
`globalThis.__DSH_DIRECTORY_PICKER__` = 系统 `DocumentViewPicker`）+
`directory-picker-browse` 后端 ⇒ 侧栏"添加工作区"能拉起系统目录选择器。

⇒ 端侧**不需要、也不该**替用户决定工作区落在哪。

---

## 2. 为什么删掉 create 是安全的

| 关注点 | 结论 |
|---|---|
| 全新安装首启会怎样 | 注册表空 ⇒ 客户端弹一条"请选择工作区"的 warning，**不阻断、不建会话** ⇒ 用户自己在侧栏选 |
| 注册表为空是不是异常 | **不是**。本插件不再登记任何东西 ⇒ 空注册表是**正常态**（不再是"登记前的中间态"） |
| 撤回会不会误伤 | `isOurRow()` 按**路径**判（末两段 `Download/<包名>`），**只可能**命中认领目录那一类，**绝不碰**用户自己的工作区 |
| 撤回会不会删数据 | 只调官方 `workspaceRegistry.delete(id)`，**不动目录、不删任何会话日志**；它名下若有会话（客户端首启建的空壳），撤回后按官方语义落到"未分组"，仍然能打开 |
| 读不到注册表 | **什么都不做**（fail-closed） |
| 会不会阻断启动 | `apply()` **同步返回**，撤回是自行吞错的**浮空 promise** ⇒ 失败只打一行日志，绝不升级成"Host 启动失败" |
| 没有 `DSHM_PUBLIC_DOWNLOAD` 时 | **完全惰性**（其它部署零副作用） |

撤回的**边界**（写进代码头注）：不改上游 dsh、不新增权限、只删注册表一行、
撤完允许为空。**恢复条件**：上游若给"默认工作区"提供不依赖空历史、且在 openharmony 上
可用的目录来源，或本端决定改由 ArkTS 侧经 picker 显式征得用户同意后再建，再另议。

---

## 3. 门禁

### 3.1 `tools/check-workspace-claim.mjs`（整文件重写）

- **12 条用例** + **A 段**（真模块在任何用例里都**不许** `create`）+ **C 段对照臂**
  （内联**旧实现**（"注册表空就 create"），要求**判红 ≥5 条** ⇒ 证明用例有牙）。
- 实测：**14 条断言全绿**，对照臂老实判红 **6 条**（逐条打印"旧实现过不掉：…"）。

### 3.2 `tools/check-core-openharmony-patches.mjs`（④ 组判据收紧）

`dshm-workspace-claim` 那组 `markers` 改成：

```js
[['DSHM_PUBLIC_DOWNLOAD', 4], ['registry.create(', 0]]
```

即：插件里 `DSHM_PUBLIC_DOWNLOAD` 只剩 **4** 处引用（删登记分支时 5→4），
`registry.create(` **必须 0 处**（守"绝不 create"）。实测 **187 passed / 0 failed**。

> 注意 `dshm-tool-fs-remove` 那条 `DSHM_PUBLIC_DOWNLOAD` 仍是 ×5，**两条判据各自成口径**，
> 不要合并计数。另外：往本文件里写 `registry.create(` 这段文字**会**加计数 ⇒
> 该判据的锚定口径见脚本自身的注释，改动时别再让它被自己的注释顶红（同族教训见 `docs/149` §3.1）。

---

## 4. 出包（`+dshm.36` → `+dshm.37`）

插件内容会进核心 zip ⇒ 树内容变了 ⇒ **必须换版本号**，否则
`BundledCore.installBundledCores` 按「资源包大小指纹」判定为"已安装"而**跳过解包**
（`hostruntime/src/main/ets/core/BundledCore.ets`，真机踩过的坑）。

| 项 | 读数 |
|---|---|
| `hostcore/core-recipe.json` `coreVersion` | `0.2.1-alpha.2+dshm.36` → **`0.2.1-alpha.2+dshm.37`** |
| 分发容器 | `dist/core/dsh-core-0.2.1-alpha.2+dshm.37-openharmony-arm64.zip`，**60,832,765 B** |
| 容器 sha256 | `a2a353bb9ed39922ba81e7e9d513ffa5e3a859eb6b947d7ac92ecc7b30faf278` |
| resfile | 只有这 **1** 份容器；`check-resfile-core-zip` 三方一致（配方 = resfile = 产出） |

出包命令（**必须带 `--place-in-app`**，否则 resfile 不带容器 ⇒ 改动全不生效）：

```powershell
node tools/pack-core.mjs --skip-install --place-in-app
```

> ⚠️ **不要**跑 `tools/place-toolchain.mjs` —— 它会把 resfile 那 15 个 `.apk` + 1 个
> `.tar.gz` 重新 gzip（只有 gzip 头 MTIME 变），与已出 HAP 失同步（"出包三坑"之一，见 `docs/116`）。
> ⚠️ **不要**裸跑 `tools/pack-core.mjs` 之外的流程去重打 `dshm-core.json` 的 `builtAt`（同 `docs/116`）。

### 4.1 同轮其他接线（不是"工作区"这件事，但同属本次出包）

- `docs/parity-matrix.md:454` 的 `dshm-workspace-claim` 行整行改成「**只撤不建**」口径。
- `hostcore/plugins/dshm-workspace-claim/package.json` 的 `description` 改成"只撤不建"。
- `cordis.patch.yml` ⑧ 段说明整段重写成"只撤不建"口径（引本文、引 `client.js:1598-1603`）。

---

## 5. 真机判据（本轮）

装机走**唯一入口** `.\tools\update-device.ps1`（只用 `hdc install -r`，**无任何卸载/删数据**）。

| # | 判据 | 期望读数 |
|---|---|---|
| ① | 首启 `node-output.log` | **不应再出现**「已登记默认工作区」那类行 |
| ② | 现存那条 `下载` 记录 | 新代码**撤掉**它（允许撤完为空 = 正常态；UI 会提示"请通过'选择工作区'选择文件夹"） |
| ③ | 宿主日志 | `已撤回本插件早先登记的一条：…` 或 `没有本插件早先登记的那条 ⇒ 不动作` |
| ④ | 用户数据 | `home` 指纹装前 = 装后（**只删注册表一行**，目录与 6 个会话都还在） |

> **全新安装**这一条需要用户配合"清数据后重装"或另一台设备 —— **绝不允许自行
> `hdc uninstall`**（`AGENTS.md` 最高优先级条款：el2 用户数据不可逆）。

---

## 6. 未做 / 待验（如实登记）

- **PC / 平板档未验**：本轮设备只有手机（PC 未连）。三端插件面同源，但**未实证**。
- **`dist/sideload/` 仍是上一代**：出正式侧载包是独立动作，用户随时可能要。
- **未 commit / 未 push**（推送由用户决定）。

---

## 7. 顺手订正（本轮之外）

- `docs/README.md` 顶部「编号 95–149」→ **95–150**，并补本文索引行。
- `AGENTS.md` 的「文档」行最大编号 **149** → **150**。
