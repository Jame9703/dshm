# 坑与红线（Pitfalls & Guardrails）

> 只记**重复发生过**或**一犯就不可逆**的坑。每条都给：现象 → 根因 → 正确做法 → 证据。
> 证据一律指向 `docs/archive/`（历史档，只读）；现行流程以 `AGENTS.md` 与 `AGENT-HANDOFF.md` 为准。

---

## 1. 不可逆 / 数据安全

### 1.1 裸卸载 = 永久丢用户数据
- **现象**：`hdc uninstall` / `bm uninstall` 后，历史会话、插件、工作区全没；系统备份为空。
- **根因**：`el2` 是用户数据分区，卸载即删；同签名覆盖安装只替换 `el1`。
- **正确**：永远 `hdc install -r`；换签名导致覆盖失败时才考虑 `uninstall -k`，且必须先问用户。
- **证据**：`docs/archive/80-真机更新与数据保全.md`。

### 1.2 删除签名物料 = 只能换身份
- **现象**：`SignHap` 报 `00303107 Invalid storeFile` / `ENOENT ... material`。
- **根因**：`signing/**`、`.certs/**`、`build-profile.json5` 里的口令与私钥只有一份。
- **正确**：永不删；重建身份会导致不能覆盖安装，进而被迫卸载（连锁到 1.1）。
- **证据**：`AGENTS.md` §4.2、`docs/archive/80-*` §7。

### 1.3 「删权限」当排障 = 终端 / 文件 / ELF 全废
- **现象**：删到 8 条后，宿主域降级，guest 与原生 PTY 都起不来。
- **根因**：`CUSTOM_SANDBOX`、`ALLOW_EXTERNAL_NATIVE_CODE`、目录权限有硬依赖。
- **正确**：权限面 entry 18 / phone 9 逐位钉死；ACL 以发布 Profile 的 `allowed-acls` 为准；
  排障按「声明面 / Profile / 设备实读」三类证据走。
- **证据**：`docs/archive/143-*`、`144-*`、`222-*`。

---

## 2. 构建 / 出包

### 2.1 改了插件或核心树，却没重打容器
- **现象**：源码改了、包也出了，设备行为仍是旧的。
- **根因**：`resfile/dsh-core-*.zip` 是静态产物，打包不会自动重生成。
- **正确**：`CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/pack-core.mjs --skip-install --place-in-app`，
  再跑 `check-resfile-core-zip`。只重打不加 `--place-in-app` 不会写进 app。
- **证据**：`docs/archive/268-*` §2。

### 2.2 从 `.app` 里解出来的 HAP/HSP 装不上（`956320`）
- **根因**：`.app` 里的模块条目没有独立签名。
- **正确**：用 module 产物目录里的 `*-signed.hap` / `*-signed.hsp`。
- **证据**：`docs/archive/421-*`、`AGENT-HANDOFF.md` §3.3。

### 2.3 canonical Beta 侧载报 `9568322`
- **根因**：`build-beta.mjs` 用的 debug Profile 与 `build-profile.json5` 的证书不是同一密钥。
- **前置**：`devecocli signature generate` 需已登录（`devecocli auth status`）；未登录报 `Run devecocli auth login to sign in`，先 `devecocli auth login`。
- **正确**：本机安装走 local-install（`devecocli signature generate` 重签后再构建）。
  不要卸载、不要硬装。
- **证据**：`AGENT-HANDOFF.md` §3.3。

### 2.4 `--modules phone` 空转、phone 产物路径特殊
- **现象**：`devecocli build --modules phone` 只有 1 个 task，无产物。
- **正确**：用 `--product phone`；产物在 `phone/build/phone/outputs/default/`（`phone/build/default/` 是旧缓存）。
- **证据**：`docs/archive/236-*`（平板侧栏常驻）+ `AGENT-HANDOFF.md` §3.3。

### 2.5 `devecocli build` 不带 `--product` 会报 “Multiple entry modules found”
- **现象**：`devecocli build` 直接失败，提示 entry / phone 两个 entry 模块。
- **根因**：本工程是双 entry HAP；CLI 无法替你选。
- **正确**：`devecocli build --product default` 或 `--product phone`。Beta / AGC 脚本已各自指定 product。
- **证据**：2026-11-18 实跑（未登录环境下 `--product default` rc=0 / BUILD SUCCESSFUL）。

