# 117 远程执行主机：飞牛 NAS（Docker）施工单

> **读者**：飞牛 NAS 上的施工 Agent（下称 **Hermes**）+ 本仓维护者。
> **动手前必须先读 §0（交付边界）与 §2（事实基线）**——本单的所有参数都是从上游代码里读出来的，
> 不是猜的；照抄即可，但**不要自行"改良"参数**（每一处偏离都对应 §5 的一条红线）。
>
> **上游版本口径**：`@deepseek-ai/dsh@0.2.1-alpha.1`（与本仓钉的版本一致，出处 `docs/10-协议兼容事实基线.md` §8.7.25）。
> 本单不涉及本仓的端侧核心树——**NAS 用的是上游 npm 包**，见 §3.3 的"陷阱一"。

---

## 0. 交付边界（先读这一节，不要跳过）

### 0.1 本单要解决的唯一问题

手机档（手机 / 平板）**无法创建进程**（`execve` 被 OpenHarmony 拒绝，判决见 `docs/104-手机档终端与bash能力判据.md`），
因此 `bash`、真终端、真 `execve` 在手持档**本机无解**。
唯一的出路是把**执行**搬到另一台机器：**NAS 当执行主机，手机当客户端**。

本单交付的是**执行主机侧**，也就是 NAS 上那一半。

### 0.2 Hermes 负责 / 不负责

| | 内容 |
|---|---|
| ✅ **Hermes 负责** | ① Docker 镜像与容器（§3.3 / §3.4）；② 目录与卷布局（§3.2）；③ 启动参数（§3.5）；④ 网络入口 ingress（§3.6）；⑤ 设备与 ACL（§3.7）；⑥ 跑完 §4 的验收并把读数贴回；⑦ 运维脚本（§6） |
| ❌ **Hermes 不负责** | ① 不改本仓任何代码；② 不改手机 App；③ **除 §3.3 那唯一一处注入外，不碰上游任何文件**；④ 不"顺手"改端口 / 绑定点 / 目录；⑤ 不做 §5 禁做清单里的任何一条 |

### 0.3 本单做完时能到什么状态（以及**到不了**什么状态）

- ✅ **能达到**：NAS 上有一条**只监听 `127.0.0.1:3111`** 的 dsh Host（LAN 里任何设备都碰不到它），
  经 tailnet 入口只对**你自己的设备**暴露；§4 的验收（含正/反控制组）全部通过。
- ❌ **达不到（本单不含）**：**手机 App 里"连上 NAS 并跑通 bash"的端到端验收**。
  手机端接入本身**零代码改动**（§7.1），但验收必须在手机上做，属于 §7 的范围。
  **Hermes 不要把"验收通过"写成"手机能用了"**——这两件事不是一件事。

### 0.4 三个必须先确认的事实（任一不成立就**停下并报告**，不要猜着往下做）

| 编号 | 要确认的事实 | 确认命令（在 NAS 上跑） | 不成立时 |
|---|---|---|---|
| **C1** | fnOS 上有可用的 Docker **与 compose** | `docker version` + `docker compose version` | 停下报告；退回 §6.5 的"裸进程 + systemd"备选 |
| **C2** | NAS 能加入 tailnet（**首选**入口的前提） | `tailscale status`（或按 §3.6.1 安装） | 走 §3.6.2（Cloudflare Tunnel + Access）备选 |
| **C3** | 入口方案已由用户拍板 | —— | 停下问用户；**默认 Tailscale serve** |

---

## 1. 目标架构

```
┌─────────────────────── 手机 / 平板（DSHM 客户端，不改代码）───────────────────────┐
│  ConnectPane「远程 Host（可选）」                                                │
│  ① 粘贴启动 URL（含 ?token=）→ 同时完成地址配置与授权                            │
│  ② 或手输 host:port + token                                                     │
│  之后：HTTP(/api/*) + WebSocket(/api/remote.mux)、Cookie 会话                    │
└───────────────────────────────────┬─────────────────────────────────────────────┘
                                    │  https://<nas>.<tailnet>.ts.net/  （WireGuard + TLS）
                         ┌──────────▼──────────────────────────────┐
                         │  tailnet（只有你自己的设备在这个网里）  │
                         │  ACL：手机（→ 以后加平板）              │
                         └──────────┬──────────────────────────────┘
                                    │  tailscale serve（在 NAS 上终结 TLS，回落到 loopback）
┌───────────────────────────────────▼──────────────────────────────────────────────┐
│  飞牛 NAS（x86_64 / N100 / Debian 12 / 内核 6.18.18.c1107-trim）                  │
│                                                                                  │
│   ┌── 容器 dsh（network_mode: host，非 root，cap_drop ALL）──────────────────┐   │
│   │  dsh web --no-open --host 127.0.0.1 --port 3111                          │   │
│   │         --public-url https://<nas>.<tailnet>.ts.net/                     │   │
│   │         --trusted-host <nas>.<tailnet>.ts.net                            │   │
│   │                                                                          │   │
│   │  监听 127.0.0.1:3111  ← 只在宿主 loopback 上，LAN 不可达                 │   │
│   │  卷 /data/dsh  = $DSH_HOME（会话 / 设置 / 凭据 / 插件 / 工作区注册表）    │   │
│   │  卷 /workspace = 干活的工作区目录                                        │   │
│   └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│   192.168.2.88 的 LAN 侧：**什么都不开**（没有 0.0.0.0 绑定，没有端口映射）       │
└──────────────────────────────────────────────────────────────────────────────────┘
```

**三条设计理由（照做即可，不要改成"更简单"的样子）**：

1. **dsh 只绑 `127.0.0.1`**：上游的 `/api` 前面有一道 *Host/Origin 信任栅栏*，它的设计前提就是
   "Host 只在 loopback 上，跨设备要靠一层隧道把出口落回 loopback"。绑 `0.0.0.0` 会被上游 CLI **直接拒绝**
   （见 §2 第 3 条），而且等于把"远程代码执行"暴露到网络上——这正是本项目 `docs/00-开发任务书.md` §3 拒绝的做法。
2. **入口在 NAS 上终结，出口回 loopback**：`tailscale serve` 把 `https://<nas>.<tailnet>.ts.net/` 转成
   `http://127.0.0.1:3111`。请求带着 `Host: <nas>.<tailnet>.ts.net` 到达 dsh，**不需要改写任何头**。
3. **栅栏靠它自己的配置口放行**：`--trusted-host <authority>` 是上游**自己提供的**参数
   （原文："extra authority the /api browser-trust fence accepts… grants no trust"）。
   ⇒ 我们没有关掉任何检查，只是**声明**了这个部署会服务的 authority。

---

## 2. 事实基线（全部读自上游代码，带出处）

| # | 事实 | 读数 | 出处 |
|---|---|---|---|
| 1 | `dsh web` 就是 `dsh --profile web` | `dsh <name>` 是 `dsh --profile <name>` 的简写 | `@deepseek-ai/dsh/lib/bin.js`（帮助文本："dsh web  boot the web profile"） |
| 2 | web 档的参数面 | `--host <host>` / `--port <port>`（`0` = 让 OS 选）/ `--public-url <url>` / `--trusted-host <authority...>`（**可重复**）/ `--no-open` | `@deepseek-ai/dsh-web-app/lib/startup.js` |
| 3 | **`--host 0.0.0.0` 被上游明确拒绝** | `error: --host 0.0.0.0 is intentionally not supported yet for safety: it would expose remote code execution to the network; use 127.0.0.1 instead` | 同上（CLI 校验分支） |
| 4 | webserver 的绑定字面量只有两个 | `host: z.union([z.const("127.0.0.1"), z.const("0.0.0.0")]).required()` | `@deepseek-ai/dsh-host-webserver/lib/index.js` |
| 5 | web 档默认 `host` / `port` | `127.0.0.1` / **`3080`**（本单**故意**改用 `3111`，与 §4 的验收命令保持一致） | `@deepseek-ai/dsh-web-app/cordis.patch.yml`（行 id = `webserver`） |
| 6 | `/api` 的信任栅栏规则 | ① `Host` 头缺失/不可解析 ⇒ 拒；② 主机名是 loopback（`localhost` / `[::1]` / 整个 `127/8`）**或**命中 `trustedHosts` ⇒ 通过，否则拒；③ `sec-fetch-site: cross-site` ⇒ 拒；④ 带了 `Origin` 就必须与 `Host` **同源**（`new URL(origin).host === hostUrl.host`） | `@deepseek-ai/dsh-client-connection/lib/index.js` 的 `isTrustedApiRequest()` |
| 7 | 栅栏与认证的分工 | 先栅栏（**403**），再浏览器会话认证（**401**） | 同文件 `requestRejection()` |
| 8 | `trustedHosts` 的形态 | 必须是**裸 authority**（`host` 或 `host:port`）且能原样通过 WHATWG 解析；**无端口项匹配任意端口** | 同文件 `assertTrustedAuthority()` / `isTrustedAuthority()` |
| 9 | `trustedHosts` 从哪来 | 配置默认 `[]`；`--trusted-host` 注入；**只有**当 `webServer.host === '0.0.0.0'` 时才会自动追加"本机所有非内部 IPv4 字面量" | `dsh-web-app/lib/index.js` 的 `resolveLanTrust()` |
| 10 | 启动横幅（唯一拿 token 的地方） | `dsh web: <带 token 的 URL>[ (LAN: <LAN URL>)]`，**每个进程只打印一次** | `dsh-web-app/lib/index.js` |
| 11 | `--public-url` 的作用 | 只改"对外公布/打印/`DSH_WEB_URL`"的根 URL，**不授予任何信任**（信任必须另外用 `--trusted-host` 声明） | `startup.js` 参数说明 + `dsh-web-app/lib/index.js` |
| 12 | 状态都在 `$DSH_HOME` | `profiles/<名>`、`storages/`（含工作区注册表）、`.credentials.yaml`、插件与安装队列 | `docs/50` §3 / `docs/107` §队列目录 / `docs/113` §1 |
| 13 | 启动期**必须**能加载的原生件 | `node-addon-require-builtin`（缺了直接 `host preparation failed` 致命退出）；npm 侧提供 `node-addon-require-builtin-linux-x64-gnu` 预编译包 | 启动失败路径 + `node-addon-require-builtin` 的 `optionalDependencies` |

> **第 6 条的第 ④ 项是本单最容易被忽略、也最容易导致"手机连上但 WS 永远连不上"的一条**。
> 详见 §3.3 与 §4 的 V5/V6/V7。

---

