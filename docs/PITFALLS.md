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

### 2.10 换 libnode soname 时，strip 排除名单与 CMake 候选必须跟着换
- **现象**：换 `libnode.so.147` 后构建失败（flock FATAL_ERROR 缺 137）；修完 CMake 后构建成功、
  但包内 libnode 变回未签名字节（sha 等于上游原文件、无 `.codesign`），真机 exec 域必拒载。
- **根因**：两处按**文件名**钉住旧 soname——`hostruntime/src/main/cpp/CMakeLists.txt` 的三处
  候选循环 / 回退值，与 `hostruntime/build-profile.json5` 的
  `nativeLib.debugSymbol.strip.exclude`（旧值 `**/libnode.so.137`）。hvigor 默认 strip 会把
  自签 `.codesign` 段剥掉，排除名单没跟上新 soname ⇒ 签名活不到包里。
- **正确**：换 soname 时同改四处——CMake 候选（含回退值）、strip exclude、
  `sign-bundled-libs.mjs` 目标、`check-node-cli.mjs` 断言；出包后必验
  「包内 libnode 的 sha == 磁盘已签名版」且含 `.codesign` 标记。
- **证据**：2026-11-24 实测（build-profile 同文件 2026-11-05 注记先例；本轮 147 修复记录见
  `JD/from-deveco/20261124-0740-node26-beta-result.md`）。

### 2.11 换 libnode 主版本必须重验 io_uring 中性化——门禁「按设计跳过」= 未测 = 放行崩溃
- **现象**：Node 24→26（147）后，2in1 本机正常，**手机端启动即闪退**：hilog
  `DfxSignalHandler :: signo(31), si_code(1)`（SIGSYS/SYS_SECCOMP），线程 `node-MainThread`，
  `node::Start` 后约 100 ms 进程消失。
- **根因**：libnode 147 里 libuv 的 **17 个 io_uring 系统调用槽全部是活的**（`movz w0,#425/426/427`
  → `bl syscall@plt`，实测 `syscall@plt=0x7049dc0`）；鸿蒙对 io_uring 是 seccomp **SIGSYS 杀进程**
  （不是返回 EPERM）。24.x 的随包件曾用 `patch-libnode-io-uring.mjs` 把这 17 槽改成
  `mov w0,#-1`；换 147 时该字节补丁「按设计跳过」，`UV_USE_IO_URING=0` 对普通 flags=0 路径不生效
  ⇒ 手机 seccomp 直接杀进程。2in1 的 sandbox 允许 io_uring 所以本机无感。
- **正确**：换 libnode 主版本时，`check-libnode-io-uring` **不允许跳过**——必须为新人件重建锚点
  （`.rela.plt` 解析 `syscall` 符号 → 扫 `bl syscall@plt` 且 w0∈{425,426,427} 的槽）并中性化；
  门禁要带 `--self-test` 变异臂（恢复任一槽必须判红）。改完必须重签（字节变化使 `.codesign` 失效）。
- **证据**：2026-11-24 21:20 手机 Mate 80（VYG-AL00, API 26）实测；证据
  `dist/acceptance/20261124-phone-sigsys-io-uring/`（崩溃 hilog 摘录 + 17 槽清单）。

### 2.12 门禁断言写死代码形态，改实现即静默失效
- **现象**：`check-startup-work` 报 `7 !== 6`、`boot` 切片为空、`ensurePythonBridge` 计数 `2 !== 1`；
  代码本身编译与运行都正常。
- **根因**：门禁把**裸调用字面量**与**固定条数**当锚点
  （`'  scheduleToolchainExtraction(resRoot, binDir, true);'`、`requests.length === 6`）。
  把调用包进 `startupWork.request(...)` 后，锚点字符串消失、请求条数 +1，
  门禁失效但构建仍绿 —— 只有跑门禁才会发现。
- **正确**：锚点优先取**结构特征**（如 `startupWork.request('toolchain'`），不要整行字面量；
  条数变化必须与实现改动在同一次提交里同步；修完必跑 `--self-test`
  （本轮 10 个 mutant 全部被拒才算真过）。
- **证据**：`tools/check-startup-work.mjs`、`hostcore/app/main.js:8335`、`docs/201-WorkBuddy启动加载顺序拆解与借鉴.md` §10.5。

### 2.13 `pack-core --skip-install` 复用上次暂存树：回滚裁剪后重打会产出「假容器」
- **现象**：回滚配方 prune 规则后重打，zip 大小 / 条目与裁剪版**一模一样**（wasm 包仍缺失）。
- **根因**：`--skip-install` 在标签一致时**复用上次安装的暂存闭包树**——而那棵树已被上一次
  裁剪运行物理删除过包；`--skip-install --force-install` 组合是「跳过安装且不复用」，树原样不动，
  也不是重装。
