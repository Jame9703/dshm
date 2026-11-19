# 180 · APMS Connect API 接入与 1.1.3 问题查询

> 2026-10-17。目标：不再依赖 APMS Web 页面逐项点击，直接查询 `1.1.3` 的崩溃指标和 TOP 问题。

## 结论

- APMS 没有通用 CLI；正式程序化入口是 HarmonyOS 开发者中心的 **Connect API / Reports API**。
- APMS 当前提供的程序化指标接口包括 Crash、AppFreeze、Leak，以及符号表上传。
- APMS 指标接口的文档明确要求 **API 客户端认证**；现有 `D:\DSHM_AGC\...private.json` 是 Service Account，
  不能替代 API 客户端。
- 本仓已加入 `tools/apms-query.mjs` 和离线契约门禁 `tools/check-apms-query.mjs`。
- 完整堆栈、现场数据和日志下载目前没有公开 Connect API；完整日志仍需 APMS Web / DevEco Operation Analyzer，
  或由 `HiAppEvent` 自行采集并上传到自建服务。

## 接口

| 能力 | 接口 |
|---|---|
| Crash 趋势（推荐） | `POST https://connect-api.cloud.huawei.com/api/apm/openapi/v2/app/crash/overview/query` |
| Crash 汇总与 Fingerprint | `POST https://connect-api.cloud.huawei.com/api/apm/api/v1/hap/query/crash/metric` |
| AppFreeze 趋势 | `POST https://connect-api.cloud.huawei.com/api/apm/openapi/v2/app/freeze/overview/query` |
| Leak 趋势 | `POST https://connect-api.cloud.huawei.com/api/apm/openapi/v2/app/leak/overview/query` |

当前工具先接 v1 Crash 接口，因为它直接返回每个 Fingerprint 的次数、设备数、摘要和起止版本；v2 更适合趋势看板。

## 使用

API 客户端凭证必须放在仓库外，例如 `D:\DSHM_AGC\.env`：

```env
AGC_CLIENT_ID=...
AGC_CLIENT_SECRET=...
AGC_APP_ID=6917614360926110054
AGC_PROJECT_ID=101653523864823442
```

也可以直接使用开发者中心下载的 API 客户端 JSON：

```powershell
node tools/apms-query.mjs `
  --agc-client-file D:\DSHM_AGC\agc-apiclient-*.json `
  --app-id 6917614360926110054 `
  --from 2026-10-11 `
  --to 2026-10-17
```

查询 `1.1.3`：

```powershell
node tools/apms-query.mjs `
  --agc-env-file D:\DSHM_AGC\.env `
  --from 2026-10-11 `
  --to 2026-10-17
```

JSON 输出：

```powershell
node tools/apms-query.mjs `
  --agc-env-file D:\DSHM_AGC\.env `
  --from 2026-10-11 `
  --to 2026-10-17 `
  --format json