### 2.6 safe-delete 阈值（50）拦构建
- **现象**：`assembleApp` / `pack-core` 中途被 safe-bin 拦下。
- **正确**：只对**单条**构建命令加 `CODEBUDDY_SAFE_DELETE_ENABLED=0`，不要全局关。
- **证据**：`AGENTS.md` §5 末尾注记、`docs/archive/367-*`。

### 2.6 回放门禁用了旧基线，新增门禁漏网
- **现象**：本地全绿，CI 却红；或反之。
- **根因**：`rerun-gates.py` 回放的是基线报告里的命令清单，旧基线不含新门禁。
- **正确**：改过 `gates.yml` 就用 `gen-full-yml-gates.py` 重生成全量基线，再用最新全量报告回放。
- **证据**：`docs/archive/420-*` §4。

### 2.7 把「`signature generate` 要登录」误当成「构建要登录」
- **现象**：文档或口头说“先 `auth login` 再出包”，让本可离线完成的构建被登录卡住。
- **事实**：`devecocli build`、`tools/build-beta.mjs`、`tools/build-agc.mjs` 只用仓库内 `debug` / `release`
  签名物料，不调用 `signature generate`。2026-11-18 模拟未登录实测：`build --product default` rc=0；
  `signature generate` rc=1 并报 `Run devecocli auth login to sign in`。
- **正确**：只有 local-install 重签需要登录；其余构建不要提“先登录”。

### 2.8 同 `versionCode` 覆盖安装不刷新图标
- **根因**：系统按 `(bundleName, versionCode)` 缓存图标。
- **正确**：只在用户明确要求升版本时升 `versionCode`；不要为了刷图标自行加版本。
- **证据**：`AppScope/app.json5` 注记。

---

### 2.9 AGC 云调试装不上，先查版本登记，别先改权限
- **现象**：本地新编的 AGC 包在云调试装不上；同版本旧包能装。
- **实测**：1010017 与 1010018 两包逐层比对，只有 `versionCode` 不同；证书 `ca94d463…`、
  Profile `ea6fe380…`、entry 18 / phone 9 权限逐条一致 ⇒ 权限面不是变量。
- **正确**：云调试装的是 AGC 侧已登记版本的包。本地新编的包若没有在 AGC 登记对应 `versionCode`，
  重编多少次都一样；先确认/上传 AGC 版本，再云调试。拿不到错误码时不要靠猜权限。
- **不要**：删 `ACCESS_USER_FULL_DISK` 之类的权限"试一试"（PC 全盘访问会失效，且违反权限面铁律）。

## 3. 端侧运行时

### 3.1 块注释里写 `*/` 导致宿主编译崩
- **现象**：`main.js` 语法错误 → SIGABRT 闪退。
- **正确**：注释里避免裸 `*/`（比如 glob `cores/*/` 要转义或换写法）。
- **证据**：`docs/archive/353-*` §5。

### 3.2 busybox 没有 `ls` / `sort` / `awk` / `sed`
- **正确**：端侧脚本用 glob + 内建 `test`；不要依赖完整 coreutils。
- **证据**：`docs/archive/353-*` §5。

### 3.3 `bin/dsh` 写死版本 / 依赖 `HOME`
- **现象**：换核心后 `dsh` 找不到树；`.106/.107/.109` 连断三次。
- **正确**：路径从脚本自身位置推导（`$0` → `bin/` → 沙箱根 → `dsh/cores`）。
- **证据**：`docs/archive/353-*` §5、`check-dsh-cli-current-core`。

### 3.4 端侧 `fs.writeFileSync` 不存在
- **正确**：`openSync + writeSync + closeSync`。
- **证据**：`docs/archive/353-*` §5。

### 3.5 `RunningLock` 必须用三参回调重载
- **现象**：ArkTS 编译报错。
- **正确**：`createRunningLock(name, type, callback)`。
- **证据**：`docs/archive/353-*` §5、`check-keepalive-wiring`。

