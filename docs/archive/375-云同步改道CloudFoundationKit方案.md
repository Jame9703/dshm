# 375 · 云同步改道 Cloud Foundation Kit（不走华为云空间会员）

> ⚠️ **已回退，勿实施**（2026-11-06）：CFK 自 2026-10-28 停止新开发者接入，用户定调继续走云空间。唯一配置口径见 [`docs/374`](374-云空间端云同步AGC配置核对与字段改造清单.md)。本文仅作方案沿革留档。

> 日期：2026-11-05 ｜ 触发：用户确认「云空间服务开启 DSHM 数据同步**需要会员**」，改用 AGC 推荐的 **Cloud Foundation Kit（云开发服务）**：云数据库存元数据 + 云存储存文件本体
> 依据：`harmonyos-docs` 官方指南（开通云数据库/云存储、新增对象类型、初始化访问、`cloudCommon` API）+ 本仓 `platform/src/main/ets/sync/*` 实读
> 结论：**可行，且比原方案更适合我们的数据形态**（会话/附件动辄几 MB，云数据库单对象上限 2MB，本来就必须拆"元数据 + 文件"）

---

---

## ⛔ 0. 阻断性发现（2026-11-05 21:40，必须先读）

**官方计费页顶部公告（云数据库、云存储两个页面都有）原文**：

> 关于云数据库服务停止新开发者接入的公告：由于云数据库服务接入政策的调整，**自 2026 年 10 月 28 日起，我们将不再支持新的开发者接入服务，当前已接入使用的开发者暂不受影响。**
> （云存储服务同款公告，同一日期）

今天已是 **2026-11-05**，晚于该日期 8 天。⇒ **如果本项目此前从未开通过「云数据库 / 云存储」，现在点「立即开通」会被拒**，本方案直接不成立。
**第一件要做的事不是建对象类型，而是去 AGC 点一下「立即开通」看能不能开**（能开 = 老开发者，本文继续有效；被拒 = 换方案，见 §0.2）。

### 0.1 费用归属与免费额度（回答"会不会进我账单"）

| 项 | 免费额度 | 超出后单价（官方价目） |
|---|---|---|
| 云数据库 · 存储 | **1 GB/月** | CNY 1.1627/GB·月 |
| 云数据库 · 出站流量 | **10 GB/月** | CNY 0.7751/GB |
| 云数据库 · 读 / 写 / 删 | **5 万 / 2 万 / 2 万 次/天** | 按量 |
| 云数据库 · 并发连接 | 150 | — |
| 云存储 · 存储 | **5 GB** | CNY 0.1679/GB·月 |
| 云存储 · 出站流量 | **1 GB/天** | CNY 0.7751/GB |
| 云存储 · 上传 / 下载 | **2 万 / 5 万 次/天** | 0.323 / 0.0258 元每万次 |

**结论**：① 计费对象是**你（开发者账号/项目所有者）**，不是用户——用户不用买会员，这正是换方案的目的；② 小规模内测基本在免费额度内，**大概率不出账**；③ 一旦超限，费用记在你的账单，且**配额用尽后服务会直接不可用**（不是自动降级）。

### 0.2 若开不通，备选路线（按本仓场景排序）

| 方案 | 成本 | 合规（保险行业） | 工作量 | 评价 |
|---|---|---|---|---|
| **A. 内网/公司服务器自建后端** | 服务器（已有则 0） | **最好**（数据不出内网） | 中（自己写 API+鉴权） | **推荐**：DSHM 本来就是保险内网场景 |
| B. 华为云 FunctionGraph + OBS/RDS | 按量 | 中（需备案/评估） | 中高 | 留在华为体系，但要华为云账号与新服务 |
| C. 腾讯云 CloudBase / Supabase | 按量/订阅 | 差（数据出境需评估） | 低-中 | 上线快，合规风险最高 |
| D. 回到"华为云空间"端云同步 | **用户买会员** | 中 | 低（原方案） | 你已否决（用户不愿买会员） |
| E. 分布式数据对象/文件（近场） | 免费 | 好 | 低 | 只能同账号近场协同，**不能云端备份/换机恢复**，官方不建议传敏感数据 |

> 工程建议：无论选哪条，端侧都应先抽出一个 `CloudSyncProvider` 接口（`uploadUnit / listDevices / listSnapshots / downloadUnit`），把"用哪家云"变成可替换实现。这样 A/B/C 切换只改一个文件，UI 与合并去重逻辑不动。

