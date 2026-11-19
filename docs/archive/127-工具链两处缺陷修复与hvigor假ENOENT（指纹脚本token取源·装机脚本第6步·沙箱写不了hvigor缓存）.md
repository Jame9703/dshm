# 127 · 工具链两处缺陷的修复（指纹脚本的 token 取源 · 装机脚本第 6 步）与 hvigor 那条「假 ENOENT」

> 承接 `docs/116` —— `tools/device-code-fingerprint.ps1` 的 **token 取源竞态** 与
> `tools/update-device.ps1` 第 6 步的 **假 FAIL** 都登记在那里，本轮用户原话是
> 「手动测试没问题，看到的工具问题可以顺手修了」⇒ 范围**只限我自己报告过的那两处工具缺陷**，
> 外加本轮实际踩到、且**会把人带偏**的一条构建期假报文（§3，它不是设计变更，是照着它的字面去做会白跑）。
> **性质：改工具 + 一处宿主侧镜像行**；`coreVersion` **未升**（仍 `0.2.1-alpha.1+dshm.25`，理由见 §4）。
> 真机：PC 档 `86E0226429000417`（`const.product.devicetype=2in1`）。

---

## 0. 一句话结论

| # | 事 | 结论 |
|---|---|---|
| 1 | 指纹脚本为什么"时好时坏" | token 的**三个来源**在 PC 档**三个都不可靠**：`host-ready.json` 在 `dsh/home`（0700）里、shell 读不到；日志里所有 `token=` 行都是**客户端请求**行；而 `grep … | tail -1` 会抓到**本脚本自己**刚喂进去的假 token（负控制 `wrongtoken` 常驻日志）。见 §1.1 |
| 2 | 修法 | 分两层：**宿主侧**把权威 token 按本仓既有手法**镜像一行**进 `dshm-host.log`（`main.js` 的 `writeHostReady`）；**脚本侧**改成「按最后一次 `--- boot pid=` 分段 + 段内三级优先 + 形状过滤」，解析留在 PowerShell 里。见 §1.2 |
| 3 | 装机脚本第 6 步的假 FAIL | `aa force-stop` 的**返回值与效果都没人看**：实测它回 `force stop process successfully.` 而进程**还在**，随后 `aa start` 走 **onNewWant** ⇒ **不产生新 boot** ⇒ 第 6 步判"端侧没起来"。见 §2.1 |
| 4 | 顺带发现 | hvigor 的 `00308003 … ENOENT … hvigor.js` 是**硬编码假报文**（`catch` 里任何异常都写成这一句）。实测文件根本不缺，真因是**当前进程写不了 `%USERPROFILE%\.hvigor`**；它自己那句 `delete <workspace> and retry` **不解决**这类问题。见 §3 |
| 5 | 纪律 | 两处改动都**先做负控制再宣布通过**：指纹脚本用 `-Token wrongtoken` 验红、三级优先用 6 条桩表逐条验；装机脚本用「沙箱内跑」验红、「沙箱外跑」验绿。§1.4 / §2.3 / §3.4 |

---

## 1. 缺陷 A：`tools/device-code-fingerprint.ps1` 的 token 取源

### 1.1 三个来源各自怎么坏（全部是真机读数，不是推断）

这个脚本的作用是回答「**设备跑的就是本机这份核心树吗**」，判据是逐字节 sha256。它靠应用自身的
Python 桥（`/dshm-python/*`）读 0700 的 `dsh/home` —— 而**桥要 token**，于是这里有个自指难题。

| 来源 | 设计意图 | 真机上怎么坏 |
|---|---|---|
| 命令行 `-Token` | 人工兜底 | 能用，但要人工先知道 token |
| `dsh/home/host-ready.json` 的 `token` | **权威**（当前进程写的） | **PC 档读不到**：`dsh/home` 是 `0700`、`hdc shell` 是另一个 uid（日志里 `hdc shell` 侧读同一树的失败是常态）⇒ 必然掉到日志兜底 |
| `dshm-host.log` 里的 `token=` 行 | 兜底 | **结构性不可靠**（下面三条都是实测） |

日志兜底的三条实测：

1. **它只有客户端留的痕**：`grep -a 'token=' … \| grep -av IN-REQ \| grep -av IN-DONE` ⇒ **0 行**。
   也就是说宿主自己**从不**在日志里写 token；日志里的 token 全是"某次请求带过来的"。
2. **只在 webview 首次导航时才有**：`GET /?token=<T>`（`status=303`）之后页面改用 **cookie** 鉴权。
   于是"热重启"（webview 已有 cookie）那一次**一条 `token=` 行都没有**（实测某次 boot 段内 0 行）⇒
   脚本只能报「未验证」（rc=2），而设备其实好好的。