## 3. 施工步骤（严格按顺序；每步都有"停下点"）

### 3.1 前置检查

```bash
# C1：Docker 与 compose
docker version --format '{{.Server.Version}}'
docker compose version

# CPU 架构必须是 x86_64（本单只覆盖 x86_64）
uname -m                      # 期望：x86_64

# 关键端口必须空闲（3111 被占就换一个，并同步改 §3.4 / §3.5 / §4）
ss -lntp | grep -E ':(3111)\b' || echo '3111 空闲 OK'

# C2：tailnet（走 §3.6.2 时跳过）
tailscale status --json | head -c 400
```

**停下点 D1**：`uname -m` 不是 `x86_64`，或 Docker/compose 不可用 ⇒ 停下报告（不要改架构假设）。

### 3.2 目录与卷布局

```bash
# 全部落在 /srv/dsh 之下，便于备份与卸载（不散落到系统目录）
sudo mkdir -p /srv/dsh/{home,workspace,config}
sudo chown -R 10001:10001 /srv/dsh/home /srv/dsh/workspace   # 与镜像里的 uid/gid 对齐，见 §3.3
sudo chmod 700 /srv/dsh/home                                 # 里面有凭据与会话
```

| 宿主路径 | 容器路径 | 内容 | 丢了会怎样 |
|---|---|---|---|
| `/srv/dsh/home` | `/data/dsh` | `$DSH_HOME`：会话、设置、**模型凭据**、插件、工作区注册表 | **不可恢复**（等同端侧 el2 数据）⇒ 必须纳入备份 |
| `/srv/dsh/workspace` | `/workspace` | 真正干活的项目目录 | 看你放什么；建议同样备份 |
| `/srv/dsh/config` | `/opt/dshm`（**只读** `:ro`） | `compose.yaml`、`Dockerfile`、注入脚本、验收探针（§4 的 V10 要在容器里跑） | 可重建 |

> **数据纪律（对应本仓 `AGENTS.md` 的真机数据条款）**：`/srv/dsh/home` 是**用户数据**。
> 任何"重装"动作都必须保留它：**永远不要** `docker compose down -v`，**永远不要** `rm -rf /srv/dsh/home`。
> 容器重建（`up -d --force-recreate`）不会动卷里的数据，这是允许且推荐的升级方式。

### 3.3 镜像

**陷阱一（最容易踩的一条）**：**不要**把本仓 `entry/src/main/resources/resfile/dsh-core-*.zip` 里的核心树
搬到 NAS 上。那份树是**为 OpenHarmony arm64 裁过并把原生件换成鸿蒙移植版**的
（`hostcore/core-recipe.json`：`platform.os = openharmony`、`native` 只留 `openharmony_arm64` 的
`pty.node` / `koffi.node`）。它在本机 Windows 上连 `--help` 都跑不过，在 x86_64 Linux 上同样跑不起来。
⇒ NAS 装**它自己的上游副本**：`npm i -g @deepseek-ai/dsh@0.2.1-alpha.1`。

**陷阱二（本单唯一一处对上游的改动，必须做）**：
DSHM 的鸿蒙客户端在 WebSocket 升级时，线上 `Origin` 头是**两个逗号分隔的值**
（平台 netstack/libwebsockets 自己按 URL 推导的**丢端口**形态 + 客户端注入的同源形态），
实测形态：`Origin: http://127.0.0.1, ws://127.0.0.1:3120`。
上游 `isTrustedApiRequest()` **按整串**解析 `Origin` ⇒ `new URL("a, b").host` 永远不等于 Host ⇒
**每一次** WS 升级都被判 403（而客户端会把它报成含糊的"升级响应不是 101"）。
本仓对此的做法是在端侧核心树里注入一次"逐项比较"（`tools/pack-core.mjs` 的 `allowOriginList()`，
标记 `DSHM_ORIGIN_LIST`）。**NAS 上必须做同样的一次注入**，否则手机能连上 HTTP、但 WS 永远连不上
（= 会话流、工具调用全废）。语义边界不变：**仍然禁止跨源**，只是允许"多值里有某一项同源"。

**先证伪再施工**（这一步很重要，它证明"注入确实是为这个原因而必须的"，见 §4 的 V5）：
在**没有**注入的容器里跑 §4 的 V5，必须得到 **403**。若 V5 直接通过，说明上游已放宽，
此时**停下报告**（不要照抄一段可能已经不适用的注入）。

> **行尾注意（这条是实测出来的）**：注入脚本的两个锚点**只有 LF 一种形态**（上游 npm 产出的文件就是 LF）——
> 脚本里用 `'\t'` 转义 + `.join('\n')` 拼接来构造锚点，**不要**把它改成多行模板字面量再让编辑器/传输环节把 LF 变成 CRLF。
> 本仓就有一个同源的真实例子：`tools/pack-core.mjs` 在 `core.autocrlf=true` 的 Windows 工作区里被签出成 CRLF，
> 于是它那份**同名常量**在运行时带上 `\r`、与上游 LF 文本匹配不上（只会在"重新物化核心树"时以 `上游实现已变化` 的误导文案报出来）。
> 本单的脚本取的是**提交版（LF）**常量，已用「上游原文 ⊕ 该补丁 = 端侧树」逐字节核对过，不受影响。

`/srv/dsh/config/Dockerfile`：

```dockerfile
# 飞牛 NAS 上的 dsh 执行主机（x86_64 / Debian 12）
FROM node:22-bookworm-slim

# ① bash 是**必须**的（不是可选项）：`tool-bash` 执行的是 `bash -c <cmd>`、终端默认 shell 也是
#    `/bin/bash`，而 `node:*-bookworm-slim` 里**只有 dash**（`/bin/sh`）⇒ 不装 bash 的话
#    "手机连上了、会话也开了，但一调 bash / 一开终端就 ENOENT"。依据见 §3.3c。
# ② git 是干活的（工作区里的仓库操作），slim 里同样没有。
# ③ python3/make/g++ 只在 npm 回落到源码编译时才用得上（node-pty / koffi 通常有预编译件）。
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl tini bash git python3 make g++ \
 && rm -rf /var/lib/apt/lists/*

# 上游本体（版本与本仓钉的一致；装 pnpm 是为了手机端"插件市场"页能正常装插件）
ARG DSH_VERSION=0.2.1-alpha.1
RUN npm i -g --no-fund --no-audit \
      "@deepseek-ai/dsh@${DSH_VERSION}" \
      pnpm@9

# ── 本单唯一一处上游注入：Origin 栅栏接受"逗号分隔的多值"（逐项比较）──
# ⚠️ 注入目标**不在全局根下**（实测）：0.2.1-alpha.1 是**单包**形态，
#    `dsh-client-connection` 嵌在 `@deepseek-ai/dsh/node_modules/` 里。
#    写成 `$(npm root -g)/@deepseek-ai/dsh-client-connection/...` 必然 ENOENT。
#    这里按"从全局根递归找出那个包"来解析（两种布局都覆盖），**解不到就报错退出，不猜路径**。
COPY origin-list-patch.mjs /opt/dshm/origin-list-patch.mjs
RUN set -eu; \
      ROOT="$(npm root -g)"; \
      TARGET="$(find "$ROOT/@deepseek-ai" -path '*/dsh-client-connection/lib/index.js' -print -quit)"; \
      if [ -z "$TARGET" ]; then echo "找不到 dsh-client-connection/lib/index.js（$ROOT 下）——拒绝瞎猜路径" >&2; exit 1; fi; \
      echo "[inject] $TARGET"; \
      node /opt/dshm/origin-list-patch.mjs "$TARGET"; \
      test "$(grep -c DSHM_ORIGIN_LIST "$TARGET")" = "1"

# 非 root 运行（uid/gid 与 §3.2 的 chown 对齐）
RUN groupadd -g 10001 dsh && useradd -u 10001 -g 10001 -m -d /home/dsh -s /usr/sbin/nologin dsh
USER 10001:10001
# NARB_DISABLE_NATIVE_CACHE：只读根下必须关掉 native 加载器的"物化写盘"（上游自带开关，见 §3.3b）
ENV HOME=/home/dsh \
    DSH_HOME=/data/dsh \
    NODE_ENV=production \
    NARB_DISABLE_NATIVE_CACHE=1
WORKDIR /workspace
EXPOSE 3111
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["dsh","web","--no-open","--host","127.0.0.1","--port","3111"]
```

`/srv/dsh/config/origin-list-patch.mjs`：

```js
#!/usr/bin/env node
/**
 * 让 /api 的 Origin 栅栏接受**逗号分隔的 Origin 列表**（逐项比较，仍禁止跨源）。
 *
 * 为什么：DSHM 的鸿蒙客户端在 WS 升级时，Origin 是两个逗号分隔的值
 * （平台推导的丢端口形态 + 客户端注入的同源形态），上游按整串解析 ⇒ 每次都 403。
 * 本脚本与 tools/pack-core.mjs 的 allowOriginList() 逐字对齐。
 *
 * 用法：node origin-list-patch.mjs <path/to/@deepseek-ai/dsh-client-connection/lib/index.js>
 * 退出码：0 = 已应用或已存在；1 = 锚点不存在（上游实现已变，拒绝静默跳过）
 */
import { readFileSync, writeFileSync } from 'node:fs';

const target = process.argv[2];
if (target === undefined) {
  console.error('usage: origin-list-patch.mjs <index.js>');
  process.exit(1);
}
const MARKER = 'DSHM_ORIGIN_LIST';
let text = readFileSync(target, 'utf8');
if (text.includes(MARKER)) {
  console.log('[origin-list-patch] 已存在（跳过）');
  process.exit(0);
}
const before = [
  '\tconst origin = header$1(request.headers, "origin");',
  '\tif (origin === void 0) return true;',
  '\ttry {',
  '\t\treturn new URL(origin).host === hostUrl.host;',
  '\t} catch {',
  '\t\treturn false;',
  '\t}',
].join('\n');
const after = [
  '\tconst origin = header$1(request.headers, "origin");',
  '\tif (origin === void 0) return true;',
  '\t/* DSHM_ORIGIN_LIST: 多值 Origin（鸿蒙客户端 libwebsockets 附加的无端口 Origin +',
  '\t * 调用方注入值）只要**任一项**同源即通过。原实现按整串解析，导致每一次端侧 WS 升级',
  '\t * 都被判 403。详见 tools/pack-core.mjs 的 allowOriginList()。 */',
  '\tfor (const rawOrigin of String(origin).split(",")) {',
  '\t\tconst candidate = rawOrigin.trim();',
  '\t\tif (candidate.length === 0) continue;',
  '\t\ttry {',
  '\t\t\tif (new URL(candidate).host === hostUrl.host) return true;',
  '\t\t} catch {',
  '\t\t\t/* 单个非法候选不足以否决整条请求，继续看下一项 */',
  '\t\t}',
  '\t}',
  '\treturn false;',
].join('\n');
if (!text.includes(before)) {
  console.error('[origin-list-patch] 锚点不存在：上游实现已变化，拒绝静默跳过');
  process.exit(1);
}
writeFileSync(target, text.replace(before, after), 'utf8');
console.log('[origin-list-patch] 已允许逗号分隔的 Origin 列表');
```

