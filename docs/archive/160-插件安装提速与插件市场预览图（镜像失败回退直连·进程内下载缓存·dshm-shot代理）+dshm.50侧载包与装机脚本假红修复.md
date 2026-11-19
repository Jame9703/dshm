# 160 插件安装提速与插件市场预览图 + 本批侧载件与装机脚本假红修复（`+dshm.50`）

## 结论

本轮三件事，都是用户在 PC 档真机上手测报出来的，各自修在**唯一一处**根因上；
末尾同批出了 release 侧载件并覆盖装到 PC 2in1 上（§5、§7）。

1. **GitHub 地址装插件太慢** —— 根因是**下载点没吃到镜像**：出网镜像改写只长在
   `globalThis.fetch` 那条路上（`fetch-shim.js` 的 `onceFetch`），而插件安装器
   （`dshm-installer.js`）用自己的 `node:https` 拉 codeload tarball，**压根不经过**那条路
   ⇒ 一直直连。真机实测同一个 4.6 MB tarball：直连 **2m39s**、经镜像 **16.65s**。
   另外把「镜像失败」这条路补成**回退直连**（镜像不是上游：它有自己的配额，也会按出口 IP
   拦人）。见 §1。
2. **插件市场不显示预览图** —— 根因是**出网身份**：`dshmarket` 的缩略图 / 灯箱原图直接由
   页面去 `img` 那些图床地址，而端侧 WebView 那条出网链**既不走镜像也不走宿主**；同一个 URL
   在宿主进程里 1.15–3 s 就能拿到。修法是宿主新增 `/dshm-shot` 本地代理 + 市场就地改写
   两处 URL（幂等、锚点唯一、装完重放）。见 §2。
3. **皮肤市场安装慢** —— 根因是**同一个 URL 下两遍**：市场 CLI 链路先做 `prefetch()`
   隔离预取（`--dir <临时目录>`），再对 live profile 正式落位，两跳都落到同一个
   `fetchBuffer()`。修法是进程内下载缓存（TTL 120 s / 32 MB / 8 项 / LRU + 命中打一行
   日志）。真机口径下皮肤一次安装从 ~131 s（直连）/~36 s（镜像）降到「第二遍 ~1 s」。
   见 §3。

`coreVersion` → **`+dshm.50`**。

## 1. GitHub 地址装插件太慢：下载点补齐镜像改写 + 镜像失败回退直连

### 1.1 现场

用户：「通过插件入口输入插件项目地址，提示无法识别这个包名或地址」修好之后
「github 地址安装插件，速度有点太慢了，此前也是这个调用的，没这么慢」。

### 1.2 两处改动

**① 下载点显式过镜像（判据单份）**。`fetch-shim.js` 新增导出 `mirrorUrlFor(urlStr)`：
纯函数、**不改写就原样返回**、带 `new URL` 的失败回退；开关 `DSHM_FETCH_MIRROR=0`、
表外主机、前缀不可解析这三条与 `onceFetch` 里那一跳**逐条同源**（它刻意不接受
`lookup` —— 那是上游 `web_fetch` 的 SSRF「DNS 钉住」才有的参数，安装器没有这条语义）。
镜像表同时补上 `codeload.github.com`（**装插件 / 装皮肤真正下字节的那台**）。

本文件**不自己维护第二张表**：两份判据迟早漂移，所以 `dshm-installer.js` 只
`require('./fetch-shim.js')` 拿 `mirrorUrlFor()`。

**② 镜像失败回退直连**。镜像不是上游 —— 实测同一时刻本机出口对
`https://gh-proxy.com/...`（raw 与 codeload 都一样）一律 `403 Access to this resource is
forbidden.`，而两个原站直连都是 200。若把改写当硬重定向，那是把「直连能通但慢」换成
**「直接不通」**，比不改还坏。

