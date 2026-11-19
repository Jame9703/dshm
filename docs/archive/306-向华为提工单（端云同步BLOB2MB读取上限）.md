# 306 · 向华为官方提工单：端云同步 BLOB 2MB 读取上限

> 日期：2026-10-30 ｜ 用途：**直接复制发给华为开发者支持**
>
> 本文是给官方的技术问题单，尽量只给事实与可复现步骤，不含推测。

---

## 一、问题摘要（一句话）

使用 ArkData 关系型数据库端云同步（`cloudSync` + `DISTRIBUTED_CLOUD`）时，
**单个 BLOB 字段超过 2 MB 就读取失败**，报 `SharedBlock over 2MB`。
写入是成功的——`SELECT length(payload)` 能返回正确字节数，只有"读出 BLOB 本体"失败。

**想知道：**

1. 这是否是 ArkData 的**已知设计限制**？
2. 如果是，**官方推荐的超大字段存储方案**是什么？
3. **端云同步传输时是否也受同一限制**？

---

## 二、环境

| 项 | 值 |
|---|---|
| 设备 | 华为云调试设备（HarmonyOS 6.x / API 26） |
| DevEco / SDK | `apiVersion=26`、`platformVersion=26.0.0`、`26.0.0.105` |
| 应用包名 | `com.dshm.dshclient` |
| 应用版本 | 1.1.6 (1010007) |
| 签名 | release 证书 |
| 使用 API | `@ohos.data.relationalStore`（ArkData / CoreFileKit 族） |

---

## 三、复现步骤

### 3.1 应用侧配置（已按官方文档完成）

**① `AppScope/app.json5` 开启端云同步**

```json5
{
  "app": {
    "bundleName": "com.dshm.dshclient",
    "cloudStructuredDataSyncEnabled": true
  }
}
```

**② 建库建表**