构建：

```bash
cd /srv/dsh/config
docker build -t dsh-host:0.2.1-alpha.1 .
# 期望：最后一行 Successfully tagged dsh-host:0.2.1-alpha.1
```

**停下点 D2**：构建期若打印 `锚点不存在：上游实现已变化` ⇒ **停下报告**（说明上游改了这段实现），
不要手工改锚点硬上。

#### 3.3b 只读根下的 native 加载器：`NARB_DISABLE_NATIVE_CACHE=1`（必设）

**症状**（2026-10-08 实测，回执 §3.2）：容器一起来就死，`dsh web:` 那行永远不出现，日志里是下面三句之一：

```
ERROR Error: Cannot find module '/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/
node-addon-require-builtin/build/napi/napi-v9-linux-x64-gnu/require_builtin.node'
No usable prebuilt binary found in linux-x64-gnu
No usable native binding found for node-addon-require-builtin-linux-x64-gnu (auto)
```

**为什么**：`node-addon-require-builtin` 的加载是**三级回退链**（读自上游
`node-addon-native-custom-loader/lib/index.js` 的 `loadEntry()`）：

1. 先 `require` **平台子包**（`node-addon-require-builtin-linux-x64-gnu`）——它内部用 `loadPrebuild()`
   取 `prebuilt/linux-x64-gnu-napi-v9.node`；
2. 再退到**就地编译产物** `<包>/build/<backend>/<abi>-<platform>/require_builtin.node`（`tryRequireLocal()`）
   ——slim 镜像里当然没有，于是报出上面那条 `Cannot find module …/build/napi/…`；
3. 两级都不行才抛 `No usable native binding found…`。

而第 1 步取那个预编译 `.node` 时，默认会先经 `materializedNativeBinaryPath()`
**把 `.node` 复制到 native cache 目录、然后 `require` 那个副本**；cache 目录是
`$NARB_NATIVE_CACHE_DIR`，否则 `os.tmpdir()/node-addon-native-custom-loader-<uid>/native-cache`。

**三路实测对照**（回执 §3.2；同一镜像，且都开着 `read_only: true` + 非 root）：

| 方案 | 结果 |
|---|---|
| 默认（走 native cache 物化） | ❌ `No usable prebuilt binary found in linux-x64-gnu` |
| `NARB_NATIVE_CACHE_DIR=/tmp/narb-cache` | ❌ 同样失败 |
| **`NARB_DISABLE_NATIVE_CACHE=1`** | ✅ **加载成功，`dsh web:` 正常打印** |

**采纳的解法**：镜像里设 `NARB_DISABLE_NATIVE_CACHE=1`（见 §3.3 的 Dockerfile `ENV`）。
它是**上游自带的环境变量开关**（`nativeCacheEnabled()` = `process.env.NARB_DISABLE_NATIVE_CACHE !== '1'`），
**不改任何上游文件**，符合 §5 红线 6。语义：跳过"复制到 cache 再加载副本"，
**直接 `require` 预编译原位文件**。（放进镜像 `ENV` 还是 compose 的 `environment` 等效，**只留一处**，别两边写。）

> ⚠️ **机制未定论（照实记）**：上游那份 `materializedNativeBinaryPath()` 对写盘失败是**防御性**的
> ——任何异常都 `catch { return sourcePath }`，即回退到预编译**原位**。所以"只是写不进去"**不足以**
> 解释前两路为什么失败；更像是"**副本 `require` 不成功**"（副本目录的挂载属性、或物化后的中间态）。
> 这不影响结论（三条读数是实测的，且被采纳的解法走的正是"直接加载原位"这条最短路径），
> 但要**彻底钉死**，请把加载失败时的 `error.attempts` 贴回（`loadEntry()` 里逐条记了 `path` / `loadPath` / `message`）：
>
> ```bash
> docker exec dsh-host node -e "
>   try { require('/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/node-addon-require-builtin'); }
>   catch (e) { console.error(e.message); console.error(JSON.stringify(e.attempts, null, 2)); }"
> ```
>
> 另有三个上游开关可用来切片定位（都只是环境变量，拿来排障是安全的）：
> `NARB_BACKEND`（`napi` / `nodeabi` / `auto`）、
> `NARB_DISABLE_OPTIONAL_PACKAGE=1`（跳过平台子包、只试就地产物）、
> `NARB_DISABLE_LOCAL_BUILD=1`（反：只试平台子包）。例：设 `NARB_DISABLE_LOCAL_BUILD=1` 后
> 报的还是"平台子包那条"，就说明坏在子包这一环。

#### 3.3c 容器里必须有 `bash`（最容易漏的工具链缺口）

`slim` 系的 node 镜像里**只有 `dash`（`/bin/sh`），没有 `bash`**。而上游：

- `@deepseek-ai/dsh-bash-local` 的 `execute()` 跑的是 **`bash -c <cmd>`**（argv 里 `bash` 是**硬编码字面量**，
  **没有**"退回 `sh`"的分支）；`@deepseek-ai/dsh-bash-sandbox` 同理；
- `@deepseek-ai/dsh-terminal-bash` 的 `DEFAULT_BASH_SHELL = "/bin/bash"`（终端默认 shell）。

⇒ 不装 `bash`，手机端**能连上、能开会话，但一调 `bash` 工具 / 一开终端就 `ENOENT`**。
所以本单的 Dockerfile 把 `bash` 列进 `apt` 必需项（顺带装 `git`：工作区里干活要用），
并用 §4 的 **V15** 守住它。

> **不要**去查 `node-pty` 的 `spawn-helper`（这是排查时最容易走错的岔路）：`node-pty` 的 `binding.gyp` 里
> `spawn-helper` 那个 target 挂在 `['OS=="mac"', …]` 下面，`prebuilds/linux-*` 目录里**本来就没有它、Linux 也不需要它**
> （`@deepseek-ai/dsh-subprocess-local` 的 `scripts/ensure-spawn-helper.mjs` 只是给 macOS 那份补 `+x` 位，
> 在 Linux 上 `existsSync` 为假 ⇒ 空转；它的 package.json 里那句 `postinstall` 同理）。
> 同理 **`ps` 也不需要**（`procps` 不必装）：Linux 侧的进程勘查读 `/proc`，
> `/bin/ps` 只出现在 **mac** 的 `MacProcessInspector` 里。

### 3.4 compose

`/srv/dsh/config/compose.yaml`：

```yaml
services:
  dsh:
    image: dsh-host:0.2.1-alpha.1
    container_name: dsh-host
    # 用 host 网络：① dsh 的监听落在**宿主 loopback** 上，tailscaled 才能回落到它；
    # ② 不开任何端口映射 ⇒ LAN 侧零暴露面。（ports: 在 host 模式下无意义，故意不写）
    network_mode: host
    restart: unless-stopped
    read_only: true
    tmpfs:
      - /tmp:size=256m,mode=1777
    volumes:
      - /srv/dsh/home:/data/dsh
      - /srv/dsh/workspace:/workspace
      - /srv/dsh/config:/opt/dshm:ro   # 验收探针（V10 的 verify-pty.mjs 要在容器里跑）
    # dsh 的 /api 栅栏只认 loopback 或 --trusted-host 声明过的 authority；
    # <INGRESS_HOST> = 入口主机名（tailnet MagicDNS 名，或 Cloudflare Tunnel 的 hostname），取值见 §3.6；
    # **同一串**要同时填在下面两处，并与 §4 的 NAME 一致。
    command:
      - dsh
      - web
      - --no-open
      - --host
      - 127.0.0.1
      - --port
      - "3111"
      - --public-url
      - https://<INGRESS_HOST>/
      - --trusted-host
      - <INGRESS_HOST>
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    healthcheck:
      # 目的只是"服务在应答"：栅栏会回 403 / 无 cookie 回 401，都算活着 ⇒ 不用 -f
      test: ["CMD-SHELL", "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3111/ | grep -qE '^[1-5][0-9][0-9]$'"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"
```

> **`--trusted-host` 的一个坑**：它是**可变长**参数（`<authority...>`），会一直吃到下一个 `-` 开头的词为止。
> 所以在命令行里它必须**放在最后**，或者后面紧跟的必须是另一个选项。
> 上面的 compose 用数组形式、且把它放最后，不会踩到。

### 3.5 启动与首启读数

```bash
cd /srv/dsh/config
docker compose up -d
docker compose ps                      # 期望 STATE = running (healthy)

# 拿 token：启动横幅（每个进程打印一次 ⇒ 取**最后**一条）
docker logs --tail 200 dsh-host 2>&1 | grep '^dsh web: ' | tail -1
# 期望形态（因为设了 --public-url，所以打印的就是入口 URL）：
#   dsh web: https://<INGRESS_HOST>/?token=<TOKEN>
```

**把这行整体保存下来**：
- `?token=…` 就是手机「ConnectPane ① 粘贴启动 URL」要粘的整串；
- token **每个进程只生成一次**，`docker restart` 后会换新的（旧 URL 立即失效，见 §6.3）。

**停下点 D3**：`docker logs` 里没有 `dsh web:` 行 ⇒ 看 §9 排查表（最常见是 `node-addon-require-builtin` 缺预编译包，或 `$DSH_HOME` 不可写）。

### 3.6 网络入口 ingress

> **实际走哪条由 §0.4 的 C2/C3 决定**。2026-10-08 实测（回执 §1）：**C2 不成立**（fnOS 上没装 Tailscale），
> 用户拍板 **Cloudflare Tunnel** ⇒ 本轮实走 §3.6.2。§3.6.1 保留为"以后想换回私有网"的备选。
> 两条路对 dsh 侧的要求**完全一样**：**入口主机名进 `--trusted-host`、出口回 `127.0.0.1:3111`**。

#### 3.6.1 首选：Tailscale（tailnet 内，不碰公网）

