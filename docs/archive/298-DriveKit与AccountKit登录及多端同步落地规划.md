# 298 · Drive Kit + Account Kit：登录入口与多端同步落地规划

> 日期：2026-10-29 ｜ 状态：**规划稿，不做实现**（等 AGC/真机前置确认后开工）
>
> 用户口径：「Drive Kit + Account Kit 的方案，看落地需要多久，应该需要一个登录华为账户的入口，
> 可以选在左下角的按钮里面，**先规划一下，确保可行**」
>
> 前置：[`297`](297-华为账号多端数据同步三条路线调研与选型建议.md)（三条路线对比）、
> [`291`](291-稳定性与性能完整测试报告（日常使用加开发环境）.md)（数据规模）。
> 本文回答的是：**怎么做、放哪里、做多久、每一步怎样算完成**。

---

## 0. 一页结论

| 问题 | 结论 |
|---|---|
| 技术上能不能做 | **能**。登录组件、`cloudStorage` 上传/下载/列表/删除、云数据库索引 SDK 都在本机；权限只要求已有 `INTERNET` |
| 登录入口放哪 | **左下角现有账号区旁边新增“华为账号”入口**。由插件注入 Web，点击经壳桥打开**原生登录页**，不改官方 `AccountMenu` |
| 数据怎么同步 | **会话文件打包上传 Drive**；会话索引存 Drive 的 `index.json`，**不把 `.jsonl.zstd` 拆成关系型表** |
| 第一版范围 | **登录 + 手动备份/恢复**（先闭环）；自动同步、冲突合并、附件放后一阶段 |
| 总工作量 | **约 12–18 个有效开发日**（不含 AGC 审核等待与真机验收）；最快第一版 **7–10 天** |
| 是否现在就能开工 | **代码可以**，但**“上云成功”必须先过 AGC/鉴权验收**。SDK 存在 ≠ Drive 服务一定可用 |

**推荐做法**：不要一上来做“全自动多端同步”。先做 **P0 鉴权闸门 + P1 登录入口 + P2 单会话手动备份恢复**；
这一步跑通后，再把自动同步和冲突策略叠上去。

---

## 1. 已核实的可行性（本机 SDK 26.0.0.105）

### 1.1 Account Kit：原生登录组件真实存在

`@hms.core.account.LoginComponent.d.ets`：

| 能力 | 事实 | 对本方案的影响 |
|---|---|---|
| `LoginWithHuaweiIDButton` | ArkTS 组件，可嵌入原生页面 | 登录页可直接使用官方按钮，不自绘登录框 |
| `LoginPanel` | 标准登录面板；**只能用于页面，不能用于对话框/子窗** | 登录页应是**独立原生页面/完整面板**，不能弹一个自定义小对话框 |
| `LoginType.ID` | 返回 `openID / unionID / authorizationCode / idToken` | **UnionID 作为云端用户命名空间** |
| `LoginType.QUICK_LOGIN` | 一键登录/手机号授权场景 | 第一版**不强制拿手机号**，避免多余隐私面 |
| 协议状态 | 一键登录前需要 `setAgreementStatus(ACCEPTED)` | UI 必须给协议/隐私说明与同意动作 |
| 失败语义 | `1001502012` 用户取消、`1001502014` 缺 scope、`1001500003` scope 不支持、`1005300001` 未接受协议 | 入口不能“点了没反应”，每类失败都要可读提示 |

**不需要新增 `module.json5` 权限条目**。`@permission` 不是系统权限，`scopes` 是账号授权范围；
但它们需要 AGC 配置，且必须在真机验证。

### 1.2 Drive Kit：云端文件能力真实存在

`@hms.core.deviceCloudGateway.cloudStorage`（CloudFoundationKit）：

```ts
cloudStorage.bucket(name?)
StorageBucket.uploadFile(context, UploadParams): Promise<request.agent.Task>
StorageBucket.downloadFile(context, DownloadParams): Promise<request.agent.Task>
StorageBucket.list(cloudPath, options?): Promise<ListResults>
StorageBucket.getMetadata(cloudPath): Promise<Metadata>
StorageBucket.deleteFile(cloudPath): Promise<void>
```