3. **`tail -1` 会抓到假值**：脚本自己的负控制 `-Token wrongtoken` 会**永久留在**这份跨 boot 追加的
   日志里。实测 `grep -ao 'token=[A-Za-z0-9_-]*' … \| tail -1` 三次都返回 `wrongtoken` ——
   于是"权威值"变成我刚喂进去的假值，桥回 401，脚本把**偶发**说成事实。

### 1.2 修法（两层，缺一层都不够）

**① 宿主侧：镜像一行（`hostcore/app/main.js` 的 `writeHostReady`）**

```js
if (token.length > 0) {
  log(`host-ready token=${token} port=${payload.port} pid=${process.pid}`);
}
```

这不是新发明的手法 —— `main.js` 里**已经有**同款先例：探针读数（exec / 终端能力）因为
"`dsh/home` 是 0700、外部核查读不到 `host-ready.json`"而被压成一行写进 `dshm-host.log`。
token 是**同一类事实**（外部核查必须能拿到），之前却只靠"客户端碰巧留了一行"。
暴露面没有新增：UI 自己的 `GET /?token=…` 请求行本来就把 token 明文写在日志里。

**② 脚本侧：分段 + 三级优先 + 形状过滤（全在 PowerShell 里做）**

| 级别 | 取什么 | 为什么是这个优先级 |
|---|---|---|
| 1 | `host-ready token=` 行 | 宿主自己镜像的**权威**行（当前进程） |
| 2 | `GET /?token=` 行 | 宿主**页面自己**的请求，用的必是当前进程活的 token |
| 3 | 任意 `token=` 行 | 兜底，仅在本轮有客户端用过 `?token=` 时才可能命中 |

外加两条守卫：

- **boot 分段**：先用 `grep -an '--- boot pid=' \| tail -1` 拿**最后一个 boot 的行号**，
  段内候选行号必须**严格大于**它（`-le bootNo` 一律丢弃）⇒ 上一个进程的 token 不可能被采用。
- **形状过滤**：只认 `[A-Za-z0-9_-]{20,}`（真 token 实测是 43 字符的 base64url）⇒ `wrongtoken`
  这类人工短串被滤掉。

### 1.3 为什么**不**在设备侧用 awk 解析（实测踩到，别改回去）

修这个缺陷时先写的是"一行 awk 做分段+三级优先"，**交互式跑同一个字符串完全正常**，
放进本脚本用 `-File` 跑却报 `awk: syntax near '}'` 并返回空。取证靠**设备侧回显**：

```
# 交互式（正常）          设备侧收到：BEGIN{rdy="";tok="";any=""} …
# 本脚本 -File（坏）       设备侧收到：BEGIN{rdy=;tok=;any=} …      ← 所有 " 都被吃掉
```

⇒ PowerShell 对"含内嵌双引号的原生参数"在 `-File` 上下文里做引号处理时会**丢掉这些 `"`**，
装 awk 程序这种"程序里必须有字符串常量"的用法正好踩中。
故最终形态**不让传参里出现内嵌双引号**（grep 用 `-F` 固定串），解析留在 PowerShell 侧 ——
这层地雷就没有了，顺带也省掉了"设备侧 awk 正则风味"这个不确定量。

### 1.4 判据与验证

| 验证 | 命令 | 期望 | 实测 |
|---|---|---|---|
| 正向 | `powershell -File tools\device-code-fingerprint.ps1` | 10/10 一致、rc=0 | **10/10**、`token 来源：dshm-host.log 的 host-ready 行（本轮 boot 段）（长度 43）`、**rc=0** |
| 负控制（假 token） | 同上 `-Token wrongtoken` | 桥 401、rc=2 | `桥回了 401（token 不被当前进程接受）`、**rc=2** |
| 三级优先/分段（桩表） | 用函数桩喂 6 组日志行、跑**从脚本里抽出来的**那段代码 | 见下 | 6/6 全符合 |

桩表的 6 条（`ok` = 与设计一致）：

| 用例 | 场景 | 期望 | 实测 |
|---|---|---|---|
| A | 本段有 `host-ready` 行、其后还有页面行 | 取 `host-ready` | ok |
| B | 三条候选**全在上一段** | 取不到（空） | ok |
| C | 本段无 `host-ready`、有页面行 | 取页面行 | ok |
| D | 本段只有短串 `wrongtoken` | 取不到（空） | ok |
| E | 日志里**根本没有 boot 行** | 退回"不过滤"（仍取 `host-ready`） | ok |
| F | `host-ready` 行号**等于** boot 行号 | 丢弃，退到页面行 | ok |

---

## 2. 缺陷 B：`tools/update-device.ps1` 第 6 步（冷启动）