**为什么首选**：① 传输层由 WireGuard 加密 + 设备身份由 tailnet 管；② 手机端已经装了 Tailscale
（实测机型上在装应用：`io.github.tailscaleohos`）；③ **不需要把任何东西暴露到公网**；
④ ACL 天然就是"设备级"的，平板以后加一条即可。

```bash
# ① NAS 加入 tailnet（用你自己的账号；登录串在浏览器里完成）
tailscale up --hostname=nas-dsh --accept-routes=false

# ② 拿到 MagicDNS 名（形如 nas-dsh.tailnet-name.ts.net）：
tailscale status --json | grep -o '"DNSName": *"[^"]*"' | head -1

# ③ 在 tailnet 管理台把 HTTPS 证书打开（Settings → HTTPS Certificates），
#    然后在 NAS 上把入口指向 loopback（这一步就是"隧道出口落在 127.0.0.1"）：
sudo tailscale serve --bg --https=443 http://127.0.0.1:3111

# ④ 复核
tailscale serve status
# 期望：https://nas-dsh.tailnet-name.ts.net/  →  proxy http://127.0.0.1:3111
```

把 ③ 里出现的**主机名**填进 §3.4 的 `--public-url` 与 `--trusted-host`，然后
`docker compose up -d --force-recreate`，再重跑 §3.5。

**为什么这样栅栏能过**：请求到达 dsh 时 `Host: nas-dsh.tailnet-name.ts.net`。
`--trusted-host` 里就是这个名字（**无端口项匹配任意端口**，§2 第 8 条）⇒ 栅栏放行，
**没有任何头被改写**。

**停下点 D4**：`tailscale serve status` 里看不到映射，或手机上打不开 `https://<name>/`
⇒ 停下报告（别改 dsh 的绑定点去"绕过"）。

#### 3.6.2 备选（**2026-10-08 实走**）：Cloudflare Tunnel + Access

只在"手机不在 tailnet 里"或"要给外部设备用"时才走这条。**必须**同时配 Cloudflare Access，
否则等于把 dsh 的 `/api` 挂到公网（上游只在 Host 匹配处做了防护，这不是面向公网的认证设计）。

**关键事实（2026-10-08 实测，回执 §6.1）**：NAS 上**已经**有一条 CF Tunnel 在跑，其中一条
`→ http://localhost:19119` 的 ingress **已经在跑通** ⇒ "**隧道出口回落宿主 loopback**"这个模式在本机
是**已被证明可行**的，正是本单要的形态。
（同一条 tunnel 里原本还有一条 `<入口名> → http://192.168.2.88:3080`；按用户 2026-10-08 的决定，
**它已被删掉、原地重建为本单的 `→ http://127.0.0.1:3111`** ⇒ 入口名沿用那一个，§12 开头已记。）

```bash
# ① 在 Cloudflare 控制台（Zero Trust → Networks → Tunnels → 选中该 tunnel → Public Hostnames）加一条：
#      Subdomain : dshhost             （自定）
#      Domain    : <你的域名>
#      Type      : HTTP
#      URL       : http://127.0.0.1:3111     ← 隧道出口落回 loopback（本单的硬要求）
#      originRequest.noTLSVerify : true      ← 回源按 HTTP 走，勾上最稳
#    DNS 记录会自动建；改完 NAS 上的 cloudflared 会自己拉新配置（日志出现 Updated to new configuration）

# ② 拿到主机名后，把它填进 §3.4 的两个占位（<INGRESS_HOST> 换成同一个值）：
sudo sed -i 's|<INGRESS_HOST>|<入口主机名>|g' /srv/dsh/config/compose.yaml
docker compose -f /srv/dsh/config/compose.yaml up -d --force-recreate
#   ⚠️ 重建会换 token（§6.3），必须重取：
docker logs --tail 200 dsh-host 2>&1 | grep '^dsh web: ' | tail -1
```

**为什么这样栅栏能过**：入口在 NAS 上终结 TLS、回源到 loopback，到达 dsh 的 `Host` 只可能是两种之一
——**入口主机名**（cloudflared 透传原始 `Host` 时，这是常见形态）或**回源地址** `127.0.0.1:3111`
（cloudflared 改写成回源 host 时）。**两种都在放行集合里**：前者靠 `--trusted-host` 声明，
后者本来就是 loopback（§2 第 6 条）。**不需要改写任何头**，也不需要猜 cloudflared 的行为
——真实取值由 **V9 / V18** 的实测读数说了算。

**停下点 D5**：Access policy 没建好之前，**不要**保留隧道运行。

⚠️ **Access 策略**：本单定位是"只给自己用"，policy 要**只放行你自己的身份**（Service Token 或 SSO）。
若不建 Access，就必须清楚：**任何拿到那串 `?token=` URL 的人都能进** —— 这是**要签字认下的风险**，
不是"默认安全"。

#### 3.6.3 明确不采用的做法（写在这里是为了防止"顺手用了"）

| 做法 | 为什么不采用 |
|---|---|
| `dsh --host 0.0.0.0` | 上游 CLI **直接拒绝**（§2 第 3 条）；且等于把 RCE 暴露到网络 |
| 手机直连 `http://192.168.2.88:3111` | ① 现在是 loopback 绑定，LAN 根本不可达；② 即使绑定放开，`Host: 192.168.2.88:3111` 不在 `trustedHosts` 里 ⇒ **403**；③ 明文 + token 走 LAN |
| 在入口上改写 / 删掉 `Host` 头 | 明确禁止（会破坏栅栏的语义，等同于"绕过安全围栏"，见 `docs/00` §3） |
| 关掉 `node-addon-*` / 打更多补丁"让它能跑" | 只在 §3.3 那一处注入是允许的；其它一律不做，报上来讨论 |

### 3.7 设备与 ACL（手机先，平板预留）

1. **手机**：把手机加入 tailnet（同一账号登录即可），ACL 允许 `phone → nas-dsh:443`。
2. **平板（预留）**：不需要任何 NAS 侧改动——入口是**按主机名**授权的（不是按设备），
   平板只需要 ① 加入 tailnet，② ACL 加一条，③ 在 App 里粘贴**同一行**启动 URL。
   ⚠️ 但要注意：**上游没有"按设备"的凭据**（一个进程一个 token + 浏览器会话 cookie）。
   设备级控制只能靠 tailnet ACL；要"吊销某台设备"，见 §6.4。

---

## 4. 验收（可机器判定；把每条的实际读数贴回）

**准备**（在 NAS 上，`TOKEN` 取 §3.5 的那串，`NAME` 取 §3.6 的**入口主机名**）：

```bash
TOKEN='<从 dsh web: 行里取的 token>'
NAME='<INGRESS_HOST>'
BASE="http://127.0.0.1:3111"          # 从 NAS 本机看，走 loopback

# ⚠️ cookie 与「换 cookie 时用的 Host」**绑定**（§14.3）：payload.authority 必须等于本次请求的 Host。
#    ⇒ 探针用哪个 Host，就用哪个 Host 换 cookie。两份都要（各回 303 + Set-Cookie）：
COOKIE_L=$(curl -s -D - -o /dev/null "$BASE/?token=$TOKEN" | tr -d '\r' | awk '/^set-cookie:/I {print $2; exit}')
COOKIE_N=$(curl -s -D - -o /dev/null -H "Host: $NAME" "$BASE/?token=$TOKEN" | tr -d '\r' | awk '/^set-cookie:/I {print $2; exit}')
echo "loopback cookie len=${#COOKIE_L} / ingress cookie len=${#COOKIE_N}"
```

| 编号 | 命令 | 期望读数 | 判据 |
|---|---|---|---|
| **V1** | `ss -lntp \| grep 3111` | 只出现 `127.0.0.1:3111` | **不得**出现 `0.0.0.0:3111` 或 `*:3111` |
| **V2** | `docker logs --tail 200 dsh-host 2>&1 \| grep '^dsh web: ' \| tail -1` | `dsh web: https://<NAME>/?token=…` | 取**最后**一条（容器不重建时日志会累积，见 §6.6） |
| **V3** | `node verify-ws.mjs - "127.0.0.1:3111" "http://127.0.0.1:3111"`（cookie 用 `-` 表示不带） | `401` | 无 cookie 必须 401（不是 101、不是 403） |
| **V4** | `node verify-ws.mjs "$COOKIE_L" "127.0.0.1:3111" "http://127.0.0.1:3111"` | `101` | loopback + cookie + 同源 Origin = 正常路径 |
| **V5** | `node verify-ws.mjs "$COOKIE_N" "$NAME" "https://$NAME, wss://$NAME"`（**两个值**，其一同源） | **注入前 `403`**；**注入后 `101`** | 这条是"注入确实必要"的**证据**。若注入前就 101 ⇒ 停下报告（上游已放宽，注入不该照抄） |
| **V6** | 同 V5（注入后） | `101` | 多值里**任一项**同源即通过 |
| **V7** | `node verify-ws.mjs "$COOKIE_N" "$NAME" "https://evil.example"` | `403` | **不得**因为注入而放宽跨源（反控制组） |
| **V8** | `node verify-ws.mjs "$COOKIE_N" "192.168.2.88:3111" "http://192.168.2.88:3111"` | `403` | 未经声明的 authority 必须被拒 |
| **V9** | `node verify-ws.mjs "$COOKIE_N" "$NAME" "https://$NAME"` | `101` | **模拟入口形态**：Host 换成 ingress 名 + 同源 Origin ⇒ 放行（证明 `--trusted-host` 生效） |
| **V10** | 真 pty 冒烟：`docker exec dsh-host node /opt/dshm/verify-pty.mjs`（脚本见下） | `PTY_OK` | 手机端要"真 bash"就得先证明**容器里**的 `node-pty` 真能起 shell（HTTP 能过 ≠ WS 能过 ≠ pty 能起） |
| **V11** | `docker inspect dsh-host --format '{{.Config.User}} {{.HostConfig.NetworkMode}} {{.HostConfig.ReadonlyRootfs}}'` | `10001:10001 host true` | 非 root / host 网络 / 只读根 |
| **V12** | `docker inspect dsh-host --format '{{json .Mounts}}' \| grep -c docker.sock` | `0` | 绝不挂 `docker.sock` |
| **V13** | `docker compose up -d --force-recreate && ls /srv/dsh/home` | 数据仍在（`profiles/`、`storages/` 等） | 容器重建**不动**用户数据 |
| **V14** | `docker exec dsh-host sh -c 'touch /tmp/probe && echo TMP_OK'` | `TMP_OK` | `/tmp` 必须可写：只读根下 native 加载器的"物化写盘"、以及 bash 工具 / 附件 / spill 的临时文件都依赖它（见 §3.3b） |
| **V15** | `docker exec dsh-host bash -lc 'echo BASH_OK; command -v git'` | `BASH_OK` + git 的路径 | 镜像里必须有 `bash`（§3.3c）；`git` 供工作区用。**两者缺一，手机端"连上了也用不了"** |
| **V16** | `docker exec dsh-host sh -c 'ls /usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/node-addon-require-builtin-*/prebuilt/'` | 列得出 `linux-x64-gnu-napi-v9.node` | 平台子包装上了（缺它就会走到 §3.3b 回退链里"就地产物"那条死路） |