| 事实 | 对设计的影响 |
|---|---|
| `localPath` 的根目录是 **cache** | 上传前必须把会话写入 **cache 下的同步暂存目录**；不能直接把 `files/dsh/home/...` 当 `localPath` |
| `cloudPath` 可自定义 | 可稳定映射为 `<uid>/<workspace>/<sessionId>/…`，不依赖本地绝对路径 |
| 上传/下载返回 `request.agent.Task` | 可做进度与失败处理；后台任务默认可行，但必须有“任务中”状态 |
| 默认 `overwrite=false` | 恢复必须走**新目录落位 + 校验后替换**，不能原目录覆盖 |
| `list` 支持分页（`maxResults 1–1000`） | 索引、恢复不能一次性假设小列表 |
| `@permission ohos.permission.INTERNET` | 当前 entry 17 / phone 9 已含，无需新增权限 |

### 1.3 云数据库也可用作索引（可选，不是第一版必需）

`@hms.core.deviceCloudGateway.cloudDatabase` 同样存在，只要求 `INTERNET`。
**建议第一版仍把索引放 Drive 的 `index.json`**，少一套 AGC 数据模型与写入一致性；
只有需要“快速云检索/多字段筛选”时再上云数据库。

### 1.4 尚未能核实的三项（不能省略）

| 前置 | 目前状态 | 必须怎样确认 |
|---|---|---|
| Drive Kit 在**当前 HarmonyOS PC/手机**实际上传下载 | 未做真机，不能宣称可用 | P0 真机：同一账号登录 → 上传小文本 → 列出 → 下载比对 → 删除 |
| AGC Drive/CloudFoundation 开关、隐私协议、存储实例 | 未登录当前 AGC 账号 | 项目设置中打开相应能力，准备默认 bucket 或创建 bucket |
| Account Kit 的 client_id/scopes 与 UnionID 返回 | 未配置应用参数 | AGC 配置后真机读回调，确认 `authorizationCode` 和 `unionID` 均返回 |

**这三项不过，后面的同步功能不要假装完成。**

---

## 2. 登录入口：左下角怎么做

### 2.1 现状

官方左下角账号菜单由 `dsh-client-ui-settings-account` 注册：

```js
ctx.slots.inject("settings.launcher", () => ctx.slots.register({...}, AccountMenu));
```

`AccountMenu` 内含设置、联系方式、登录等项（`lib/client.js` 的 `AccountMenu`）。
**不应修改这份官方菜单**：上游升级会覆盖，也违背本仓“不改上游”的边界。

### 2.2 推荐结构

```text
左下角 Web 账号区
  · 官方「… / 更多」菜单（原样保留）
  · 新增「华为账号 / 云同步」入口（dshm-huawei-sync 插件注入）
                    │
                    ▼ 点击（不直接走 Web 登录）
        __DSHM_BRIDGES__.openHuaweiAccount()
                    │
                    ▼
        ArkTS 原生账号页（独立页面或完整面板）
          · 华为账号官方 LoginWithHuaweiIDButton
          · 账号状态 / 同步开关 / 立即备份 / 恢复入口
          · 云空间与隐私说明、退出登录
```

**为什么不是把华为登录按钮直接塞进 Web**：登录组件是 ArkTS 组件，无法在 ArkWeb 的 React 中渲染。
**为什么不用弹窗**：`LoginPanel` 文档明确“只能用于页面，不能用于对话框/子窗”。
所以采用**壳层原生账号页**最稳，入口仍位于用户熟悉的左下角。

### 2.3 具体落点

| 层 | 新增内容 |
|---|---|
| 插件 | `hostcore/plugins/dshm-huawei-sync/`：`lib/index.js`（Host 侧状态/扫描/队列）+ `lib/client.js`（Web 入口与状态展示） |
| Web | 在账号区附近注册入口，样式与 `AccountMenu` 同档；点击调桥，不直接操作 Drive |
| 桥 | `__DSHM_BRIDGES__.openHuaweiAccount()`（同步返回请求 id 或状态字符串）；同时加入 methodList，避免桥未注册报错 |
| 原生 | `entry/src/main/ets/pages/HuaweiAccountPage.ets`（完整原生页），统一登录状态与同步操作 |
| Host | `/dshm-sync/status`、`/dshm-sync/backup`、`/dshm-sync/restore`（均校验 Host token）；不暴露云端凭据给 Web |

### 2.4 入口状态（不能只有一个“登录”按钮）

| 状态 | 展示 |
|---|---|
| 未配置 AGC | “华为云同步未配置”+ 原因，点击给配置说明，不反复弹登录 |
| 未登录 | “登录华为账号” |
| 已登录未开启同步 | 显示脱敏 UnionID + “开启同步” |
| 同步中 | 进度、当前会话数、可取消 |
| 同步失败 | 原因 + 重试，不把失败伪装成完成 |
| 恢复中 | **禁止同时编辑/切换核心**，直到恢复事务完成 |

---

## 3. 同步模型：第一版先做“可解释的手动备份/恢复”