回退条件两条：**连接层失败**（超时 / ECONNRESET / TLS）与**镜像给的 4xx/5xx**。
后者是关键的一条：镜像的 403/429 是**它自己的话**，直接透给调用方，上游就会把
「镜像限流」误判成「资源不存在」（装插件那条链真的会这样分诊）⇒ 回退后的结果才是权威
（上游真 404 时它会照常回 404）。回退面刻意只覆盖**能重放**的请求：
`method` 是 GET/HEAD，或者 body 是已知长度的 buffer（`encoded.stream` 为空）；
流式 body 回退会重发一个已经被读掉一半的体 ⇒ 宁可不退。回退时**取消废弃镜像的响应体**。

顺带订正 `httpGet()` 的失败文案：必须带原因短语（`HTTP 404 Not Found：<url>`），
因为上游 `classifyInstallFailure` 的 `LOG_KINDS` 正是靠 `404 Not Found` 这类形态判
not-found；只写 `HTTP 404：<url>` 会掉进 unknown ⇒ 用户看到的是通用文案而不是
「未找到相关插件」。文档里那句「实测 codeload 直连可用」也一并订正 ——
它只验了「拉得下来」、没量速度，被当成了「网络没问题」的依据。

## 2. 插件市场不显示预览图：`/dshm-shot` 宿主代理

宿主 `main.js` 新增 **`/dshm-shot?url=…[&h=…]`**：仅 `127.0.0.1`、**不需要 token**、
https 白名单、10 MB 上限、`Cache-Control: max-age=86400`；启动阶段落一行读数
`BOOT_64_SHOT_PROXY`。

市场侧由 `dshmarket` 的两处 URL 改成走该代理（`dshm-market-bridge` 的
`patchDshmarketThumbs()`）：**卡片缩略图**与**灯箱原图**，日志分别落
「缩略图出网改为宿主代理（/dshm-shot）」「灯箱原图改为宿主代理（/dshm-shot）」。
纪律与皮肤市场那处改写同源：幂等（目标形态逐字节不写）、锚点唯一才写、不改 `.map`。

时机上复用 `docs/159` 的**装完重放**：`dshm-market-patch.cjs` 在安装成功、
`<id>.done` 写出之前，同时重放 `patchMarketCliBranch()`（皮肤市场挂载契约）与
`patchDshmarketThumbs()`（预览图出网）。

## 3. 皮肤市场安装慢：进程内下载缓存

`fetchBuffer()` 前挂一层 LRU：`DOWNLOAD_CACHE_TTL_MS = 120 s`、
`DOWNLOAD_CACHE_MAX_BYTES = 32 MB`、`DOWNLOAD_CACHE_MAX_ITEMS = 8`、key = **原 URL**
（不是镜像 URL —— 否则开关一抖就整片失效）。单条超上限则**不入缓存**（宁可不下缓存，
也不把内存顶起来）；命中即刷新（LRU 重排）。命中时打一行，
这是「同一个包为什么第二次装得快」的唯一直接证据：

```
DSHM 下载缓存命中（<n> B，<n> s 前下的同上一个 URL）：<url>
```

## 4. 本批产物（`+dshm.50`）

| 件 | 大小 | sha256 |
|---|---|---|
| 核心容器 `dist/core/dsh-core-0.2.1-alpha.2+dshm.50-openharmony-arm64.zip` | 60,951,154 B | `eb9f7fbfee202845afe82893087f17a3d291c51cab9d3625f808e6ddbaeb072a` |
| release 侧载件 `dist/sideload/DSHM-1.1.2-core0.2.1-alpha.2+dshm.50-arm64-signed.hap` | 403,669,981 B | `021E8E1CA24FC1F9569A20254CCAF0FEB5B20D082552E5C4452CB27743E71EDB` |

版本面：`1.1.2` / `1010002` / `minAPIVersion=60101024` / `targetAPIVersion=260000026` /
`deviceTypes = phone,tablet,2in1` / **权限恒 8 条** / 随包核心 zip 为 `+dshm.50`；
实读包内 `module.json` 的 `debug=false`（release 构建 + 调试签名 ⇒ 可 `install -r`）。
`+dshm.46/47/48/49` 的四件在 `dist/sideload/` 里留档。