**外部侧（经入口，V17/V18）——"手机能不能用"的必要条件**：

| 编号 | 命令 | 期望读数 | 判据 |
|---|---|---|---|
| **V17** | 从**外部网络**（手机流量 / 别的机器）`curl -sI https://<INGRESS_HOST>/` | **`401`**（正文 `dsh web authentication required; reopen the URL printed by dsh web.`） | 不带 token/cookie 的 `/` **本来就该 401**（§13 实测）⇒ 回 401 说明"打到 dsh 了"；回 CF 的 `5xx`/`1033`/错误页 = 隧道或回源没通；Access 若已开则是 Access 的拦截面 |
| **V18** | 在外部网络跑 `node verify-ws.mjs "$COOKIE_N" "<INGRESS_HOST>" "https://<INGRESS_HOST>"`（`$COOKIE_N` = §4「准备」里**用 `-H "Host: <INGRESS_HOST>"` 换的那份**，§14.3） | `101` | **这才是"手机端能用"的必要条件**：入口经真实隧道 ⇒ dsh 侧栅栏放行 ⇒ WS 升级成功。本单**未做**（回执 §8 边界声明正确） |

> **为什么栅栏探针一律用 WS 升级（这条是 Hermes 实战发现的，回执 §4.3）**：栅栏**不是**全局中间件，
> 它在 `/api` 的处理器**内部**、路由命中之后才调 `admit()`（出处：`dsh-client-connection/lib/index.js`
> 的 `createSharedFetchHandler()` 与 `dsh-api-gateway/lib/index.js` 里 `remote.mux` 的 upgrade 注册）。
> ⇒ ① 不存在的 `/api/...` 路径会 **404**（根本没走到栅栏），拿它做探针会得到"假通过/假失败"；
> ② 静态根 `/` **不受栅栏保护**（在 `/` 上带跨源 `Origin` 回 200 是**正常服务静态资源**，不是故障）；
> ③ `/api` 的调用面是 RPC（`ctx.inject(["connection"])` 注册的拦截），不是 REST 路由。
> 所以本单的 V3–V9 统一用 `/api/remote.mux` 的 **WebSocket 升级**做探针——它同时覆盖"HTTP 能过 ≠ WS 能过"。

**V3–V9 的 WS 升级脚本**（`/srv/dsh/config/verify-ws.mjs`，只用 Node 内置模块；`cookie` 传 `-` 表示不带 cookie）：

```js
// 用法：node verify-ws.mjs <cookie|-> <hostHeader> <originHeader>    （cookie 传 - 表示不带）
// 判据：打印 101 = 通过；403 = 栅栏拒；401 = 认证拒；其它 = 报告
import http from 'node:http';
import { randomBytes } from 'node:crypto';

const [cookie, hostHeader, originHeader] = process.argv.slice(2);
const req = http.request({
  host: '127.0.0.1',
  port: 3111,
  path: '/api/remote.mux',
  headers: {
    Host: hostHeader,
    Connection: 'Upgrade',
    Upgrade: 'websocket',
    'Sec-WebSocket-Version': '13',
    'Sec-WebSocket-Key': randomBytes(16).toString('base64'),
    ...(cookie === '-' ? {} : { cookie }),
    Origin: originHeader,
  },
});
req.on('upgrade', (res) => {
  console.log(res.statusCode);
  req.destroy();
  process.exit(0);
});
req.on('response', (res) => {
  console.log(res.statusCode);
  res.resume();
  process.exit(0);
});
req.on('error', (error) => {
  console.error('transport error', error.message);
  process.exit(2);
});
req.end();
```

**V10 的脚本**（`/srv/dsh/config/verify-pty.mjs`，**在容器里**跑：`docker exec dsh-host node /opt/dshm/verify-pty.mjs`；
所以 §3.4 的 compose 要把 `/srv/dsh/config` 只读挂进 `/opt/dshm`，见 §3.2 的表）：

```js
// 用法：docker exec dsh-host node /opt/dshm/verify-pty.mjs [全局根]   （默认自己跑 `npm root -g`）
// 判据：打印 PTY_OK = 通过；PTY_FAIL = 报告
// 说明：这条测的是**真 pty** —— 即上游 `dsh-terminal-bash` 用的那个内核（node-pty）。
//       HTTP 能过 ≠ WS 能过 ≠ pty 能起，三者要分开验。
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

const globalRoot = process.argv[2] ?? execFileSync('npm', ['root', '-g'], { encoding: 'utf8' }).trim();
// 从 `@deepseek-ai/dsh` 的包目录起解析 ⇒ 单包形态下嵌在它 node_modules 里的依赖也能解到
const require = createRequire(path.join(globalRoot, '@deepseek-ai', 'dsh', 'package.json'));

let pty;
try {
  pty = require('node-pty');
} catch (error) {
  console.error('PTY_FAIL 无法加载 node-pty：', error.message);
  process.exit(1);
}

const term = pty.spawn('/bin/bash', ['-lc', 'echo PTY_OK; echo TERM=$TERM; id -u'], {
  name: 'xterm-256color',
  cols: 80,
  rows: 24,
  env: { ...process.env, TERM: 'xterm-256color' },
});

let output = '';
function finish(reason) {
  if (output.includes('PTY_OK')) {
    console.log('PTY_OK');
    console.log(output.trim());
    process.exit(0);
  }
  console.error('PTY_FAIL', reason, JSON.stringify(output));
  process.exit(1);
}
term.onData((chunk) => {
  output += chunk;
  if (output.includes('PTY_OK')) finish('ok');
});
term.onExit(({ exitCode }) => finish(`exit=${exitCode}`));
setTimeout(() => finish('timeout'), 8000);
```

> **探针跑在哪**：`verify-ws.mjs` 在 **NAS 宿主**上跑（回执里 V3–V9 就是这么跑通的，宿主有 `node`）；
> `verify-pty.mjs` 必须**在容器里**跑（要的就是容器里那份 `node-pty`）。
>
> ⚠️ `$COOKIE_N` = §4「准备」里**用 `-H "Host: $NAME"` 换的那份**（cookie 与 authority 绑定，§14.3）——
> 用 `127.0.0.1` 换来的 cookie 打 `$NAME` 会得到**假阴性 401**。

```bash
node /srv/dsh/config/verify-ws.mjs "$COOKIE_N" "$NAME" "https://$NAME"                             # 期望 101
node /srv/dsh/config/verify-ws.mjs "$COOKIE_N" "$NAME" "https://$NAME, https://$NAME"              # 期望 101（注入后）
node /srv/dsh/config/verify-ws.mjs "$COOKIE_N" "$NAME" "https://evil.example"                      # 期望 403
node /srv/dsh/config/verify-ws.mjs "$COOKIE_N" "192.168.2.88:3111" "http://192.168.2.88:3111"      # 期望 403
```

---

## 5. 安全红线与禁做清单

**红线（硬性）**：

1. dsh **只绑 `127.0.0.1`**；容器用 `network_mode: host` 但**不开任何端口映射**。
2. 容器**非 root**（uid 10001），`cap_drop: ALL`，`no-new-privileges`，根文件系统只读。
3. **绝不**把 `/var/run/docker.sock` 挂进容器（V12 守这条）。
4. **绝不**在没有 Access policy 的情况下把入口暴露到公网。
5. **绝不**改写 / 删除 `Host` 或 `Origin` 头，**绝不**用 `0.0.0.0` 绑定去"绕过"栅栏。
6. 对上游的改动**只有 §3.3 那一处**，且必须带幂等标记与"锚点不存在即失败"的守卫。
7. `/srv/dsh/home` 是用户数据：不 `down -v`、不 `rm -rf`。
8. 只挂两个卷（`home` + `workspace`）。**不要**为了"方便"再挂宿主家目录、`/etc`、`/var`。

**禁做清单（写出来是因为它们都很"顺手"）**：

- ❌ 把本仓的 `dsh-core-*.zip` / 端侧插件 / `hostkit` 拷进这个容器（平台不对，见 §3.3 陷阱一）。
- ❌ 把 dsh 的端口通过 `ports:` 映射到 LAN，或加 `0.0.0.0` 绑定。
- ❌ 在镜像里"顺手"关掉 `node-addon-*` 或加别的补丁。
- ❌ 把 token 写进 compose 文件、塞进 git、或贴到聊天里。
- ❌ 用 `docker exec` 进容器改文件（改动必须回到 Dockerfile，容器可随时重建）。

---

## 6. 运维

### 6.1 升级

```bash
# ① 备份（见 6.2）② 改 Dockerfile 里的 DSH_VERSION（或 --trusted-host 等参数）
docker compose build && docker compose up -d --force-recreate
docker logs --tail 200 dsh-host 2>&1 | grep '^dsh web: ' | tail -1     # 拿新 token
```

### 6.2 备份 / 还原

```bash
# 备份（含凭据与会话，落盘前先停容器保证一致）
docker compose stop
sudo tar -C /srv/dsh -czf /srv/dsh/backup-$(date +%F-%H%M).tar.gz home workspace config
docker compose start
# 还原：停容器 → 解包到 /srv/dsh → start
```

### 6.3 token 轮换

token 是**每进程一次**的：`docker restart dsh-host` 即换新，旧 URL 立刻失效（手机上要重新粘新 URL）。

### 6.4 设备吊销

- **tailnet 层（推荐）**：在 ACL 里删掉那台设备的条目 / 把节点从 tailnet 移除；
- **应用层**：没有"按设备"的凭据（§3.7），所以"吊销单台设备"只能靠上面那条 + §6.3 轮换 token。
  （需要真正的"配对 + 按设备吊销"时，那属于本仓 `hostkit/` 的 Phase 2，见 §7.2。）

### 6.5 若 fnOS 上 Docker 不可用（C1 不成立时）