### 3.1 数据形态（核心树实测）

```text
$DSH_HOME/
  sessions/<projectKey(cwd)>/<sessionId>/<version>.jsonl.zstd
  attachments/
  cache/             ← 不同步
  cores/             ← 不同步（每棵约 350 MB）
```

**同步单元 = 会话目录**，同步对象是 `.jsonl.zstd` 文件，不转换成数据库行。
本地 3 个会话约 3.7 MB，规模适合先做手动闭环。

### 3.2 云路径与索引

```text
cloudPath:
  dshm/v1/<unionID>/workspaces/<workspaceId>/sessions/<sessionId>/package.tar.zst
  dshm/v1/<unionID>/workspaces/<workspaceId>/index.json
```

`index.json` 只放元数据：

```json
{
  "schema": 1,
  "workspaceId": "ws-<stable-hash>",
  "updatedAt": "2026-10-29T…",
  "sessions": [
    { "id": "…", "title": "…", "formatVersion": 4,
      "size": 12345, "sha256": "…", "updatedAt": "…" }
  ]
}
```

- **不同步本地 cwd 绝对路径**；用稳定 `workspaceId` + `sessionId`。
- `index.json` 是“索引”，正文是 Drive 的会话包。索引与包体分别校验 SHA-256。
- 每个会话独立上传，后续增量只传有变化的会话，不重传整个 home。

### 3.3 工作区映射（多端同步的关键）

**建议手动确认一次，而非按目录名猜**：

```text
workspaceId = hash(用户选择的规范工作区名 + 首次创建时的 UnionID)
本地映射表：<workspaceId> ↔ <本机 cwd>
```

恢复时显示“云端工作区 X ↔ 本机工作区 Y”，避免 PC 与手机因路径不同生成两份会话。
第一版可只支持**一个默认工作区**，验证链路后再扩多工作区。

### 3.4 上传/下载事务

```text
备份：
  扫描并排除 cache/cores/临时目录
  → 单个会话复制到 cache/dshm-sync/staging/<operation>/<sessionId>/
  → 打包容器 + 写 index.json
  → 上传（带进度）
  → 云侧索引更新
  → 本地 manifest 记录 sha256

恢复：
  读取云端 index.json
  → 下载到 cache/dshm-sync/restore/<operation>/
  → 校验包结构与 hash
  → 停 Host 或进入恢复锁（禁止会话继续写）
  → 新目录落位 → 校验 → 原子替换/合并
  → 清 staging → 重启 Host
```

**不能边跑 Host 边直接覆盖会话文件**。这会撞上游 tmp+rename 的写入语义，属于数据损坏风险。

---

## 4. 分阶段实施与工期

> 工期按“有效开发日”估计，**不含 AGC 审核与真机排队**。

| 阶段 | 内容 | 工期 | 完成判据 |
|---|---|---:|---|
| **P0 可行性闸门** | AGC 开关、账号 scopes、Drive bucket、登录/上传/下载小文件 | **0.5–1.5 d + 等待** | 真机登录返回 UnionID；上传文本→list→下载一致→删除成功；权限仍 entry 17 / phone 9 |
| **P1 登录入口与原生页** | 左下角入口、桥、原生账号页、状态展示、错误文案、退出登录 | **2–3 d** | 未登录可登录、取消可回、协议可查看、重复点击不重复拉起、深/浅色正常 |
| **P2 本地会话清单与打包** | 扫描/排除、workspace 映射、索引与哈希、cache 暂存、离线门禁 | **2–3 d** | 相同输入两次清单一致；cores/cache 零混入；非法路径与缺失会话明确失败 |
| **P3 手动备份** | 单会话上传、Drive 进度、失败重试、云端索引、任务状态 | **2–3 d** | 真机备份 1 个会话后，云侧 list 能见到包体与索引；断网可读失败；不重复上传未变会话 |
| **P4 手动恢复** | 下载、hash 校验、恢复锁、原子落位、Host 重启、另一设备恢复 | **2–4 d** | 设备 B 恢复设备 A 的会话，标题/正文可读；原会话不丢；失败不破坏现有数据 |
| **P5 自动增量与冲突** | 文件变更队列、退避、冲突策略、附件、后台限流 | **4–6 d** | 两端编辑不会静默覆盖；冲突可见可处理；cache/cores 始终不传 |
| **P6 合规与发布** | 隐私政策、数据开关/删除、注销清理、三端回归、AGC 材料 | **2–3 d + 审核** | 用户能关闭并删除云数据；审核材料与实际一致；发布包全量验收 |

