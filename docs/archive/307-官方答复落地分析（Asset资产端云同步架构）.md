# 307 · 官方答复落地分析：Asset 资产端云同步架构

> 日期：2026-10-30 ｜ 状态：**方案决策，待你确认后实施**
>
> 输入：华为官方对 [`306`](306-向华为提工单（端云同步BLOB2MB读取上限）.md) 四个问题的完整答复。
>
> 用户口径：「AGC AI 助手回复的」（附完整技术答复）。

---

## 0. 一页结论

| 项 | 官方结论 | 对我们的影响 |
|---|---|---|
| **2 MB 上限** | **官方文档明确记载**："建议一条数据不要超过 2M。超出该大小，**插入成功，读取失败**" | ✅ 与我们的实测**完全吻合**（1.5MB 过、2MB 读失败） |
| 字符串写入上限 | 8 MB，**静默截断** | 我们是 BLOB，不受此限 |
| `substr()` 分片读 | 技术可行但**非官方推荐** | 放弃这条路 |
| **官方替代** | `queryByStep()` / `queryWithoutRowCount()` → `LiteResultSet` | ✅ 本机 SDK 已核实存在 |
| 端云同步上限 | 普通字段无独立公开上限；**Asset 1B~50G** | ✅ 7 MB 完全覆盖 |
| **官方推荐架构** | **文件与元数据分离 + ASSET 资产端云同步** | ⭐ **我们改用这个** |

**结论：改用官方推荐的 Asset 架构。** 这让所有问题一次性消失——
7 MB 会话不进 BLOB，而是作为"资产文件"随记录同步，单资产上限 50 G。

---

## 1. 官方答复与本机 SDK 的逐条核对

我没有直接采信答复，而是在本机 SDK（`apiVersion=26`）里逐项验证：

| 官方提到 | 本机 SDK 实读 | 结论 |
|---|---|---|
| `queryByStep(sql, bindArgs?)` | ✅ 存在，`@since 26.0.0` | 真实 |
| `queryWithoutRowCount(predicates)` | ✅ 存在，返回 **`LiteResultSet`** | 真实 |
| `getAsset(columnIndex): Asset` | ✅ 存在 | 真实 |
| `interface Asset { name, uri, path, createTime, modifyTime, size, status? }` | ✅ 字段与官方示例**逐字一致** | 真实 |
| `context.distributedFilesDir` | ✅ 存在于 `application/Context.d.ts:133` | 真实 |
| `Asset` 单资产 1B~50G | SDK 无此声明（属云侧规则） | 采信官方文档 |

> **注意**：`queryByStep` 是 **API 26 新增**。我们的 `compatibleSdkVersion` 是 `6.1.0(23)`，
> 所以用到它必须加 `canIUse` / `apiVersion >= 26` 守卫，否则 API 23 设备会崩。

---

## 2. 为什么必须换架构（而不是打补丁）

### 旧设计（`docs/304` §3）的问题

```text
会话代际 .jsonl.zstd  →  BLOB 整条存  →  RDB  →  端云同步
                         ↑
                    2MB 读取上限（官方确认是设计如此）
```

会话**平均 1.1 MB、最大 7 MB** ⇒ 一大半会话读不回来。

### 三条"打补丁"的路，官方都不推荐

| 打补丁方式 | 官方态度 | 我们的判断 |
|---|---|---|
| `substr()` 分片读 | "技术上可用，**不是官方推荐**"，且有并发一致性风险 | ❌ 放弃 |
| `queryByStep()` 读大 BLOB | 可行（官方推荐用于**读取**超 2MB） | 🟡 可用，但仍是"绕行" |
| 切成多条记录 | 未提及 | ❌ 复杂度落在我们身上 |

### Asset 架构为什么更好

```text
会话代际 .jsonl.zstd  →  留在 distributedFilesDir（文件本体）
                              ↓
                         RDB 里只存 Asset 元数据（name/uri/path/size/时间）
                              ↓
                         端云同步自动带上资产文件（单资产 1B~50G）
```

| 优势 | 说明 |
|---|---|
| **无 2 MB 问题** | 文件不进 BLOB，读的是本地文件，不受 ResultSet 限制 |
| **同步是官方处理** | 资产随记录上云，不用我们自己打包/上传 |
| **天然增量** | `size` 变化即判定资产变更，只传变化的 |
| **跨端自动还原** | 另一端拉元数据 + 资产文件 |

---

## 3. 新的数据模型

### 3.1 表结构

```sql
CREATE TABLE IF NOT EXISTS sync_units (
  unit_id    TEXT PRIMARY KEY,   -- 必须全局唯一（UUID/编码路径），**禁止自增**
  workspace  TEXT,
  session_id TEXT,
  version    INTEGER,
  sha256     TEXT,
  bytes      INTEGER,
  updated_at INTEGER,
  payload    ASSET               -- ← 文件本体在 distributedFilesDir
);
```

### 3.2 与旧设计的对应关系