```

离线契约测试：

```powershell
node tools/check-apms-query.mjs
```

## API 接入结果

开发者级 API 客户端 `dshm-apms-reader` 已创建并授权。角色仅勾选“开发”时，APMS 与 `publish/app-id` 都返回 `403`；
改为“管理员”后，Token、`publish/app-id` 与 APMS Crash v1 均成功。

2026-10-17 API 实测：

- v1 Crash：`200 OK`
- v1 AppFreeze：`200 OK`
- v2 Crash/Freeze/Leak：仍为 `404`，当前不可依赖
- AppFreeze v1 的 Header 是大小写敏感的 `appid`，不是 `appId`

API 请求 ID：`5ef8f6cb8e8c4c46aaf23ae03cdfa2c4`

## 1.1.3 API 读数

时间范围：`2026-10-11` 至 `2026-10-17`；应用版本：`1.1.3`。

| 指标 | API 读数 |
|---|---:|
| 崩溃次数 | 148 |
| 启动次数 | 2526 |
| 崩溃率 | 约 5.8%（本次查询 5.8591%，刷新后 5.82%） |
| 崩溃设备数 | 7 |
| 启动设备数 | 389 |
| 应用冻屏 | 0 次（startCount 2530 / deviceCount 389） |

页面同时刻显示崩溃率约 `5.836%`，总次数/设备数一致，属于采样刷新与启动计数变化。

## 1.1.3 Crash API 指纹

| 排名 | 信号摘要 | 次数 | 设备数 | 版本跨度 |
|---:|---|---:|---:|---|
| 1 | `SIGSYS(SYS_SECCOMP) syscall number is 425` | 112 | 1 | `1.1.2 ~ 1.1.3` |
| 2 | `SIGILL(ILL_ILLOPC)` | 24 | 3 | `1.1.2 ~ 1.1.3` |
| 3 | `SIGABRT(SI_TKILL)` | 9 | 2 | `1.1.1 ~ 1.1.3` |
| 4 | `SIGSEGV(SEGV_MAPERR)@0x4fb563ac` | 2 | 1 | `1.1.3 ~ 1.1.3` |
| 5 | `SIGSEGV(SEGV_MAPERR)@0x22c06116f8` | 1 | 1 | `1.1.3 ~ 1.1.3` |

系统调用号 425 在 arm64 上是 `io_uring_setup`。本仓 `docs/50` E42 记录过同一 seccomp 行为：
鸿蒙不返回错误，而是直接以 `SIGSYS` 杀进程。API 的该 Fingerprint 跨 `1.1.2 → 1.1.3`，
不能仅凭此条断言当前 `+dshm.67` 仍会触发；需要用具体构建号/Fingerprint 继续归因。

## APMS Web 当前版本 TOP 列表

页面把 TOP 问题进一步限定为 `1.1.3 ~ 1.1.3`，显示：

| 排名 | 故障模块 | TOP 问题内发生次数 | 影响设备数 |
|---:|---|---:|---:|
| 1 | `/data/storage/el1/bundle/libs/arm64/libqemu-system-aarch64.so(tcg_region_init+1944)` | 8（61.5385%） | 2（15.3846%） |
| 2 | `/data/storage/el1/bundle/libs/arm64/libqemu-system-aarch64.so`，地址 `0x17524ac` | 3（23.0769%） | 2（15.3846%） |
| 3 | `/data/storage/el1/bundle/libs/arm64/libnode.so.137`，地址 `0x536a110` | 2（15.3846%） | 1（7.6923%） |

API 的 Fingerprint 汇总与页面的“问题特征ID”不是同一个字段，不能用 API fingerprint 直接替换页面的问题特征ID。
页面当前版本 TOP 仍以 QEMU `tcg_region_init` 为第一优先；API 侧跨版本汇总则显示 `SIGSYS 425` 次数最多。

## 首个问题个例

- 时间：`2026-10-16 16:54:53`
- 应用：`com.dshm.dshclient` / `1.1.3` / build `1010003`
- 设备：`VDE-AL10`，`7.0.0.109(SP6C00E105R3P5)`
- 类型：`CPP_CRASH`
- 错误：`SIGABRT` / `SI_TKILL`
- 前台状态：否
- 崩溃模块：`libqemu-system-aarch64.so(tcg_region_init+1944)`

堆栈从 libc `raise` / `abort` 进入 `tcg_region_init`，再经 `accel_*`、`libkoffi.so`、Node worker 线程。
这与 `docs/154` 记录的 QEMU TCG 初始化路径一致；完整堆栈和现场数据继续以 APMS 详情页为准。

## 下一步

1. 用 APMS 页面当前版本 TOP 的 3 个问题特征ID 下钻完整堆栈，优先处理 QEMU `tcg_region_init`。
2. 对 `SIGSYS 425` 补充构建号维度，确认它来自旧 1.1.2/早期 1.1.3 测试件还是当前包。
3. 如需自动拉完整堆栈与现场数据，接入 `HiAppEvent` 采集通道；不要依赖 APMS Web 内部接口。