```ts
const config: relationalStore.StoreConfig = {
  name: 'DSHM.db',                          // AGC 容器名 = DSHM
  securityLevel: relationalStore.SecurityLevel.S1
};
const store = await relationalStore.getRdbStore(context, config);

await store.executeSql(
  `CREATE TABLE IF NOT EXISTS sync_probe (` +
  'unit_id TEXT PRIMARY KEY, ' +
  'workspace TEXT, ' +
  'session_id TEXT, ' +
  'version INTEGER, ' +
  'sha256 TEXT, ' +
  'bytes INTEGER, ' +
  'updated_at INTEGER, ' +
  'payload BLOB' +          // ← 问题字段
  ')'
);
```

> 注：按官方要求，**字段均未设 NOT NULL**，主键为 `unit_id` 且已在 AGC「端侧去重主键」中勾选。

**③ 声明云端分布式表**

```ts
await store.setDistributedTables(
  ['sync_probe'],
  relationalStore.DistributedType.DISTRIBUTED_CLOUD,
  { autoSync: true }
);
```

**④ AGC 侧配置**

- 容器名：`DSHM`
- 本地表名称：`sync_probe`
- 字段：`unit_id(String) / workspace(String) / session_id(String) / version(Integer) / sha256(String) / bytes(Integer) / updated_at(Integer) / payload(Bytes)`
- 端侧去重主键：`unit_id`
- 已**实施变更到生产环境**

### 3.2 复现动作

对一个**单个 BLOB 字段**依次写入不同大小的数据，然后读回：

```ts
// 写入
const buf = new Uint8Array(size);          // size = 1MB / 1.5MB / 2MB / 3MB / 5MB / 7MB
await store.insert('sync_probe', { unit_id: id, payload: buf, ... });

// ① 查长度（不取 BLOB 本体）
const rs1 = await store.querySql(`SELECT length(payload) AS n FROM sync_probe WHERE unit_id='${id}'`);
// 结果：能正确返回 size ✅

// ② 读 BLOB 本体（querySql）
const rs2 = await store.querySql(`SELECT payload FROM sync_probe WHERE unit_id='${id}'`);
const got = rs2.getBlob(rs2.getColumnIndex('payload'));   // ← 这里失败

// ③ 读 BLOB 本体（query + RdbPredicates）
const pred = new relationalStore.RdbPredicates('sync_probe').equalTo('unit_id', id);
const rs3 = await store.query(pred);
const got2 = rs3.getBlob(rs3.getColumnIndex('payload'));  // ← 同样失败
```

---

## 四、实测结果

| BLOB 大小 | ① 写入 `insert` | ② `SELECT length()` | ③ `querySql` 读 BLOB | ④ `query` 读 BLOB |
|---|---|---|---|---|
| 1 MB | ✅ 成功 | ✅ 正确 | ✅ 成功 | ✅ 成功 |
| **1.5 MB** | ✅ 成功 | ✅ 正确 | ✅ **成功** | ✅ 成功 |
| **2 MB** | ✅ 成功 | ✅ 正确 | ❌ **失败** | ❌ **失败** |
| **3 MB** | ✅ 成功 | ✅ 正确 | ❌ 失败 | ❌ 失败 |
| **5 MB** | ✅ 成功 | ✅ 正确 | ❌ 失败 | ❌ 失败 |
| **7 MB** | ✅ 成功 | ✅ 正确 | ❌ 失败 | ❌ 失败 |
| 10 MB | ✅ 成功 | ✅ 正确 | ❌ 失败 | ❌ 失败 |

**关键观察**：

- **写入全部成功**，`length()` 返回的字节数完全正确 ⇒ **数据确实完整存进了库**
- **只有"读出 BLOB 本体"在 ≥2 MB 时失败**
- `querySql` 与 `query` **两条路径表现一致**（都失败）

---

## 五、日志

```
W/C01650/com.dshm.dshclient/ShareBlock: ResetStatement:over 2MB[1, 0]
E/C01650/com.dshm.dshclient/SqliteStatement: FillBlockInfo:ResetStatement Failed.
E/C01650/com.dshm.dshclient/SqliteSharedResultSet: ExecuteForSharedBlock:Fill shared block failed, ret is 27394048
```

`ret is 27394048`，`ShareBlock` 明确指出 **over 2MB**。

---

## 六、我们的疑问（请官方答复）

### Q1：这是否是已知限制？

ArkData 的 `ResultSet` 通过 **SharedBlock（共享内存块）** 传数据，
看起来单块上限为 **2 MB**。

请确认：

- 这个 2 MB 是否为**硬限制**？
- 是否有官方文档说明？我们没找到明确出处。

### Q2：有没有绕开的**官方推荐**方式？

我们已验证 **SQLite `substr()` 对 BLOB 可以按字节切片**：

```sql
SELECT substr(payload, 1, 1048576)      FROM sync_probe WHERE unit_id='...';
SELECT substr(payload, 1048577, 1048576) FROM sync_probe WHERE unit_id='...';
```

分片读出后重组，数据完整一致（本地 SQLite 验证通过）。

**请确认这种做法在端侧 RDB 上是否受支持、是否推荐。**
如果有更合适的官方方案（例如 `getValue` 的其他重载、流式读取、
或 `Assets` 类型存大文件），请指出。

### Q3：**端云同步传输时是否也受 2 MB 限制？**

这一点对我们最关键。

我们观察到：`setDistributedTables` 与 `cloudSync` 调用本身没有报 2 MB 相关错误，
但**尚未在另一端验证大字段是否真的同步过去了**。

请确认：

- 端云同步上传/下载时，单行单字段是否有大小上限？
- 如果有，**上限是多少**？是否也是 2 MB？
- 超限时是**静默截断**还是**报错**？错误码是什么？

### Q4：大数据量场景的**官方推荐架构**

我们的场景：需要在应用私有云存储里同步"会话记录"——
每个会话是一个不可变的压缩日志文件，**平均 1.1 MB、最大约 7 MB**，
单用户目前约 13 个文件、共 14.7 MB。

请给出官方推荐做法：

| 方案 | 是否推荐 |
|---|---|
| RDB + BLOB 整条存 + 分片读 | ? |
| RDB + 把大文件切成多条记录（每片一条） | ? |
| 改用 `Assets` / `ASSETS` 类型 | ? |
| 改用云存储（CloudStorage）存文件 + RDB 只存元数据 | ? |
| 其他 | ? |

---

## 七、补充：我们也试过但**不适用**的方案

| 方案 | 结论 |
|---|---|
| `cloudStorage`（CloudFoundationKit） | 报 `1008221001 Server error` / `GetDefaultBucket result error`，需要开发者自建 bucket；且它是**应用私有存储**，不是用户云空间 |
| Drive Kit | 官方页面标 Android / Web，**鸿蒙原生支持情况未确认** |
| 端云同步（本文方案） | 已跑通到"数据能写、能查长度"，但**读大 BLOB 失败** |

---

## 八、期望的答复形式

1. Q1 的确认（2 MB 是否为硬限制 + 文档出处）
2. Q3 的明确答复（端云同步是否有同样限制、上限多少、超限行为）—— **这项最关键**
3. Q4 的推荐架构

---

## 九、备注

- 我们已确认 `cloudStructuredDataSyncEnabled` 生效：加入前系统报
  `GetCloudSyncInfo: load schema fail`，加入后该错误消失。
- 我们也已确认 `autoSync` 在 `DistributedConfig` 而非 `StoreConfig`
  （本机 API 26 SDK 的 `StoreConfig` 中没有 `autoSync` 字段，
  与部分官方示例写法不同），请确认哪个是正确的？