## 1. 为什么这条路对我们更合适

| 维度 | 原方案（ArkData 端云同步 / 华为云空间） | 新方案（Cloud Foundation Kit） |
|---|---|---|
| 用户前置 | **需要云空间会员**、要在系统"设置→云空间"开开关 | 不需要会员；数据在**应用自有云端** |
| 存储归属 | 用户云空间容器（`DSHM` 容器） | 应用自己的云数据库 + 云存储 |
| 大小限制 | 资产走 ASSET 通道 | **云数据库单对象 ≤ 2MB**、批量 ≤ 1000 条 ⇒ 文件必须走云存储 |
| 鉴权 | 华为账号 + `DISTRIBUTED_DATASYNC`（ACL 申请 1–2 周） | **华为账号 Access Token 就能当凭据**（见 §3），**不需要那个权限** |
| 计费 | 需要会员 | **按量计费 + 免费额度** |

> 顺带解决两件老问题：① 不再需要 `DISTRIBUTED_DATASYNC`（那条 ACL 申请可以撤）；② `CLOUD_DISABLED schedule=2` 这一整类错误消失（不再走 RDB 端云同步）。

---

## 1. 目标架构

```
端侧                                    云侧（AGC · 云开发 Serverless）
┌─────────────────────────┐            ┌──────────────────────────────┐
│ 会话/插件/技能文件        │            │ 云存储 bucket（实例 dshm-sync）│
│  ↓ 生成 unit 元数据      │  upload    │  dshm/<deviceId>/<yyyy-MM-dd>/ │
│ 本机 RDB: sync_units     │ ─────────► │    <kind>/<unitId>.bin        │
│ （离线缓存 + 首屏数据源） │            ├──────────────────────────────┤
│  ↑ 恢复时合并去重        │  upsert    │ 云数据库 对象类型 SyncUnit     │
└─────────────────────────┘ ─────────► │  （只存元数据，≤2MB/条）       │
                                        │  存储区 zone: dshmsync         │
                                        └──────────────────────────────┘
```

**分工依据**：云数据库单对象 2MB 上限写死在官方文档里，会话 JSON 经常超过它 ⇒ **正文永远进云存储，数据库只存索引**（`cloud_path` + `sha256` + `bytes`）。

---

## 2. 你需要在 AGC 上做的事（按序，逐项照做）

### 2.1 开通两个服务

| # | 路径 | 动作 | 注意 |
|---|---|---|---|
| 1 | AGC → 我的项目 → 左侧「**云开发（Serverless）→ 云数据库**」 | 点「立即开通」 | 首次会要求**设置数据处理位置**（选中国境内） |
| 2 | AGC → 「**云开发（Serverless）→ 云存储**」 | 点「立即开通」，输入存储实例名 **`dshm-sync`** | 实例名规则：小写字母/数字/中划线，3–57 字符，**创建后不可改**；开通后实际名字会变成 `dshm-sync-xxxxx` |

### 2.2 建对象类型（云数据库）

- 对象类型名：**`SyncUnit`**（**这次不用管"表名/容器名"那套**，那是端云同步的规矩；CFK 的对象类型名只用来生成类）
- 存储区（zone）：**`dshmsync`**（最多 4 个，别多建）

字段（**主键必须一个**）：

| 字段 | 类型 | 主键 | 非空 | 默认值 | 说明 |
|---|---|---|---|---|---|
| `unitId` | String | **✓** | **不勾** | 不设 | `kind/workspaceId/key`，与本地 `unit_id` 同值 |
| `kind` | String | – | **不勾** | – | `session / attachment / skill / plugin_manifest` |
| `workspaceId` | String | – | **不勾** | – | 项目路径哈希（`ws-xxxxxxxx`） |
| `sessionId` | String | – | **不勾** | – | 会话 id（合并去重的键） |
| `deviceId` | String | – | **不勾** | – | 上传设备（型号+短哈希） |
| `uploadedAt` | Long | – | **不勾** | – | 本次上传时间（毫秒） |
| `updatedAt` | Long | – | **不勾** | – | 内容最后修改时间 |
| `version` | Integer | – | **不勾** | – | 内容版本号 |
| `bytes` | Long | – | **不勾** | – | 文件字节数 |
| `sha256` | String | – | **不勾** | – | 内容摘要 |
| `cloudPath` | String | – | **不勾** | – | **云存储里的路径**（文件本体位置） |
| `metadata` | String | – | **不勾** | – | unit 元数据 JSON（标题/模型/插件 spec 等） |