- **正确**：配方**回滚类**改动（要把之前裁掉的包加回来）重打时用
  `CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/pack-core.mjs --force-install --place-in-app`
  （不带 `--skip-install`），强制重跑 npm install 还原 optionalDependencies；
  打完必须核 zip 内条目数与体积，不能只看 rc=0。
- **证据**：`dist/acceptance/20261125-core023-audit-report.md` §11、`tools/pack-core.mjs`。

### 2.14 「静态实核加载面」不能替代真机实测：整包裁剪判据必须真机定稿
- **现象**：静态读码判 `libreoffice-kit-wasm` 整包缺失「优雅降级」，裁掉后两台真机 office
  链路硬报 `Cannot find module '@deepseek-ai/libreoffice-kit-wasm/package.json'`。
- **根因**：`lookupEntry` 之外另有 `package.json` 子路径直取的硬依赖，静态实核漏了这一条路径。
- **正确**：整包删除类裁剪，判据 = 静态实核 **+ 真机实测通过** 才能定稿；只做过静态实核的裁剪
  必须标注「待真机」。裁剪规则旁留 `$comment_*` 写证据，回滚时同轮删除规则、保留注释。
- **证据**：`hostcore/core-recipe.json`（`$comment_keep_libreofficeKitWasm`）、
  `dist/acceptance/20261125-core023-audit-report.md` §10 ⑦ vs §11。

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

### 3.10 2in1 桌面 UI 自动化的工具盲区（右键 / 弹窗 / 光标）
- **现象**：自动验证"右键菜单 / 弹窗"类交互时四处碰壁：`uitest uiInput` 无鼠标右键；`uitest dumpLayout -i` 不含 ArkUI 弹窗层（菜单开着也 dump 不出菜单节点）；`verify_ui` 服务端 400（structured-outputs 后端冲突，JD-011 起复现）；`/system/bin/uinput -M` 有右键但仅相对位移，用户正在用机时不可靠。
- **正确**：右键类交互走「人工点击 + 系统侧取证」闭环（hilog 原文 / ps / a11y dump / 截图像素比对四重）；光标位置可读 `hidumper -s MultimodalInput -a '-c'` 的 `lastPhysicalX/Y`；hilog 缓冲分钟级滚动，关键日志当场落盘。
- **证据**：2026-11-20 JD-014 实测（`JD/from-deveco/20261120-pet-float-poc-result.md` 工具链发现节）。

### 3.11 机器侧 dlopen 三铁律：exec 位 + `.codesign` 内嵌 + 路径闭包
- **现象**：从 HAP/HSP 解出的 `.so`/`.node` 在机器（= 鸿蒙设备）上 `process.dlopen` 报 EACCES。
- **根因**：三件叠加——①文件无 exec 位（660 拒，770/755 过）；②未签名 ELF 被 exec 域拒（装机时由 installer 签，zip 解出件丢失）；③E44 形态（NEEDED `libnode.so.147`）无 RPATH 时需 `LD_LIBRARY_PATH` 指向含 libnode 的闭包目录。
- **正确**：`node third_party/ohos-selfsign/selfsign.js <f> <f> --force` 内嵌自签 + `chmod 7xx` + `LD_LIBRARY_PATH=<闭包目录>`；E44 形态在独立 node 下会载入第二个 libnode 实例，注册/实调成功但**退出时 SIGTRAP**——机器独有伪影，设备内单实例无此路径，不判失败。
- **证据**：2026-11-24 JD-041 四 addon 实调（`JD/from-deveco/20261124-1747-jd041-audit-calls-result.md` §3）。

### 3.12 `/tmp` 禁 `flock`（flock errno 表外 EACCES）
- **现象**：`flock(2)` 在 `/tmp` 下恒 `EACCES(13)`（python `fcntl.flock` 同样），flock(2) 的 errno 表（EBADF/EINTR/EINVAL/ENOLCK/EWOULDBLOCK）里根本没有 EACCES。
- **正确**：锁文件路径换工作区/应用数据目录即过（内核对该挂载点的安全策略，非 addon 缺陷）；排查此类"表外 errno"先用 python fcntl 做对照臂再怀疑 addon。
- **证据**：2026-11-24 JD-041 system addon 实调（同上 §3 对照记录）。

### 3.13 `ps -ef` 时间戳滞后 wall clock ~12h10m；`netstat` 双口径
- **现象**：设备 `ps -ef` 的 STIME 与 hilog/墙钟差约 12h10m；同一台机上 shell `netstat -tln` 看不到监听而 `hdc shell netstat` 可见（或反之）。
- **正确**：进程时间线以 hilog/`date` 为准，`ps` 时间戳不用于时序结论；端口占用以 `hdc shell netstat`（走设备 netstat 二进制）为准。
- **证据**：2026-11-24 JD-041 host 链路实测（probe-mux-ws 前置排查）。