退化为"裸进程 + systemd"：同一套参数、同一个非 root 用户、同样只绑 `127.0.0.1`，
用 systemd 的 `Restart=always` 代替 compose 的 `restart:`。
**其它一切不变**（尤其是 §5 的红线）。此时 §4 的 V11/V12 换成"跑 `dsh` 的用户不是 root、没有被额外授权"。

### 6.6 日志与可观测

- 启动横幅**每个进程**打印一次 ⇒ `docker logs` 是唯一权威来源，别去别处找 token；
  但容器**不重建**时（`restart` / `up -d`）日志会累积 ⇒ **必须取最后一条**：
  `docker logs --tail 200 dsh-host 2>&1 | grep '^dsh web: ' | tail -1`（`grep -m1` 会拿到**上一个进程**的 token）。
- 审计/会话日志在 `/srv/dsh/home` 里（随备份走）。
- 容器日志已按 §3.4 的 `logging` 限制在 5×10 MB。

---

## 7. 手机端接入（现状与缺口）—— **本单不做**

### 7.1 手机侧**零代码改动**即可接入（这正是选这条路的原因）

`entry/src/main/ets/view/ConnectPane.ets` 的「远程 Host（可选）」已经支持：

- **① 粘贴启动 URL（含 `?token=`）**——最快路径，同时完成地址配置与授权（§3.5 那行直接粘）；
- **② 手输 `host:port` + token**——适用于分开填写；
- 地址解析 `connection/src/main/ets/protocol/HostAddress.ets` 已支持 `192.168.1.5:3000`、`https://host`、`[::1]:8080`
  等形态，`https → wss` 自动推导 ⇒ **入口用 HTTPS 时无需任何改动**。

### 7.2 仍未接线 / 不存在的部分（本单**不**包含，属于本仓的活）

| 项 | 现状 | 与本单的关系 |
|---|---|---|
| `ConnectPane` 的**局域网自动发现** | **未接线**（`MainShell.ets` 里 `discoveryAvailable: false`，按钮置灰） | tailnet 路线**不需要**发现 |
| `hostkit` 的**隧道客户端**（X25519 + HKDF + AES-256-GCM 密封帧 + `dshkit://` 配对） | ArkTS 侧**没有实现**（全树无 `cryptoFramework`/`X25519`/AES-GCM，无 `dshkit` 解析） | 那是 Phase 2（配对 + 按设备吊销）；**不是**本单的前置 |
| 手机端**端到端**验收（真机连上 NAS、跑 `bash`） | **未做** | 需要用户在手机上操作，见 §0.3 |

> **为什么 Phase 1 不需要 hostkit**：tailnet 已经把"谁能到达这个入口"管住了（设备身份 + ACL），
> 而 dsh 的栅栏要的是"请求在 Host 看来仍来自被声明的 authority"——入口在 NAS 上终结、出口回 loopback，
> 正好满足。hostkit 的增量价值只剩"配对 UX + 按设备吊销"，属于可选加购项。

---

## 8. 未验证 / 待定（照实记）

- **已跑过 §3.1–§3.5**（2026-10-08 真实飞牛 NAS，回执见 §11）：C1 成立（Docker `28.5.2` / compose `v5.1.3` / `x86_64`）、
  **C2 不成立**（fnOS 未装 Tailscale）⇒ 入口实走 **Cloudflare Tunnel**（§3.6.2）；镜像 13/13 步、loopback 侧自验收 10/10。
  上游事实仍全部读自本仓钉的 `@deepseek-ai/dsh@0.2.1-alpha.1` 代码。
- **未验证手机端到端**（§0.3、§7.2）：需要真机。`V17/V18` 是它的**必要条件**，但必要条件 ≠ 端到端。
- **未验证真 pty**（V10 + V15/V16，本轮**新增**的探针）：理由是"**`dsh web` 起来 ≠ `bash` 能用**" ——
  HTTP 能过 ≠ WS 能过 ≠ pty 能起 ≠ 手机能用，四层要各自有读数。已知的一处工具链缺口（镜像没装 `bash`）已在 §3.3c 修掉。
- **`NARB_DISABLE_NATIVE_CACHE=1` 的触发点未定论**：三路对照是**实测**的（§3.3b），但"前两路为什么会失败"
  目前只有"写不进只读根"这一层解释，而按上游代码它是**防御性回退**（失败即用原位）⇒ 该解释**不成立**；
  要定论得取 `error.attempts`（§3.3b 给了命令）。**采纳的结论不受此影响**。
- **未定论 Phase 2 是否值得做**：tailnet ACL / Access policy 已经覆盖设备级控制，用户若要"配对码 + 单设备吊销"再说。
- **`--public-url` 与 `--trusted-host` 的具体取值**依赖 §3.6 实际拿到的入口主机名，本单用 `<INGRESS_HOST>` 占位。

---

## 9. 故障排查表

| 症状 | 最可能的原因 | 处理 |
|---|---|---|
| 容器起来就退出，日志 `host preparation failed: No usable native binding found for node-addon-require-builtin-linux-x64-gnu` | 全局安装时没装到 linux-x64 的预编译包 | 在容器里 `npm ls -g node-addon-require-builtin-linux-x64-gnu`；确认 `apt` 装过 `ca-certificates`、npm 能访问 registry |
| `docker logs` 里没有 `dsh web:` 行 | `--public-url` 格式不合法 / `$DSH_HOME` 不可写 / 端口被占 | 查 §3.1 的端口检查、§3.2 的 `chown 10001`；先去掉 `--public-url` 复跑 |
| 手机能打开 `https://<name>/`，但 App 里连不上 | 粘贴的不是带 `?token=` 的整串；或 token 已因重启失效 | 重新取 §3.5 那一行；注意 token 每进程一次 |
| HTTP 能过、会话/工具一律不动（"升级响应不是 101"） | **Origin 多值被栅栏拒**（§3.3 陷阱二） | 跑 V5/V9；确认注入生效（`grep -c DSHM_ORIGIN_LIST`，注意**注入文件不在全局根下**，用 §10 的 `find` 解析） |
| 手机直连 `192.168.2.88:3111` 打不开 | 这是**预期行为**（loopback 绑定） | 不要"修"它；走 §3.6 的入口 |
| `tailscale serve status` 空 | 没开 tailnet 的 HTTPS 证书 / 不在 tailnet | 见 §3.6.1 第 ③ 步 |
| 装插件（手机端"插件市场"）报错 | 镜像里没有 `pnpm` | §3.3 的 Dockerfile 已含 `pnpm@9`；确认没被删 |
| `Cannot find module '…/build/napi/napi-v9-linux-x64-gnu/require_builtin.node'` 或 `No usable prebuilt binary found in linux-x64-gnu` | ① **平台子包**没装上（`npm ls -g node-addon-require-builtin-linux-x64-gnu`）；② 或 native cache 物化那条路走不通（§3.3b） | 先确认子包在（V16）；再设 `NARB_DISABLE_NATIVE_CACHE=1` 复跑。要定论就把 `error.attempts` 贴回（§3.3b 有命令） |
| `bash` 工具 / 终端报 `ENOENT`（或 `bash: not found`） | 镜像里没装 `bash`（slim 只有 dash）——§3.3c | 按 §3.3 的 Dockerfile 装上 `bash`（顺带 `git`）后重建；V15 守这条 |
| 构建期打印 `锚点不存在：上游实现已变化` | ① 注入目标**解析错了**（0.2.1-alpha.1 是单包形态，注入文件不在全局根下）；② 或上游真改了那段实现 | 先看构建日志有没有 `[inject] <路径>` 且路径里含 `/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-client-connection/`；确实解出来了还报锚点 ⇒ **停下报告** |
| 经隧道打开是 `403`（手机端表现为"升级响应不是 101"） | `--trusted-host` 里没有入口主机名 / 填了没重建容器 | 填 §3.4 的两个占位 ⇒ `up -d --force-recreate` ⇒ **重取 token**（§6.3）⇒ 重跑 V9/V18 |
| `verify-pty.mjs` 报 `PTY_FAIL 无法加载 node-pty` | 从宿主跑了它（宿主的全局树里没有 `@deepseek-ai/dsh`） | 用 `docker exec dsh-host node /opt/dshm/verify-pty.mjs`（§4） |

---

## 10. 复现命令汇总（贴回报告时用这一节）

```bash
# 事实确认
uname -m; docker version --format '{{.Server.Version}}'; docker compose version
# 构建与启动
cd /srv/dsh/config && docker build -t dsh-host:0.2.1-alpha.1 . && docker compose up -d
# 关键读数
docker compose ps
docker logs --tail 200 dsh-host 2>&1 | grep '^dsh web: ' | tail -1
ss -lntp | grep 3111
docker inspect dsh-host --format '{{.Config.User}} {{.HostConfig.NetworkMode}} {{.HostConfig.ReadonlyRootfs}}'
# 注入目标（注意：0.2.1-alpha.1 是**单包形态**，它不在全局根下 ⇒ 用 find 解析）
CONN="$(find "$(npm root -g)/@deepseek-ai" -path '*/dsh-client-connection/lib/index.js' -print -quit)"
echo "conn=$CONN"; grep -c DSHM_ORIGIN_LIST "$CONN"
# 工具链（§3.3c）+ 真 pty（§4 V10 脚本）
docker exec dsh-host bash -lc 'echo BASH_OK; command -v git'
docker exec dsh-host node /opt/dshm/verify-pty.mjs
```

---

## 11. 实收回执（2026-10-08，飞牛 NAS / Hermes）与判读

> 回执全文在**开发端**（`D:/temp/.../回执-117-构建与验收.md`），本节只记判读结论与**本单据此改了什么**。
> 回执自己的边界声明是对的：**"验收通过" ≠ "手机能用"**（§0.3）。

**总判**：§0.4 三项确认 **2/3 成立**（C2 不成立 ⇒ 走 §3.6.2）；§3.1–§3.5 完成；**loopback 侧自验收 10/10 通过**；
**手机端到端未做**（属 §7，本单不含）。