> **⚠️ AGC 表单校验（2026-11-05 实测踩到）**：勾了「非空」就必须同时给「默认值」，而**主键字段不允许设默认值** —— 所以 `uploadedAt` 这类勾了非空又不给默认值的字段会直接报红、点不到下一步。
>
> **正确做法：除主键 ⚠️ 只勾「主键」外，其余所有字段的「非空」全部不勾、默认值全部留空。**
> 理由：端侧 `upsert` 时 12 个字段**总是写全**（见 `CloudSyncClient`），云端留空只是兜底；反过来若把非空设死，一旦某台老版本设备少写一个字段，整条写入会被服务端拒绝，排查成本远高于收益。

索引：`sessionId`、`deviceId`、`uploadedAt`（列表按设备+日期查）。

> **类型下拉里没有 `Long` 怎么办**：AGC 字段类型若只提供 `Integer / String / Double / Date / Boolean`，则
> · `uploadedAt`、`updatedAt` 改用 **`Date`**（官方示例里就有 Date，存时间语义最正）；
> · `bytes` 用 **`Integer`**（上限 ≈2.1 GB，单文件远小于它）；
> · **千万别把 13 位毫秒塞进 `Integer`**（2^31-1 ≈ 2.1e9，毫秒时间戳 1.7e12 会直接溢出）。
> 端侧对应地把 `number` 存成 `Date` 或改存 `String`（毫秒串），以 AGC 实际可选项为准。

角色权限：**先给「认证用户」query/upsert/delete**；若实测华为账号 Token 不被识别为"认证用户"（见 §5 待验点），临时给「所有人」query/upsert 但**必须**在字段上加 `deviceId` 过滤 + 说明风险。

> 不要在 `metadata`/`cloudPath` 上开**加密字段**：官方明确开了加密后「所有人」角色权限会被清空且不可改，且加密影响性能。

### 2.3 导出对象类型文件

对象类型建好后，按「引入对象类型文件」导出 **`schema.json`**（AGC 页面「导出」按钮），放到端侧 `entry/src/main/resources/rawfile/schema.json` 或 `platform` 模块对应位置 —— `cloudCommon.init({ databaseOptions: { schema: 'schema.json' } })` 要用它。

### 2.4 不需要做的事（省掉）

- ❌ 不需要「云空间服务」容器/数据类型（上一轮 `docs/374` 那套作废）
- ❌ 不需要 `DISTRIBUTED_DATASYNC`
- ❌ 不需要用户开云空间会员 / 系统"设置→云空间"开关
- ✅ 仍需 `ohos.permission.INTERNET`（已有）

---

## 3. 鉴权：用**华为账号 Access Token**，不引入第二套账号体系

官方 `cloudCommon` 文档原文：

> 开发者可以使用 **AGC 认证服务 SDK** 获取 AuthProvider，或者**使用华为账号服务 Access Token 接口自定义 AuthProvider**。
> `AuthProvider.getAccessToken(isForceRefresh: boolean): Promise<string>` —— 返回的用户凭据「可使用 AGC 认证服务 SDK 或**华为账号服务的获取用户级凭证接口**生成」。

DSHM 已有华为账号登录（Account Kit），因此：

```ts
// platform/src/main/ets/sync/HuaweiAuthProvider.ets（新增）
class HuaweiAuthProvider implements cloudCommon.AuthProvider {
  async getAccessToken(isForceRefresh: boolean): Promise<string> {
    // 已登录 → 取华为账号用户级凭证（forceRefresh 时强制刷新）
    return await huaweiAccount.getAccessToken(isForceRefresh);
  }
}
```

- 用户点「登录」→ **弹框确认** → 华为账号授权 → 拿到 token → `cloudCommon.init({ authProvider })`
- **登录成功后脱敏显示**（手机号 `138****5678` / 邮箱 `ab***@x.com`）
- 不引入 `@hw-agconnect/auth`（少一个依赖、少一套账号），也满足你"不要默认登录、弹框给用户确认"的要求

---

## 4. 端侧改造清单