### 2.1 根因：force-stop 的返回值没人看，于是"停不掉"伪装成"起不来"

原实现是 `Shell "aa force-stop $bundle" | Out-Null` —— **输出与返回值都不看**，随后只轮询
"本轮 exec 探测是否增加"。真机那次的实际链路是：

1. 旧进程的事件循环正卡在 statSync 风暴里（日志有 `LOOP-GAP 17964ms`）；
2. `aa force-stop` **回** `force stop process successfully.` 而 `pidof` **仍非空**；
3. 紧接着 `aa start` 只能走 **onNewWant**（复用已有 ability）⇒ **不产生新 boot**；
4. 日志里没有新的 exec 探测 ⇒ 第 6 步报 FAIL「端侧没有起来」，
   而**应用一直在跑**、跑的也还是**旧代码** —— 这正是最坏的一种报告：**假红**。

### 2.2 修法（四条，都是"把不可观察变可观察"）

| # | 改动 | 为什么 |
|---|---|---|
| 1 | 判据换成 `pidof <bundle>`（不再信 aa 那句话）+ **3 次重试**（退避 2/4/6 s） | 实测那句 `force stop process successfully.` **会撒谎**；重试是必需的（第二次就停掉了） |
| 2 | 轮询期间**每 15 秒打一条读数**（boot/exec/pid） | 原先 90 秒**全静默**，真机上像卡死；"卡在哪一拍"正是排障要的第一读数 |
| 3 | 超时分支先**再 StopApp 一次**再拉，并把现场打出来（pid / 末次 boot 行 / `ps` / 日志尾 6 行） | 停不掉进程时 `aa start` 必然无效 ⇒ 得说清"这不是装机失败，是停不掉进程" |
| 4 | 记 `POST /dsh-market/restart` 基线，末尾如实报出本轮次数 | 插件市场页面**自己**会要求宿主冷启动（写 `host-exit-mode=app-restart` 后退出、ArkTS 侧再拉起）⇒ 现场看到"App 自己退出了"极容易被读成"新包把 App 搞崩了" |

> 安全面**一个字没动**：仍然只走 `install -r` / `aa force-stop` / `aa start`，第 0 步的
> 「本脚本不含卸载/删数据命令」自检两次运行都 `OK`。

### 2.3 验证

| 验证 | 结果 |
|---|---|
| 标定（先测原始行为） | `aa force-stop` → `force stop process successfully.` / `pidof` 为空 / `aa start` → `start ability successfully.` / **第 5 秒**出现本轮 exec 探测 |
| 端到端 #1（`-SkipRebuild`，已出好的 HAP） | `OK 旧进程已停（pidof 为空）` → `OK 端侧已起来（第 5 秒…）` → home 指纹 **links 13 → 13**（数据保全）→ 核心树 `+dshm.25` 在 → **exec 10/10 全通** → **rc=0** |
| 端到端 #2（含重编，用来同时验 §3 的提示） | 构建成功 → 同上全绿 → **rc=0** |

---

## 3. 构建期那条「假 ENOENT」（沙箱写不了 `~/.hvigor`）

### 3.1 现象

`update-device.ps1` 第 3 步（构建）**0~2 秒**即失败，报文是：

```
> hvigor ERROR: 00308003 Operation Error
Error Message: ENOENT: no such file …\.hvigor\project_caches\2680bdcae53a15bd8534b9894af855ed\workspace\node_modules\@ohos\hvigor\bin\hvigor.js
* Try the following:
  > delete …\project_caches\2680bdcae53a15bd8534b9894af855ed\workspace and retry.
```

### 3.2 取证：四处读数**推翻**"文件真缺"

| # | 读数 | 结论 |
|---|---|---|
| 1 | `fs.realpathSync(<那个 hvigor.js>)` 手测 → 成功，解析到 `C:\Program Files\Huawei\DevEco Studio\tools\hvigor\hvigor\bin\hvigor.js` | 文件**在**，链接**不悬空** |
| 2 | 目标包实测 **2577** 个文件齐全（`bin/hvigor.js` 3954 B、`lib/hvigor-java-daemon.jar` 314,601 B） | 不是"包被删了" |
| 3 | `project_caches/<hash>/workspace/node_modules/@ohos/hvigor` 是 **Junction**（`Directory, ReparsePoint`），指向 DevEco 安装目录 | 缓存的形态本来就是链接，不是拷贝 |
| 4 | 报文出自 `hvigorw.js:31627`，在 `catch (t) { logFormatedErrorAndExit("00308003", "ENOENT: no such file " + n, […]) }` 里 —— try 块里还有 `fork(...)` | **任何**异常都被写成这一句 ⇒ 报文与真因**无关** |