| 项 | 实测 | 判读 |
|---|---|---|
| C1 Docker / compose | `28.5.2` / `v5.1.3` / `x86_64`（3111 施工前空闲） | ✅ 成立 |
| C2 tailscale | **未安装** | ❌ 不成立 ⇒ 入口实走 §3.6.2（Cloudflare Tunnel） |
| C3 入口拍板 | 用户选 **Cloudflare Tunnel** | ✅ 成立 |
| 镜像 | `dsh-host:0.2.1-alpha.1`，13/13 步 | ✅ 含 §3.3 那处唯一注入（`DSHM_ORIGIN_LIST` 计数 = 1） |
| V1 / V2 / V11 / V12 / V13 | 全 ✅ | 只监听 `127.0.0.1:3111`、横幅 1 行、`10001:10001 host true`、0 处 `docker.sock`、重建不动数据 |
| V3–V9 栅栏 | `401` / `200` / `403` / `403` / `101` | ✅（探针载体见下条"本单缺陷 2"） |
| **反控制组（决定性证据）** | 官方原版 vs 注入后：单值同源 `101`/`101`；**多值（鸿蒙形态）`403` → `101`**；跨源 `evil.example` `403`/`403` | ✅ **"先证伪再施工"成立：注入既必要、又不削弱安全** |
| 开机自启 | `dsh-host.service`（`Type=oneshot` + `RemainAfterExit`，与容器自身的 `restart: unless-stopped` 配合）enabled / active | ✅ 且**未触碰**已有的 `dsh-web.service`（3080） |
| 待办（入口侧） | CF Tunnel 已在跑（已有 `→ http://localhost:19119` 的 ingress 跑通 ⇒ "隧道出口回 loopback"在本机**已被证明可行**） | 按 §3.6.2：控制台加 `→ http://127.0.0.1:3111` ⇒ 填 `--trusted-host` ⇒ **重取 token** ⇒ 跑 V17/V18 |
| **未做** | 真 pty（V10/V15/V16）、手机端到端（V17/V18） | 照实记，见 §8 |

### 11.1 本单自己的两处缺陷（施工方发现，本版已修）

1. **§3.3 的注入路径写错了**。`0.2.1-alpha.1` 是**单包**形态：全局 `node_modules/@deepseek-ai/` 下**只有 `dsh` 一个目录**，
   其余全在 `@deepseek-ai/dsh/node_modules/@deepseek-ai/` 里（开发端已在本机用
   `npm i -g --prefix <临时目录> @deepseek-ai/dsh@0.2.1-alpha.1` 复现）。照原文路径必然 `ENOENT`，
   施工方首次构建就卡在这一步（Step 6）。
   ⇒ 本版改成"**从全局根递归解析** `*/dsh-client-connection/lib/index.js`，**解不到就报错退出**"，并在构建日志打印 `[inject] <路径>`。
2. **§4 的栅栏探针载体选错了**。栅栏**不是**全局中间件，它在 `/api` 处理器**内部**、路由命中之后才调 `admit()`
   （出处：`dsh-client-connection/lib/index.js` 的 `createSharedFetchHandler()`、`dsh-api-gateway/lib/index.js` 里
   `remote.mux` 的 upgrade 注册）⇒ ① 不存在的 `/api/...` 路径会 **404**（根本没走到栅栏）；
   ② 静态根 `/` **不受栅栏保护**（在 `/` 上带跨源 `Origin` 回 `200` 是"正常服务静态资源"，不是故障）。
   ⇒ 本版已把 V3–V9 统一改成 `/api/remote.mux` 的 **WebSocket 升级**探针（`verify-ws.mjs` 扩了"不带 cookie"的 `-` 形式）。

### 11.2 本轮新增/加强的三条（都是"不查就会漂"的）

- **`NARB_DISABLE_NATIVE_CACHE=1` 是上游自带开关**（`node-addon-native-custom-loader` 的 `nativeCacheEnabled()`），
  **不是**我们发明的补丁 ⇒ 与 §5 红线 6（不碰上游文件）不冲突。三路实测对照见 §3.3b。
- **镜像必须装 `bash`**（§3.3c）：slim 里只有 `dash`，而 `tool-bash` 硬编码执行 `bash -c`、终端默认 `/bin/bash`。
  这条是**新的工具链缺口**，回执没覆盖（它只验到 HTTP/WS 层）。
- **验证要分层**：`dsh web` 起来 / HTTP 能过 / **WS 能过** / **pty 能起** / 手机端到端，是**五个不同层次**。
  V10 因此从"WS 冒烟"改成"**真 pty 冒烟**"（`verify-pty.mjs`），并新增 V15/V16（工具链）、V17/V18（经真实入口）。

---

## 12. 复跑清单（入口已就绪后，照抄即可）

> **触发条件**：Cloudflare 侧已经给这条 tunnel 加好了 `→ HTTP → http://127.0.0.1:3111` 的 hostname。
> 下面 `<INGRESS_HOST>` 就填那个 hostname（**与 §3.4 / §3.5 / §4 的 `NAME` 是同一串**）。
> ⚠️ **本仓是公开仓库，所以本单不落盘真实域名**（一个没有 Access 的公网入口名写进公开文档等于递扫描清单）；
> 请只在 NAS 上现填。
>
> ✅ **撞车已排除（2026-10-08 用户确认）**：回执 §6.1 里 `dsh.<域名>` 原本指向 `http://192.168.2.88:3080`
> （已有的 `dsh-web.service`）—— 用户**把 3080 那条 ingress 删掉、原地重建为 `→ http://127.0.0.1:3111`**（即本单这条）。
> **副作用照实记**：经这个主机名访问 **3080 的入口已经不存在**了；若那个服务还要对外，**另给它一个子域名**，
> 不要与本单抢同一个名字（同一条 tunnel 的两个 hostname 指向不同回源时，CF 只认先匹配的那条）。

```bash
# ① 填实入口名（两种占位形态都覆盖：本单新版是 <INGRESS_HOST>，按旧版施工的是 REPLACE_ME.tailnet-name.ts.net）
cd /srv/dsh/config
HOST='<INGRESS_HOST>'                      # ← 改成实际入口主机名
sudo sed -i -e "s|<INGRESS_HOST>|$HOST|g" -e "s|REPLACE_ME.tailnet-name.ts.net|$HOST|g" compose.yaml
grep -n 'public-url' -A1 compose.yaml; grep -n 'trusted-host' -A1 compose.yaml    # 复核两处都已是 $HOST
grep -n '/opt/dshm' compose.yaml           # 复核有 `- /srv/dsh/config:/opt/dshm:ro`（V10 要在容器里跑；没有就补上）

# ② 重建（--trusted-host 是**启动参数** ⇒ 必须重建，restart 不生效）
docker compose up -d --force-recreate
docker compose ps                          # 期望 running (healthy)

# ③ 重取 token（**每个进程一次**；重建后旧 URL 立刻失效）
docker logs --tail 200 dsh-host 2>&1 | grep '^dsh web: ' | tail -1    # 期望 dsh web: https://<INGRESS_HOST>/?token=<TOKEN>
```

```bash
# ④ loopback 侧回归（§4 的「准备」先跑一遍拿 TOKEN）
TOKEN='<③ 里那串>'
NAME='<INGRESS_HOST>'
BASE="http://127.0.0.1:3111"
# ⚠️ 用**目标 Host** 换 cookie（cookie 与 authority 绑定，§14.3）；拿 127.0.0.1 的 cookie 打 $NAME 会得到假阴性 401
COOKIE_N=$(curl -s -D - -o /dev/null -H "Host: $NAME" "$BASE/?token=$TOKEN" | tr -d '\r' | awk '/^set-cookie:/I {print $2; exit}')
node verify-ws.mjs "$COOKIE_N" "$NAME" "https://$NAME"                  # V9  期望 101（--trusted-host 生效）
node verify-ws.mjs "$COOKIE_N" "$NAME" "https://$NAME, wss://$NAME"     # V5  期望 101（Origin 注入生效）
node verify-ws.mjs "$COOKIE_N" "$NAME" "https://evil.example"           # V7  期望 403（没被放宽）
docker exec dsh-host bash -lc 'echo BASH_OK; command -v git'          # V15 期望 BASH_OK + git 路径
docker exec dsh-host node /opt/dshm/verify-pty.mjs                    # V10 期望 PTY_OK
```

```bash
# ⑤ 外部侧（**从手机流量或另一台机器**跑，别在 NAS 上自连自）
curl -sI "https://$NAME/" | head -3                                   # V17 期望 303/200（或 Access 的拦截面）
node verify-ws.mjs "$COOKIE_N" "$NAME" "https://$NAME"                # V18 期望 101
#   → V18 = 「手机端能用」的**必要条件**；101 之后才是手机 App 粘 URL 的端到端。

# ⑥ 手机端到端（本单不含，属 §7）：ConnectPane ① 粘 ③ 那行整串 URL → 起会话 → 跑一条 `bash` 命令
```

**贴回报告时给这几行读数**：②`docker compose ps`、③横幅（token 打码）、V9 / V5 / V7 / V15 / V10 / V17 / V18。

**六个常见坑（§9 都有对应行）**：

1. **`Host` 与 `--trusted-host` 不一致 ⇒ 一律 403**。cloudflared 透传原始 `Host` 时到达的是**入口名**；
   改写成回源 host 时到达的是 `127.0.0.1:3111`（loopback，本来放行）。两种都在放行集合里，
   **前提是填了入口名并且重建过容器**——V9 就是这条的读数。
2. **`restart` 不生效**：`--trusted-host` / `--public-url` 都是**启动参数**，必须 `up -d --force-recreate`。
3. **重建一定要重取 token**，否则手机端会拿着旧 URL 一直 401。
4. **Access**：没建 Access 就等于把 dsh 的 `/api` 挂公网——上游的栅栏是「同源 / 已声明 authority」的防护，
   **不是**面向公网的认证。最低限度确认：无 cookie 访问是 401，而不是直接开门。
5. **若 V9 = `101` 而 V18 = `403`**：说明**到达 dsh 的 `Host` 与已声明的入口名不一致**（cloudflared 侧改写了 Host）。
   两个修法都在**配置层**：① 让回源带上入口名（CF 的 origin request `Host` / `httpHostHeader` 设为入口名）；
   ② 把实际到达的那个 authority 也加进 `--trusted-host`（该参数**可重复**，`--trusted-host a --trusted-host b`）。
   **不要**靠改写 / 删掉 `Host` 头去绕——§3.6.3 明令禁止（那等于拆安全围栏）。这是 CF 模式下最可能踩的坑。
6. **取 token 一律用 `tail -1`**：`docker logs … | grep -m1 '^dsh web: '` 拿的是日志里**最早**那条横幅，
   容器不重建时日志会累积 ⇒ 拿到**上一个进程**的 token（现象：「日志里明明有 token，请求却 401」）。
   正确：`docker logs --tail 200 dsh-host 2>&1 | grep '^dsh web: ' | tail -1`。

---

## 13. 入口就绪后的第一个 403（2026-10-08 开发端实测判读）