### 3.6 jitless 下全局 `fetch()` 崩
- **根因**：第三方代码绕过垫片直接走全局 fetch/WASM。
- **正确**：保持两层垫片（模块解析 + HTTP 派发）；新增能力走 `dshmFetch`。
- **证据**：`docs/archive/291-*`、`check-fetch-shim`、`check-internal-undici`。

### 3.7 桥方法泄漏导致日志风暴 / 卡顿
- **现象**：`__DSHM_BRIDGES__` 每分钟数百次报错，输入卡顿。
- **根因**：方法进了 `methodList` 但没有真实实现。
- **正确**：新桥方法必须同时改 `check-bridge-methodlist` 与实现。
- **证据**：`docs/archive/277-*`。

### 3.8 端口偏移断链
- **现象**：侧栏浏览器一直「正在打开」。
- **根因**：浏览器扩展写死 19390，beta 宿主听 19391。
- **正确**：端口从配置/桥获取，不写死；改端口同步扩展与宿主。
- **证据**：`docs/archive/281-*`。

### 3.9 设备分档白名单加错型号 = 普通平板被判 desktop、终端不可用
- **现象**：`MRO-W00` 真机上 VM 被关死，终端打不开。
- **正确**：`EDGE_FAMILY_TOKENS` 只含 `QXS`；市场名靠 `MatePad Edge` / `Pro Max` 分词。
- **证据**：`docs/archive/413-*`、`check-edge-desktop-policy`。

---

## 4. 文档 / 协作

### 4.1 「文件:行号」引用必然漂移
- **正确**：文档引用用节标题或相对链接；`check-doc-refs` 只兜底，不替代纪律。
- **证据**：`tools/check-doc-refs.mjs` 头注。

### 4.2 流水账文档会让人失忆
- **现象**：同一问题 5 篇文档互相推翻，没人知道当前口径。
- **正确**：一问题一篇；结论进 `AGENTS` / 台账 / 坑档；过程进 `docs/archive/`。
- **证据**：`AGENTS.md` §10。

### 4.3 本机 `devecocli docs search` 不可用
- **现象**：报 `better-sqlite3` 原生绑定缺失。
- **正确**：改用本地知识库 `~/data/HarmonyOS-KB`（`catalog/docs.jsonl` + `docs/<alias>/<slug>.md`），
  或直接读归档文档。不要在这一点上反复试。
- **证据**：本机 2026-11-18 实跑。

### 4.4 toybox `grep` 不支持 `\|` 会静默漏报
- **现象**：`grep "a\|b" file` 返回空，看起来像"改动没生效"；实际是 BRE 交替不被支持，且**不报错**。
- **根因**：端侧 / 本机 toybox grep 只认基础正则的子集，`\|` 被当作字面量。
- **正确**：用 `grep -E 'a|b'`；判断"内容是否变化"更稳的是 `python3` 的 `in` / `re`。
- **门禁里的同一坑（2026-11-18 外部复核假红）**：`check-guest-terminal-lifecycle` 让被测脚本直接跑宿主
  `grep -Fxq`，在 toybox grep 环境下静默返回 1 ⇒ 门禁报「TERM/KILL 丢失」，换台机器又绿。
  **规则：门禁的判据不许依赖宿主 `grep/sed/awk`；必须像 `tr` 一样在临时 `PATH` 里桩化。**
- **证据**：2026-11-18 本机实测（同族漏报见 `docs/archive/278-*`）。

### 4.5 把「包结构核验通过」说成「真机可用」
- **正确**：两者分开写；release 包不可侧载，平板/手机需用户真机自测。
- **证据**：`AGENT-HANDOFF.md` §8。

---

## 5. 老坑速查（一句话）

| 坑 | 一句话处置 |
|---|---|
| 裸 `hdc uninstall` | 永不；只 `install -r` |
| 删 `signing/**` | 永不 |
| 删权限排障 | 永不；先看三类证据 |
| 自己加 `versionCode` | 永不；等用户明确要求 |
| `git commit` | 永不；用户明令禁止 |
| 从 `.app` 解模块装 | 不可；用 `*-signed.*` |
| 只出包不重打容器 | 行为不生效 |
| 用旧基线回放门禁 | 新门禁漏网 |
| `rm` 删文件 | 被 shim 接管；用 python 并回读 |