| # | 改动 | 落点 |
|---|---|---|
| C1 | **删除端云同步链路**：`setDistributedTables` / `cloudSync` / `DISTRIBUTED_CLOUD` 全部移除 | `sync/SyncStore.ets` |
| C2 | `app.json5` 去掉 `cloudStructuredDataSyncEnabled: true` | `AppScope/app.json5` |
| C3 | 本地表迁移：`payload ASSET` → `cloud_path TEXT`；新增 `device_id`、`uploaded_at`（**只增列**，旧列保留兼容） | `sync/SyncStore.ets`（DDL + `ALTER TABLE ADD COLUMN` 兜底） |
| C4 | 新增 `CloudSyncClient`：`cloudCommon.init` + `zone('dshmsync').upsert/query` + `bucket.uploadFile/downloadFile` | `platform/src/main/ets/sync/CloudSyncClient.ets`（新） |
| C5 | 上传编排：本机落库 → `uploadFile`（`dshm/<deviceId>/<yyyy-MM-dd>/<kind>/<unitId>.bin`，`mode=BACKGROUND`）→ `upsert` 元数据；**两个状态位分开**（本机已写 / 云端已传） | `sync/SyncEngine.ets` / `UploadRunner.ets` |
| C6 | 跨设备恢复：`query` 按 `deviceId + uploadedAt` 拉列表 → 用户选设备+日期 → 下载并**合并（按 `sessionId` 去重、保留本机）**；插件只恢复清单+启用状态 | `sync/ImportRunner.ets` / `PluginRestore.ets` |
| C7 | 设置页云同步分区重做（账号卡 / 本机快照 / 设备▸日期 / 上传·刷新·删除 / 恢复） | `sync/SyncState.ets` + `hostcore/plugins/dshm-cloud-sync/lib/client.js` |
| C8 | 错误码人话化（CFK 的错误码与旧 `CLOUD_DISABLED` 完全不同，按新码映射） | `CloudSyncClient` |

---

## 5. 必须实测确认的三件事（`落地好我们测试一下` 就是这个清单）

1. **华为账号 Token 在 CFK 侧算不算"认证用户"**：对象类型角色给「认证用户」后，用华为账号 Access Token 调 `upsert` 是否成功。若报无权限，退路是给「所有人」+ 客户端强制 `deviceId` 过滤（并接受"同应用用户可互读"的风险），或引入 AGC 认证服务。
2. **PC/2in1 支持**：`cloudCommon` 文档写「从 **6.1.0(23)** 开始新增支持 PC/2in1」。DSHM 的 `minAPIVersion` 正好是 6.1.0(23)，**刚好达标**，但要在平板/PC 真机各验一次。
3. **上传大文件**：单个会话 > 2MB 时确认走的是云存储而不是被云数据库拒；`uploadFile` 的 `localPath` 根路径是**应用 cache 目录**，上传前必须先拷进 cache。

---

## 6. 与上一轮（`docs/374`）的关系

`374` 是按**华为云空间端云同步**口径写的（容器名 `DSHM`、数据类型 `sync_units`、12 个字段、端侧去重主键…）。**那整套随本方案作废**，不要再去配它。

`374` 里仍然成立的两条结论，本文继承：
- 「设备 + 日期」必须显式建模（`deviceId` + `uploadedAt`）；
- 不能拿 `updatedAt` 当上传日期。

---

## 7. 证据出处

- 开通：`harmonyos-docs/guides/应用服务/Cloud Foundation Kit（云开发服务）/开发准备/开通云数据库服务.md`、`开通云存储服务.md`
- 对象类型/权限/索引：`.../云数据库/新增对象类型/新增对象类型.md`（字段类型、主键必填、四种角色、加密字段会清权限）
- 初始化与鉴权：`.../云数据库/初始化数据库访问/初始化数据库访问.md`、`api/应用服务/Cloud Foundation Kit（云开发服务）/ArkTS API/cloudCommon (公共模块).md`（`AuthProvider.getAccessToken`、华为账号凭据可用、PC/2in1 自 6.1.0(23) 起支持、`databaseOptions.schema`）
- 云存储：`.../开发准备/开通云存储服务.md`（实例名规则、默认安全策略=认证用户可读写）
- 本仓：`platform/src/main/ets/sync/SyncStore.ets`（`SYNC_DB/SYNC_TABLE/DDL/setDistributedTables`）、`SyncModel.ets:155`（`unit_id` 三段式）、`SyncPlanner.ets:66`（`workspaceIdOf` 不含设备）