### 3.14 shell 不能枚举 `/proc`：在线侦察 in-app 进程只能用 `ps` + uid 过滤
- **现象**：`hdc shell` 里 `grep -l 'x' /proc/[0-9]*/cmdline` 只展开**自身会话**的 2~3 个进程（readdir 受限），对 app 进程永远 0 命中——据此判「app 没派生进程」会得出反向结论；`/dev/pts` Permission denied；`/proc/<pid>/task/*/children` 内核未开（不存在）。
- **正确**：判 app 内 fork/exec 用 `ps -ef | awk '$1==<app_uid>'` 连续采样（约 30 样本/秒，可捕获 5–20 ms 瞬态子进程）；`/proc/<pid>/cmdline`、`/proc/<pid>/stat` **显式路径**可读（可核 uid/comm）。app uid 可由 `ls -ld /proc/<apppid>` 或 `ps` 确认。
- **证据**：2026-11-24 JD-041 E15 取证（`dist/acceptance/20261124-jd040-node26-guard-local/evidence-uid-watch-5boots.log`：app uid 抓到 `sh`/`node`/`gh`/`git-remote-http`/`binary-sign-tool` 等瞬态进程）。

### 3.15 0.2.3 webserver 路由默认 `auth:"required"`：本地 host 路由不写 auth 即 401
- **现象**：真机诊断 PC r2 / 手机 r51 的 python（`/dshm-python/exec` 等）与 browser
  （`/dshm-browser/start` 等）探测全 401，功能实际可用。
- **根因**：0.2.3 `dsh-host-webserver` 的 authPolicy 为 `auth ?? "required"`——不写 `auth`
  字段就走 admission 鉴权（`webserver/authorize`），Web 侧未带鉴权头直接 401；
  0.2.2 旧 webserver 无此字段语义。
- **正确**：本地 web→host 路由（`hostcore/app/main.js` 10 处 + `dshm-pet-host.cjs` 1 处）
  显式 `auth:'anonymous'`；真实防护保留 handler 内 token 检查 + `isTrustedRequest` 403 栅栏。
  门禁 `tools/check-webserver-route-auth.mjs`（11 路由 + 6 变异自检）钉住，防删注册漏 auth。
- **证据**：`tools/check-webserver-route-auth.mjs`、
  `dist/core/work/dsh-core-0.2.3-alpha.2+dshm.1/node_modules/@deepseek-ai/dsh-host-webserver/lib/index.js`
  （authPolicy 段）、`dist/acceptance/20261126-full-gates.txt`。

### 3.16 资源投放 hook 只挂「本轮刚解包」分支：升级用户永远拿不到
- **现象**：`dshm-pysite.tar.gz`（13 MB，pptx/lxml/Pillow 等）明明随 HSP 在包，真机升级后
  `$HOME/py-site` 恒空，`python3 -c "import pptx"` 失败（诊断 v3 R4）。
- **根因**：`ensurePythonSitePreset()` 只在 `finishToolchainExtraction` 的 `didPy` 分支调用；
  升级设备 python 早已就绪 ⇒ 稳态 boot 走 `finalizeToolchain()` 分支，永不投放。
- **正确**：资源投放类 hook 必须在**稳态 boot** 也跑（自身幂等：仅空目录解）；只挂在
  「本轮刚解包」路径等于只服务新装用户。同类风险：核心数据迁移、缓存预热、新随包资产。
- **证据**：`hostcore/app/main.js`（`scheduleToolchainExtraction` 稳态分支 + `ensurePythonSitePreset`）、
  `.workbuddy/memory/2026-11-26.md`、Desktop 诊断 v3 R4。

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

### 4.6 `cmd | tail` 后取 `$?` 拿到的是 tail 的退出码
- **现象**：`node gate.mjs | tail -2; echo $?` 打出 0，以为门禁绿；实际门禁是红的（本会话
  权限面 19≠20 已判红却显示 `PERM_RC=0`，同一会话内连中两次）。
- **根因**：管道最后一段是 `tail`，`$?` 取的是 `tail` 的 rc；门禁真实 rc 被吞。
- **正确**：要真 rc 就先落文件再取——`node gate.mjs > /tmp/x.out 2>&1; echo $?`，之后再看文件；
  或用 `bash` 的 `set -o pipefail`（本机 sh 不保证支持，优先落文件方案）。
- **证据**：2026-11-24 本机实测（`check-permission-surface` 假绿事件，见
  `JD/from-deveco/20261124-0740-node26-beta-result.md` §1.3）。

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
| 换 libnode soname | CMake 候选 + strip exclude + 签名/断言四处同改；验包内 sha |
| `cmd \| tail; echo $?` | `$?` 是 tail 的 rc；先落文件再取真 rc |