### 3.3 真因

**当前进程写不了 `%USERPROFILE%\.hvigor`**。hvigor 启动时要把它自己的构建工具链
（`@ohos/hvigor`、`@ohos/hvigor-ohos-plugin`）在 `project_caches/<hash>/workspace` 里建好/更新好，
写不进去就在这一步抛错，然后被上面那句硬编码报文盖住。本机的触发条件很具体：
**命令跑在沙箱里**（本轮的 managed sandbox 只允许写工作区）⇒ `.hvigor` 不可写。

### 3.4 修法 + 负控制

修法：`update-device.ps1` 在构建失败时**识别这条报文**（`00308003` / `project_caches`）并把真因、
以及"它那句 `delete … and retry` 不解决问题"直接打出来 —— 否则照它说的去删缓存，**白跑一趟还丢缓存**。

| 验证 | 结果 |
|---|---|
| 负控制（沙箱内跑 `update-device.ps1`） | 构建失败 → **打印人话提示** → `rc=1`（提示与报文同时出现，见 §3.1 的原文） |
| 正向（沙箱外/提权跑同一入口） | `> hvigor BUILD SUCCESSFUL in 15 s 995 ms` → 装机全绿 → `rc=0` |

> **这是长期事实，不是本轮引入**：`tools/update-device.ps1` 的构建段（以及任何 hvigor 调用）
> 需要在**能写 `.hvigor` 的环境**里跑。`AGENTS.md` 的"出包三坑"之外，这条算第 4 个同族坑：
> **报错文本会指错方向**。

### 3.5 同源的沙箱限制：三条门禁必须**在沙箱外**跑（本轮顺带量到）

本轮把 CI 内的 18 条门禁全跑了一遍：**15 条在沙箱内绿**，另有 3 条在沙箱内直接 `spawn EPERM`
（`child_process.spawn` 被沙箱拦）—— 换成沙箱外复跑**三条全绿**：

| 门禁 | 沙箱内 | 沙箱外 |
|---|---|---|
| `tools/check-worker-jitless.mjs` | `Error: spawn EPERM`（rc=1） | `PASS：对照实验成立` |
| `tools/check-internal-undici.mjs` | 同上 | `PASS：…` |
| `tools/check-vm-bash.mjs` | 同上 | `PASS 233/233` |

⇒ 与 §3 是**同一类**：**环境限制伪装成代码失败**。判定口径：报错是 `EPERM/EACCES` 这类
**环境 errno**、且换成沙箱外复跑即绿 ⇒ 不要去改代码。

> 同族还有一条**需要核心树**的门禁：`tools/check-fs-local-permission.mjs` 在沙箱内一样崩，
> 沙箱外 `PASS`（含"删掉补丁退回裸 EPERM"的负控制）。可见这不是个别脚本的毛病，而是
> **本机沙箱与"要起子进程/要写 `%USERPROFILE%`"这两类操作整体不兼容**。

---

## 4. 影响面与未做

### 4.1 为什么 `coreVersion` **不**升

`hostcore/app/*` **不进核心树**：它由 `tools/place-host-app.mjs` 放进
`entry/src/main/resources/resfile/resources/app/`（`assert-resfile-sync` 用**字节**守着这 14 件）。
核心树（`dist/core/work/dsh-core-<ver>`）装的是 npm 包 + 自带插件 + profile，配方在
`hostcore/core-recipe.json`。改 `hostcore/app/*` 不触及核心树内容 ⇒ 与 `docs/115` 同例，
**`coreVersion` 不动**（仍 `+dshm.25`）。

### 4.2 但 `main.js` 随 HAP 走 ⇒ 手持档要拿镜像行必须装新 HAP

本轮只在 PC 档真机验证（`86E0226429000417`）。**手机 / 平板要拿到 §1.2① 的镜像行，需要新的侧载包**
才生效（`dshm-host.log` 里那条 `host-ready token=` 行来自新的 `main.js`）。
本轮**未出正式侧载包**、未 push —— 出包与推送按惯例由用户拍板。

### 4.3 登记未做

| # | 事 | 状态 |
|---|---|---|
| 1 | 手持档（手机/平板）复验本轮改动 | **未做**：等新包 + 用户连机 |
| 2 | `docs/125` 的遗留（皮肤"装上了但没激活"那条链） | **未做**（与本轮无关，继续挂着） |
| 3 | `dsh/cores/0.2.0-rc.2.stale-1791119711686.tmp` 残留目录 | 实测在设备上，**本轮不动**（属历史升级残留；要不要清由用户决定） |
| 4 | `dist/sideload/` 里现存的包与本轮源码**已不同步**（缺 `host-ready token=` 镜像行） | 登记；出包时一并解决 |