## 5. 装机脚本假红修复（release 件的 exec 判据分档）

`tools/update-device.ps1` 第 8 步原来对 PC/2in1 用的是一条**不分档的强判据**
（要求 `python3.12 / git / rg / ash / bash` 全 `=ok`）。这在 release 构建件上是
**必然假红**：release 档应用域是 `u:r:normal_hap:s0`（debug 档是 `debug_hap`），
应用数据区的可执行文件被平台拒（`EPERM`）属**预期**，见 `docs/140` / `docs/154` /
`docs/155`；而自 `docs/155` 起三端终端与 bash 统一走 guest VM，宿主 `execve` 已**不是**
产品依赖路径。

修法是**读包内 `module.json` 的 `debug` 标志**（第 4 步末尾，`$hapDebug`：
`true` / `false` / `$null`，读不到按**从严**），第 8 步改为三态：

- 全 `=ok` ⇒ 通过（debug 件的强判据不变）；
- `$hapDebug -eq $false` 且 `toybox=ok` ⇒ **通过**，并打出未通项属 release 域降级；
- `$hapDebug -eq $false` 但 `toybox` 也未 ok ⇒ FAIL；其余走原「未全通」FAIL。

同时订正第 3 步的注释/文案：默认 debug 构建是**端侧调试用**，交付件是 release 构建，
须走 `-Hap <dist/sideload/…> -SkipRebuild`。**假红与假绿同等有害** ——
一条永远红的判据会让人学会忽略它。

## 6. 真机读数（PC 2in1 `86E0226429000417`）

- 覆盖安装（`install -r`，**未卸载**）成功；`files/dsh/home` 指纹 `links=9 size=3440`
  **前后不变**（用户数据未动）；核心树实读 `+dshm.50`。
- `host-ready.json`：python 桥 `ready / stdlib=true / selftest=ok / stdout=2`。
- `node-output.log` 三行：`dshm-vm-bash` 已接管 `ctx.subprocess.spawn` 与
  `spawnTerminal`（三端同步走 guest VM），**按需冷启动**（首条 bash / 终端请求时才拉 VM）。
- `vm/` 下有 `rootfs.qcow2` 54,001,664 B、`serial.log` 16,965 B、`shared-roots.json`
  ⇒ VM 确曾运行。
- exec 探针：`python3.12=fail(EPERM)`、`rg / ash / bash = fail(EPERM)`、`git* = 缺`、
  `toybox=ok`；`terminal.hostDomain=u:r:normal_hap:s0`、`realShell=yes`、
  `libsExec=err(EACCES)` ⇒ 正是 §5 里那条「release 域降级」读数。

## 7. 门禁

本会话实跑全绿：`check-fetch-mirror.cjs`（镜像表内/表外/开关/DNS 钉住/前缀不可解析回退）、
`check-fetch-shim.cjs`（jitless 下 9 项，含流式体保真与对照臂）、
`check-permission-surface.mjs`（8 条、已删三条 0 命中）、
`check-no-apk-surface.mjs`（0 命中）、`check-install-spec-normalize.mjs`（含对照臂）、
`check-core-openharmony-patches.mjs`（212/0）、`check-market-bridge.mjs`（140/0，
含 `/dshm-shot` 路由接线 M6a–M6d）、`check-dshm-installer.cjs`（含 9a₂ 缓存断言与第 10 段
镜像回退）、`check-doc-refs.mjs`。

## 8. 未做 / 待验

- 用户手测四项：GitHub 地址装插件速度、皮肤一次安装看 `DSHM 下载缓存命中` 行、
  插件市场预览图出图、终端与冷启动回归。
- 手机 / 平板档本批**未复验**（上一批 `+dshm.49` 见 `docs/159`）。
- AGC 上架 `.app` 本批**未出**（用户本轮只要侧载件）。

**未 commit / 未 push。**