| 旧字段 | 新字段 | 变化 |
|---|---|---|
| `payload BLOB` | **`payload ASSET`** | 内容搬到文件，表里只存描述 |
| `unit_id TEXT PRIMARY KEY` | 不变 | 本来就是文本主键（非自增）✅ |
| 其余元数据 | 不变 | 照旧 |

### 3.3 Asset 描述怎么构造

```ts
const stat: fs.Stat = fs.statSync(filePath);
const asset: relationalStore.Asset = {
  name: fileName,
  uri: 'file://' + filePath,
  path: filePath,
  createTime: String(Math.floor(stat.atime)),
  modifyTime: String(Math.floor(stat.mtime)),
  size: String(stat.size),                                  // ★ 变更判定依据
  status: relationalStore.AssetStatus.ASSET_NORMAL
};
```

**`size` 是全链路契约**：官方强调它"是端云同步判定资产是否变更的关键依据，须全链路统一为**字节、非负整数**格式"。
所以写入时**绝不能**写成 `"7MB"` 这种人类可读格式。

---

## 4. 六条官方硬约束（必须逐条遵守）

| # | 约束 | 对 DSHM 的影响 |
|---|---|---|
| 1 | 表列**只能新增**，不能修改/删除 | ⚠️ **表结构必须一次定对**，之后只能加列 |
| 2 | S4 安全级别不能同步到云 | 我们用 S1，没问题 |
| 3 | 删除数据时**端云同步不删本地资产文件** | ⚠️ 要自己做文件清理（否则缓存越堆越多） |
| 4 | `Asset.size` 必须"字节、非负整数"字符串 | 写入时统一格式 |
| 5 | 每应用最多 **16 个**分布式库，单库最多 **8 个**订阅回调 | 我们 1 个库，够用 |
| 6 | 云侧配置更新后需**退出华为账号重登** | 已验证过 |

### 额外注意：主键不能自增

官方示例明确：`id TEXT PRIMARY KEY` + `util.generateRandomUUID()`，**禁止自增主键**（端云同步要求跨设备唯一）。

我们的 `unit_id` 本来就是 `<workspace>/<session>/<version>` 这种编码路径，**天然唯一** ✅

---

## 5. 实施计划

### 阶段 0：验证 Asset 方案（1–2 天）

**先证明这条路真的通，再写正式功能。**

| 验证项 | 判据 |
|---|---|
| **A1** Asset 写入与读回 | 写 7 MB 文件 → `getAsset()` 取回 → 按 path 读文件，字节一致 |
| **A2** 端云同步 | 资产能上云；**另一台设备能拉到并还原文件** |
| **A3** 云侧配置 | 数据类型 `sync_units` 的 `payload` 选 **Asset** 类型 |

> 验证页可以复用现有 `RdbCloudProbe` 的框架，把 V1 换成 Asset 测试。

### 阶段 1：正式同步功能（3–5 天）

| 模块 | 内容 |
|---|---|
| 会话扫描 | 复用 `docs/301` 的 `SessionSyncScope`（已完成，26 条判据） |
| 文件搬迁 | 会话代际文件 → `context.distributedFilesDir` |
| 元数据入库 | 每个代际一条 `sync_units` 记录 |
| 跨端还原 | 另一端拉取 → 按 Asset.path 读文件 → 写回会话目录 |
| 文件清理 | 自己做（约束 #3：端云同步不删本地资产） |

### 阶段 2：冲突与增删（3–4 天）

同一会话两端都改、删除会话、工作区映射等。

---

## 6. 需要你确认的三件事

| # | 问题 | 为什么 |
|---|---|---|
| **1** | **是否切到 Asset 架构？** | 这是官方推荐，也解决 2 MB 问题；但**表结构要重建** |
| **2** | **AGC 云侧要重建数据类型** | 新表名 `sync_units`、`payload` 选 **Asset** 类型。旧的 `syncshm`/`sync_probe` 作废 |
| **3** | **`distributedFilesDir` 里的文件谁清理？** | 官方明确"端云同步不删本地资产"，必须我们管，需要定策略（按会话删除时一并删？定期清理孤儿？） |

---

## 7. 一个务实提醒

**先别急着改正式代码**。建议按阶段 0 先写一个 Asset 验证页：

- 写 7 MB 文件到 `distributedFilesDir`
- 建 Asset 记录
- `getAsset()` 读回校验
- 看能否上云

**这一步通过再动架构**，否则可能白改一遍表结构（而官方说云侧列**只能增不能改**，试错成本高）。

---

## 8. 一句话交接

官方答复确认了我们的实测：**2 MB 是读取链路的官方限制**（"插入成功，读取失败"）。
`substr` 分片读官方不推荐；**官方推荐的是 Asset 架构**——文件留 `distributedFilesDir`、
表里只存 Asset 描述、端云同步自动带上文件（单资产支持到 50 G）。
**方案确定改用 Asset，但请先做阶段 0 验证（7 MB 文件读写 + 上云），
验证通过再重建表结构**——因为云侧列一旦实施**只能增不能改**。