**第一版可用（P0–P4）约 8.5–16.5 天**；**完整自动同步（含 P5/P6）约 14.5–25.5 天**。
若只要“登录 + 手动备份/恢复”且已有 AGC 配置与两台可测试设备，**7–10 天可冲刺**，但不压缩恢复安全验证。

---

## 5. 冲突策略：第一版不要做危险自动合并

| 场景 | 第一版处理 |
|---|---|
| 同一 sessionId 云端更新，本机未改 | 允许恢复，原子替换 |
| 本机已改，云端也改 | **不自动合并**，显示“本机/云端都有更新”，由用户选择 |
| 同一工作区 cwd 不同 | 使用 workspaceId 映射，不按绝对路径合并 |
| 不同核心版本 | 不自动改写格式；只恢复相同/受支持的格式代际，其他提示升级 |
| 附件 | 第一版**暂不同步**；会话引用的附件在设置页明确标记，后续单独评估 |

日志是追加式且可能多端并发，**“最后写入者赢”会静默丢内容**。
P5 才评估按代际合并/重放，不能把这个复杂度藏进第一版。

---

## 6. 隐私、凭据与安全边界

1. **云端必须有单独开关**：默认关闭，用户阅读说明后主动开启，不默认上传会话。
2. **Token 不落 Web / 日志 / 云包**：`authorizationCode`、Access Token 只在受控原生/服务端链路；
   Web 只拿脱敏状态（已登录、UnionID 后 4 位、同步状态）。
3. **云端索引不包含对话正文**：标题是否上传也建议做成可选项，默认脱敏。
4. **登出不是删除**：分别提供“退出账号”“停止同步”“删除本账号云端数据”三种语义；删除需二次确认。
5. **错误可读**：网络不可用、AGC 未配置、scope 拒绝、空间不足、会话冲突分别提示，不能都报“同步失败”。
6. **备份包格式校验**：拒绝路径穿越、非预期目录、未知格式、hash 不符；恢复失败绝不删除本地旧数据。
7. **上云加密待明确**：Drive 默认服务端存储加密不等于端到端加密；若需要会话正文对平台不可见，
   要在打包前做用户侧加密，另立密钥恢复方案，**不属于第一版范围**。

---

## 7. 验收清单（按阶段给测试端）

### P0（先跑，不通过就停）

- [ ] AGC 已配置账号 scopes 与 Drive bucket；
- [ ] 登录返回 `unionID` 与 `authorizationCode`；
- [ ] `cloudStorage.uploadFile()` 真机成功；
- [ ] `list()` 能看到该文件；
- [ ] `downloadFile()` 到 cache，字节一致；
- [ ] `deleteFile()` 成功；
- [ ] `check-permission-surface` 仍 entry 17 / phone 9。

### P1–P2（离线/本机）

- [ ] 左下角入口可见，官方账号菜单不变；
- [ ] 登录页为独立原生页，不用 `LoginPanel` 弹窗；
- [ ] 取消登录、scope 失败、协议未同意都有明确提示；
- [ ] 会话清单可重复生成，排除 cache/cores/临时目录；
- [ ] 不修改核心树、不修改官方 AccountMenu。

### P3–P4（真机）

- [ ] 备份一个会话后云侧索引和包体均存在；
- [ ] 另一台设备恢复后标题与内容可读；
- [ ] 本机已有同名会话时不被静默覆盖；
- [ ] 上传中取消、断网、下载 hash 不符均不破坏本地数据；
- [ ] 恢复期间 Host 被锁定，恢复完成后重启，el2 用户数据保全。

---

## 8. 建议的开工顺序

1. **现在先做 P0**：由你确认/配置 AGC，测试端给一台 PC + 一台手机做上传下载小文件验证；
2. P0 通过后再做 **P1 左下角入口与原生登录页**；
3. 并行做 **P2 本地清单与打包门禁**（不依赖云）；
4. 跑通一次“PC 备份 → 手机恢复”，再讨论自动同步。

**不要把 P5 自动同步作为第一期目标。** 先把鉴权、入口、数据打包和恢复安全这四件事验证清楚，
才值得投入后续一到两周。

---

## 9. 一句话交接

这套方案**技术上可行，而且不需要新增权限**：
左下角新增入口 → 原生华为账号登录页 → UnionID 命名空间 → 会话打包到 Drive。
**最小可用版本是“登录 + 手动备份/恢复”，约 7–10 天冲刺 / 8.5–16.5 个有效开发日**；
自动增量与冲突另需 4–6 天。**先过 P0 的 AGC + 真机 Drive 上传下载闸门，再投入正式开发。**