**一句话**：Cloudflare 链路**已经通了**，但 `/api` 栅栏把经隧道的一切请求都判 **403** ——
因为 compose 里那两个占位**没填**（`--trusted-host` 里没有入口名）。手机侧此时即使拿到正确地址与 token，
也**拿不到任何会话/工具数据**（WS 升级必失败）。

> ⚠️ **2026-10-08 16:35「回执-2」更正**：占位 **NAS 侧已经填实并重建过**（横幅已是 `https://<入口名>/?token=…`）。
> 本节第 2 条读到的那个 **401** 来自**另一个进程** —— 当时公网这条主机名**根本没打到 3111 这个容器**，
> 而是打在 **3080 的旧 dsh 进程**上。判读与实测证据见 **§14**。

**证据**（全部从**公网**打，不占 NAS 资源；判据与 §4 一致）：

| # | 观测 | 说明 |
|---|---|---|
| 1 | `GET https://<入口名>/` → **401** + 正文 `dsh web authentication required; reopen the URL printed by dsh web.` | CF Tunnel → cloudflared → dsh `127.0.0.1:3111` **全链路 OK**；**没有 Access 拦截面**（要签字认下的风险） |
| 2 | `GET https://<入口名>/?token=<token>` → **401** 且**无 `set-cookie`** | token ≠ 当前进程的 `launchToken`（上游 `authorizeIndex()` 的 `tokenMatches()` 逐字节比较、与 Host 无关）⇒ 拿到的是**旧进程**的 token（见下方坑 1） |
| 3 | WS 升级 `GET /api/remote.mux`（`Host` = 入口名）：**单值同源 403**、**多值（鸿蒙形态）403**、跨源 `evil.example` 403 | 前两条**是 dsh 的 `text/plain` 403（栅栏在拒）**；第三条**本该 403**（反控制臂，说明栅栏没被关掉） |
| 4 | 同 3 但 `Host: 127.0.0.1:3111` → CF 自己的 `text/html 403` | **CF 不允许伪造 Host** ⇒ 改 Host 绕不过去（本来也不该绕，§3.6.3） |

**为什么不矛盾**：栅栏**只保护 `/api`**（在 `/api` 处理器内部、路由命中之后才 `admit()`），
静态根 `/` 不受它保护 ⇒ "**首页能打开**"**不能**当作"手机能用"的证据；判据必须是 `/api/remote.mux` 的 WS 升级。

**修法**：就是 §12 的 ①②③ —— 填 `--public-url` / `--trusted-host` ⇒ `up -d --force-recreate` ⇒ 重取 token。

**坑 1（本轮踩到的）**：`docker logs dsh-host 2>&1 | grep -m1 '^dsh web: '` 取的是日志里**最早**那条横幅；
`restart`（= `up -d`，不重建容器）会让日志累积 ⇒ 拿到**上一次甚至第一次**进程的 token
（现象："日志里明明有 token，请求却 401"）。**正确**：`docker logs --tail 200 dsh-host 2>&1 | grep '^dsh web: ' | tail -1`。

**交接件**：给 Hermes 的**填充版**修复单（含真实入口名与逐条命令）在仓库**外**——
本仓是公开仓库，故真实入口名不落盘。

---

## 14. 回执-2 判读（2026-10-08 16:35，NAS 侧修复回执 + 开发端公网复测）

**结论：NAS 侧「dsh 执行主机」这一层已经**全部就绪**；卡点在**隧道没把新配置拉下来** ——
公网这条主机名仍打在 **3080 的旧 dsh 进程**上，所以手机侧现在仍然连不上。**

### 14.1 已确认就绪（NAS 侧自验收 10/10 + 修复单要求的五项）

| 项 | 期望 | 实际（回执-2） |
|---|---|---|
| V1 / V1b 监听 | 只有 `127.0.0.1:3111` | ✅（无 `0.0.0.0:3111`） |
| V2 横幅 | 一条，且是 `https://<INGRESS_HOST>/?token=…` | ✅（`REPLACE_ME` 计数 `0`） |
| V9 单值同源 | `101` | ✅ `101`（`--trusted-host` 生效） |
| V5 多值 Origin（鸿蒙形态） | `101` | ✅ `101`（`DSHM_ORIGIN_LIST` 注入生效） |
| V7 跨源 `evil.example` | `403` | ✅ `403`（栅栏没被放宽） |
| V15 `bash` + `git` | `BASH_OK` + git 路径 | ✅ `BASH_OK` + `/usr/bin/git`（**镜像这轮才补装 `git`**，原镜像只有 `bash`） |
| V10 真 pty | `PTY_OK` | ✅ `PTY_OK` |
| 注入复核 | `DSHM_ORIGIN_LIST` 计数 = 1 | ✅（路径 `…/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-client-connection/lib/index.js`） |
| V11 / V12 | `10001:10001 host true` / 不挂 `docker.sock` | ✅ |
| `/opt/dshm` 只读挂载 | 有 | ✅（补上了；这是 V10 能跑的前提） |

⇒ `--trusted-host` / `--public-url` **已经填实**（横幅从 `https://replace_me/?token=…` 变成入口 URL）。
**§13「占位没填」那个归因是错的**（见 §13 顶部的更正框）：§13 读到的 401 来自另一个进程。

### 14.2 未达成：公网端到端（阻塞在「隧道指向」）

**决定性证据（回执-2 的双 token 对照 + 开发端复测）**：

| 观测（从公网） | 结果 | 说明 |
|---|---|---|
| `GET https://<入口名>/?token=<3111 的 token>` | **401，无 `set-cookie`** | `/` **不受栅栏保护、只比 token** ⇒ 若打到 3111 就一定 303 ⇒ **请求没打到 3111 这个进程** |
| `GET https://<入口名>/?token=<3080 的 token>` | **303 + `Set-Cookie`** | ⇒ 这条主机名**确实落在 3080 的旧实例上** |
| WS 升级 `Host`/`Origin` = 入口名、**不带 cookie**（单值与多值都试） | **403 `text/plain`** | 收到请求的那个进程**不信任入口名**（3080 实例没有 `--trusted-host`） |

⇒ **CF Tunnel 里 `<入口名>` 的 origin service 实际仍是 `http://192.168.2.88:3080`。**

**为什么控制台改了也不生效**：NAS 上 cloudflared 最后一次
`Updated to new configuration` 停在 **2026-09-25T04:20:25Z** —— 之后**再没拉到过配置**
（最后一次 `Registered tunnel connection`：`2026-10-08T07:50:52Z`，之后持续
`TLS handshake with edge error: EOF` + `Retrying connection in up to 1m4s`，进程还在但一直退避重试）。
⇒ 控制台里的改动处于**待发布**状态：**拉不到新 ingress ⇒ 连接器仍按旧配置把这条主机名送到 3080**。

**cloudflared 连不上 edge 的初判（回执-2 §4.3 的诊断，机制未定论）**：

```
$ getent hosts argotunnel.com
198.18.0.165    argotunnel.com        # 198.18.0.0/15 = fake-ip 段
$ ip route get 198.18.0.165
198.18.0.165 via 198.18.0.2 dev Meta table 2022   # 被 mihomo(TUN) 接管
```

TCP 443 到 edge 通、**TLS 握手被 EOF**。**旁证**：同一条隧道的另一条主机名（走 5666）回 200 ⇒ 隧道/DNS 层面正常，
问题在"cloudflared → CF edge 这一跳"。

> ⚠️ 这属于 **Fluxor/mihomo（另一个服务）**，不在本单 §0.2 的范围内，**NAS 侧不动**。
> 若用户要修，方向是：在 mihomo 的 `fake-ip-filter` 里补 `*.argotunnel.com` / `*.cloudflare.com` 走真实 DNS，
> 或给 cloudflared 进程做 bypass。

### 14.3 【已修进本档】验收方法的一个坑：cookie 绑定 authority

回执-2 §3 是**Hermes 验收时实地发现的**，开发端**读上游代码逐条复核无误**
（`@deepseek-ai/dsh-client-connection/lib/index.js`）：

- `authorizeIndex()`（第 391–411 行）mint cookie 时把 `requestAuthority(req.headers)` 写进 payload；
  **cookie 名**也是 `dsh-auth-<base64url(sha256(authority))>`（第 284–286 行）
  ⇒ **cookie 与"换 cookie 时用的 Host"绑定**；
- `isAuthenticated()`（第 433–443 行）：`payload.authority !== authority` ⇒ 直接判未认证；
- `requestRejection()`（第 586–589 行）：**先栅栏（403）后认证（401）**
  ⇒ **403 = 没通过 Host/Origin 栅栏；401 = 栅栏已过、认证没过**。
  （这条判据很有用：**拿到 401 说明 `--trusted-host` 已经生效**。）

⇒ 用 `127.0.0.1` 换来的 cookie 去打 `Host: <入口名>`，得到的是**假阴性 401**（既不是 403、也不是 101）。
**正确姿势**：用**目标 Host** 换 cookie ——
`curl -s -D - -o /dev/null -H "Host: <入口名>" "http://127.0.0.1:3111/?token=$TOKEN"`。
§4 的「准备」与 §4 尾部用法块、§12 的 ④⑤ **已按这条拆成两份 cookie**（`$COOKIE_L` = loopback 用、`$COOKIE_N` = 入口名用）。

### 14.4 仍待办（**都在用户侧**；NAS 侧无新活）

1. **让 cloudflared 恢复连上 CF edge**（14.2 的 fake-ip 那条）—— 它才会拉到新配置；
2. **确认 CF 控制台里 `<入口名>` 的 origin service 是 `http://127.0.0.1:3111`**；
   ⚠️ 若写成 `http://192.168.2.88:3111`，还要防"到达 dsh 的 Host ≠ 声明的入口名"那一类 403
   （处置见 §4 末尾第 5 条与 §9 最后一行）；
3. 之后从公网复核：`curl -s -D - -o /dev/null "https://<入口名>/?token=<3111 的 token>"`
   **期望 303 + `Set-Cookie`**（现在回 401，因为还打在 3080）；
4. **手机端到端**（ConnectPane 粘 URL → 起会话 → 跑一条 `bash`）**由开发端做**，NAS 侧不动手机。

### 14.5 一个副作用（照实记）

`<入口名>` 现在**指向 3080 的旧 dsh 进程**，而那个进程不信任这个 authority ⇒ 这条主机名下的 `/api` **一律 403**
（**手机、浏览器用这条地址都拿不到数据**）。原来的 `dsh-web.service`（3080）如果还要对外用，
**给它另一个子域名**，别与本单抢同一个名字（同一条隧道的两个 hostname 指向不同回源时，CF 只认先匹配的那条）。
