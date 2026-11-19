# D-01 / D-R1 本轮独立反证复核

## 范围与判定

项目根：`~/data/DSHM-deveco-workspace`。本轮仅把 `review.md` 当候选定位表，没有以其定性、历史 docs、memory 或旧 acceptance 作为正确性证据。以下引用行号均为本轮读取的文件。没有修改源码、配置、资源，没有 build/deploy/device 操作，没有 Git 操作，没有运行验证代理或导入生产入口。唯一主动写入是本报告。

| 项 | 本轮结论 | 成立边界 | 真实最小复现 |
|---|---|---|---|
| D-01 | **确实存在** | live profile 中已有 npm 包，成功解析出不同版本，旧目录删除成功，随后下载/校验/解包等失败；直接队列安装不保旧 | **没有**生产安装器、网络或真实文件系统故障注入；仅纯内存顺序模型 |
| D-01 附属 tmp TDZ | **确实存在** | npm 完整性检查返回非空错误，执行到初始化前的 `tmp` 引用 | JavaScript 同构词法作用域最小例已执行；不是生产安装器端到端复现 |
| D-R1 | **确实存在（源码及本机 SDK 契约层面）** | 探写实际运行、目标目录中已有可读写的固定名普通文件，open 成功；不要求删文件成功才算内容受损 | **没有**实际 HarmonyOS fileIo/ROM 文件操作复现；仅 SDK 契约的内存模型 |

“确实存在”指可达源码与已取得契约构成因果链，不表示已发生用户事故。D-R1 的系统在线文档与真机授权行为仍有缺口，不能宣称所有设备每次都会丢文件。若以“必须取得在线官方文档或真实 ROM 复现”作为确认标准，D-R1 的**设备事故主张**只能算条件性存在，而非已确认事故。

## D-01：旧包删除与失败恢复

### 当前活跃 UI：不能只用旧原生页面证明

本次补核当前承载页：`entry/src/main/ets/entryability/EntryAbility.ets:1463` 和 `phone/src/main/ets/entryability/EntryAbility.ets:1349` 均 `loadContent('pages/WebApp')`；两页分别在 `entry/.../pages/WebApp.ets:7079`、`phone/.../pages/WebApp.ets:6213` 创建加载 launchUrl 的 Web。`SettingsPlugins` 虽被旧 `SettingsPane.ets:492` 引用，但**不能据此认定当前默认 Web 页面挂载这个原生安装页**。下节保留其队列生产者证据，不再把它单独作为当前 UI 可达证明。

实际核心的路径前缀统一为 `dist/core/work/dsh-core-0.2.2-rc.2+dshm.1/node_modules/@deepseek-ai/`，下列 UI/manager 路径均接在此前缀之后：

1. `dsh-web-app/cordis.patch.yml:341-342` 登记 `ui-plugin-manager`。`dsh-client-ui-plugin-manager/lib/client.js:2` 是长行压缩产物，不能虚构展开后的行号；以下附字符列（按 Unicode 字符、1 起算）便于定位。第 `328356` 列附近注册 main 插件面板，第 `327664` 列附近以 `pluginManager/listBundles` 访问权接通刷新和操作事件。
2. **当前“添加插件”确有防重复保护**：同文件 `2:168870` 附近在 `listed !== undefined && listed.availability !== 'missing' && catalogSubject === undefined` 时返回 already-installed/shipped；`2:170243` 附近调用 `remote.pluginManager.inspect()`，`2:171231` 调用 `remote.pluginManager.installBundle(spec, options)`。因此不能说“当前添加页任意填已装版本一定直接换版”。此外 manager `lib/index.js:3042-3044` 在 HMR 存在且 known 已登记时再次拒绝。
3. **当前版本更新使用的确实是有兜底的接口**：UI `client.js:2:160687` 调用 `remote.pluginManager.updateBundle(packageName, to, ...)`。manager `lib/index.js:2691-2715` 检查目标、semver 更新方向和 registry/Git 计划，失败在这里不会删包；`2725-2742` 的无 HMR 分支直接安装；`2762-2791` 的 HMR 分支 remove → install → 失败时 install previous。它不是“下载失败无条件永久丢旧版”的证据。
4. **有兜底不等于本地事务保旧**：manager `3217-3237` 的 removeBundle 在 not-removable、stop-profile 或 bundle-in-use 条件下拒绝，只有移除实际成功才继续更新；成功移除交 `runPnpm(['remove', name])`。`3284-3314` 的 runPnpm → `839-854` 进程内桥 → `hostcore/plugins/dshm-profile-pnpm/lib/index.js:369-380,508-515` 写 `.rem/.req + .dir` → main `8834-8839` → removeSpec/installSpec。installer `1952-1957` 物理删除旧 node_modules，`1969-1991` 移除清单登记，没有重命名保存旧目录。更新的恢复操作是再安装旧来源，不是从本地备份改名恢复；若新版本和旧来源下载都失败，旧目录仍不存在。如果旧来源安装成功，则该更新入口恢复可用，原先笼统“失败无恢复”的说法不成立。
5. **另有当前 catalog 更新操作先卸载再打开安装向导**：UI `client.js:2:156685` 附近的 `update` action 对已安装且非 installation 的包调用 `removeBundle()`，随后 `openCatalogInstall()`；它不同于第3项 `updateBundle()`。此回调本身未保存旧包或调用旧版重装，不能把另一个接口的兜底强加于它；但本轮没有把所有 catalog 卡片显示条件逐一跑 UI，故这条只作为代码内已接 controller action 的补充路径，不宣称所有可见“更新”按钮都走它。
6. **全局 operation wrapper 没有暗中恢复目录**：manager `3455-3500` 的 change() 对 package.json 加锁、捕获错误转 failed/cancelled、比较 diskState、发 changed 事件；未复制或还原 node_modules。installBundle `3049,3160-3162,3350-3359` 的 restoreFiles 仍只有两份清单文本。registry 重试 `3099-3129` 只在故障分类允许时换源，不保证最后一定安装成功。

默认注册不能替代实际服务状态取证：`dsh-base/cordis.patch.yml:20-32` 同时按 profileContext 注册 manager/HMR，HMR 并非静态无条件禁用。ondevice 的 `patchReload=startup` 也不能直接等同于 `ownerContext.get('hmr') === undefined`。本轮没启动 Host，不判定设备当前 HMR 对象是否可用；**两分支结论分别成立**。

以上 UI client、dsh-base patch、dsh-web-app patch 均另以 Python zipfile 只读内存核对，确认实际随包 zip 对应成员与本次引用 work 树逐字节相同。未导入这些生产文件。

**最终可达性分层**：安装器先删旧包机制确实存在；当前活跃 UI 的标准更新入口存在旧版重装兜底，故“UI 新版安装失败就一定无恢复”是误报式扩大。对标准更新，应改判为“旧版恢复也失败时条件性丢失旧安装”；对直接队列/CLI 安装，则不存在该 updateBundle 包围层。旧 SettingsPlugins 页只证实生产者实现，不再充当活跃 UI 的唯一证据。

### 直接队列与安装器路径

1. `entry/src/main/ets/view/SettingsPlugins.ets:248-270` 的 `startInstall()` 取输入 trim，仅拒绝空串或本页 busy，直接写 `filesDir/dsh/home/install-queue/<id>.req`。这里不拒绝已安装包、不强制预取、不做旧包备份。失败处理在 `285-305` 只是读 `.fail`、显示错误。
2. `hostcore/app/main.js:8695-8725` 读取请求及可选 `.dir`，取走即删除 req。`8777-8816` 解析 spec/命令并核对显式目标目录，`8820-8839` 调用 `pluginInstaller.installSpec()`。串行锁 `8663-8665` 解决并发，不提供事务。
3. `hostcore/app/dshm-install-command.js:159-166` 单 token 原样作为 spec；`277-291` 完整命令同样返回单目标 spec。用户输入 `example-plugin@2.0.0` 可以直接到安装器。显式 `--dir` 在 main 的 profile 子树检查只约束路径，不检查是否换版，也不产生备份。
4. `hostcore/app/dshm-installer.js:603-655` 先读取 registry 元数据，选择目标版本并取得 tarball 地址及完整性字段；`1372-1385` 成功解析之后定位 `profileDir/node_modules/resolved.name`。
5. `1095-1104` 只对 npm、两侧非空版本作不等判断。`1398-1409` 只有“可加载且不漂移”才跳过；已有可用 `1.0.0` 请求 `2.0.0` 不会跳过。`1417` 保存的是旧**版本字符串**，不是包内容；`1418` 删除旧目录，`1421` 才 fetch tarball。
6. 下载 reject、`1434` gunzip 抛错、`1437` 解包抛错均向外退出；`1306-1311` 只把异常变为 `{ok:false,error}`。`main.js:8848-8858` 仅成功才重放市场补丁，然后写 `.done/.fail`；`8864-8882` catch/finally 也只写失败结果并释放 busy，不还原包。

直接安装相异 npm 版本是队列协议接受的请求。当前 CLI shim 的独立入口在 `hostcore/app/main.js:2866-2909`，将 add/install 目标写 req 和 dir，`2924-2930` 收到 fail 仅显示并返回失败，没有 old-version 恢复。是否某设备 shell 能执行该 shim 是运行时条件，不能据生成脚本本身称所有手机 CLI 可用；当前活跃 Web manager 则通过进程内桥接通同一 main 队列，不依赖 shell。本轮不假设指定示例包实际在 registry 存在，而是以“已有合法包及可成功解析的另一个版本”为前提。

### 真正的反证及为何不是全局兜底

| 机制 | 本轮源码证据 | 对本问题的作用 |
|---|---|---|
| 同版幂等 | installer `1398-1409` | 可用且版本相同时保留，不属于触发集合 |
| registry 元数据 fallback | installer `613-637` | 元数据阶段还未删旧包；该阶段失败不造成此损失；不是 tarball 失败后的回滚 |
| 新包 tmp | installer `1434-1437,1524-1543,1592` | 是新包解压目录，旧目录已在 `1418` 删除；`1529` 还会删除最终目标，`1542` 的“回滚”只删新包，不恢复旧包 |
| GitHub → npm fallback | installer `1566-1584` | 只覆盖 GitHub 无子目录、仓库同一性匹配、落位不可加载这一特定分支；不处理普通 npm 下载/校验错误 |
| 下载缓存 | installer `158-201` | TTL 120s、总量32MiB、8条、单条超上限不缓存；可能让同 URL 第二次下载成功，但不保存旧目录且会失效/淘汰，不是事务保证 |
| 市场临时目标 | `hostcore/plugins/dshm-market-bridge/lib/index.js:200-214,227-239,326-331,362-396` | `--dir` 优先并写 `.dir`，确实允许隔离目录安装；若目标是临时目录，不会删除 live 旧包。但这不是 main 对所有请求强制套用的机制 |
| 官方 manager 的安装拒绝 | 实际核心 `dsh-plugin-manager/lib/index.js:3042-3044` | 有 HMR 时，直接 installBundle 已登记的 known 包会拒绝 already-installed，部分官方入口确实挡住换版；原生 SettingsPlugins 写 req 绕过它 |
| 官方 manager 的文件恢复 | 同文件 `1734,3049,3160-3162,3350-3359` | `RESTORED_FILES` 只有 `package.json`、`pnpm-lock.yaml`；恢复文本不恢复被删的 node_modules |
| 官方 updateBundle 的旧版本重装 | 同文件 `2682-2792`，尤其 `2735-2742,2762-2791` | **确有恢复尝试，不能说全仓没有回滚代码**。无 HMR 分支直接 installTarget；有 HMR 分支先 remove，再安装，失败后以旧 `name@from` 或 Git 来源再次 installBundle。需要重下载旧包且可能失败；只包围该入口，不包围直接 req |
| 真 pnpm 的拒装后 repair | 同文件 `1000-1017` | 原 execa 路径在特定 post-check 警告时恢复清单并执行 install repair；进程内桥在 `839-854` 提前 return，不进入该段。即使走 execa，随包 pnpm shim `main.js:2895-2897` 拒绝无目标 install |
| profile pnpm bridge | `hostcore/plugins/dshm-profile-pnpm/lib/index.js:119-132,369-380,466-538` | 应用环境通常由桥接管，add 请求仍交同一队列。`492-494` 的无目标 install 返回成功但明确跳过，不重建 node_modules；失败仅返回 exitCode 1 |
| 启动自愈/隔离 | main `8167-8169,8277-8296`；`dshm-user-rows.js:878-924,934-1007` | 可以移除坏依赖/bundle 引用、防止启动被坏登记阻断，但没有把已删旧包重建出来。这是宿主保活反证，不是旧插件保全 |
| 救援面板恢复 | `hostcore/plugins/dshm-boot-rescue/lib/index.js:1542-1567` | 删除救援停用标记、恢复 patch/rows 启用，不是恢复安装目录 |
| 核心更新/ffmpeg 事务 | `hostruntime/src/main/ets/core/BundledCore.ets:130-135`；`hostcore/app/ffmpeg-runtime-provision.cjs:144-175` | 管各自 core/ffmpeg 目标，不包围插件队列，不能迁移其保证到 installSpec |

实际核心路径前缀为 `dist/core/work/dsh-core-0.2.2-rc.2+dshm.1/node_modules/@deepseek-ai/`。上述 manager 引用均为其 `dsh-plugin-manager/lib/index.js`，不是旧版本，也不是仅类型实现。

市场 prefetch 的限制：本轮实际随包 zip 不包含 `dshmarket/` 或 `dsh-skin-market/` 社区包成员。桥的 `targetDirFromArgv()` 与 `.dir` 协议可由代码确认，但不能把桥注释里描述的外装社区市场 prefetch 当成已验证的当前市场全流程。也不能据“仓库没有该外装包”认定设备上没有。其上游版本、预取后提交/备份/恢复完整性仍属未知；不影响直接 req 的反例。

### tmp TDZ

installer `1427-1435`：`verifyTarballIntegrity()` 返回非空字符串时，`1430` 的 `fs.rmSync(tmp, ...)` 先求值参数，访问尚未初始化的 `const tmp`，先抛 ReferenceError，`1431` 原始完整性错误不会执行。该分支不需要旧包存在，首次安装也能触发。对 D-01，旧目录若已删，TDZ 并不会把它恢复。

完整性函数 `220-255` 能在支持的 hash 不符时返回错误；不能说所有 integrity 非标准情况都拒绝：`256-265` 对仅不支持的算法且无 shasum 选择放行。本报告不把 TDZ 夸大成绕过已判失败的校验；它改变失败原因而不是使本分支继续解包。

### 影响收窄

- 确认损失对象是目标 profile 下旧安装目录，不是会话、工作区或整个核心树。包内自带状态若存在也随该目录删除，但本轮未取得插件把重要用户数据存包内的实例，不能据此声称已丢业务数据。
- 已加载 JS 可暂留内存，不保证立即停止；后续懒加载、资源读取、重新挂载或重启可能暴露缺包。启动自愈可能让宿主继续可用，不能称应用必崩。
- 解析失败、同版本可用、未进入 live profile 的隔离安装不属于该直接失败模式。GitHub 的占位名与最终包名不同，其 `1529` 替换也无保旧，但本轮无需据此扩成所有 GitHub 更新必坏。
- 依赖队列 `684-697,1375-1380` 也会换版；解析子依赖失败会跳过，但解析后下载失败没有相同的子依赖 catch，仍可造成已改部分目录后整单失败。此处是放大面，不是另一个已实测事故。

## D-R1：固定名探写

### API 与实际枚举核验

`platform/src/main/ets/system/FilePicker.ets:30` 从 `@kit.CoreFileKit` 导入 `fileIo as fs`。本机 SDK `ets/kits/@kit.CoreFileKit.d.ts:26,34` 把 `@ohos.file.fs` 导出为 fileIo，不是 Node `fs`。

SDK 根：`/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/sdk/default/openharmony/`。`ets/api/@ohos.file.fs.d.ts:147-173` 明文规定：

- `READ_WRITE = 0o2`，读写打开。
- `CREATE = 0o100`，不存在才创建；没有“存在即拒绝”的保证。
- `TRUNC = 0o1000`，已存在且 write-only/read-write 打开时长度清零。
- `2584-2600,2634` 的 openSync 声明明确允许这些 flag 按位或，重复确认 TRUNC 对既存文件清零。
- `3482-3506` 的 unlinkSync 是同步删除文件。

因此实际传入 mode 是 `0o1102`，不是把 Node 的常量数值误套到 HarmonyOS。源码没有独占创建、先验文件是否存在、备份原字节或检查 inode 所有权。

按用户要求尝试了 `devecocli docs search OpenMode TRUNC openSync --limit 6`，因 `better-sqlite3` 本地绑定缺失失败，未得到 documentId。另按 SDK 中 `docroot://reference/apis-core-file-kit/js-apis-file-fs.md#openmode` 线索尝试 `devecocli docs read reference/apis-core-file-kit/js-apis-file-fs`，结果 Document not found；此路径是尝试读取的路径，**不是已检索成功的 documentId**。没有修复工具、安装依赖或伪造在线文档结果。

本结论的系统语义证据来自随工具链 SDK 声明，不是项目注释或泛用 POSIX 经验；在线文档与具体 ROM 实现未核实。

### 破坏链与失败分支

`FilePicker.ets:162` 固定名 `dshm-write-probe.tmp`；`385-398` 拼 `${path}/<固定名>`，按上述 flag 打开、write `'ok'`、close、unlink。open 成功后即把 `created=true`（`394`），这只证明“已打开”，不证明文件由本次新建。

目标原已有可读写普通文件时，按 SDK 契约在 open 就清空旧内容；正常路径继而写成 `'ok'` 并删除。write/close 抛错则 catch 返回 false，finally 在 `414-417` 仍按 created 尝试删除同一路径；unlink 失败也不恢复原内容。即使最后 false 或回落沙箱，先前清零已经发生。open 被拒绝且未修改文件时才没有此链。

路径是系统 URI 转出的父目录，文件名不是用户这次在保存框确认的输出文件名。这里不需要路径注入、恶意文件名或符号链接；一个碰巧/人为创建的同名普通文件就满足名字条件。没有证据显示系统为此名称提供保留字保护，也没有源码全局保留名过滤。工程文本检索 `WRITE_PROBE_NAME|dshm-write-probe.tmp` 的生产命中只有定义与拼接两处。

### 全部已定位生产调用分支

| 入口/调用点 | 触发及限制 |
|---|---|
| `FilePicker.ets:235-346` 的 pickFolder | folder picker 可用并选中目录、路径非空后，非手持且 `granted.persisted=false` 才对**所选目录**探写。`entry/src/main/ets/pages/Index.ets:2748` 调用该入口 |
| entry Web 目录桥 `entry/src/main/ets/pages/WebApp.ets:3541-3555` | 对所选目录同样非手持且 persisted=false 才直接探写 |
| phone Web 目录桥 `phone/src/main/ets/pages/WebApp.ets:3315-3329` | 同结构；正常 PHONE/TABLET 不对任意选中目录直接探写，不能根据 import 就声称普通手机任意目录受影响 |
| 上述三个选目录入口的 handheld 前置 claimed | FilePicker `337`、entry Web `3542`、phone Web `3316` **先 await publicDownloadFolder**；即使持久授权最终为 true，也会先探写应用下载根，而不是任意所选目录 |
| `FilePicker.ets:578-591` 的 publicDownloadFolder | 所有形态，bundleName 非空、path 非空即先探写 `~/Download/<实际包名>`；**不经过 handheld 或 persisted 闸门** |
| 同函数 `617-633,657-663` | 直拼探写未成功后，DOWNLOAD save 若取得有效路径，必要时取父目录，再次探写；有系统权限/URI 返回值依赖，不能假定 save 在每台设备一定成功 |
| `FilePicker.ets:703-725` → `hostruntime/src/main/ets/runtime/NodeRuntime.ets:251-261,365-377` | Host 启动前调用共享下载认领，有 UIAbility context 才执行。成功路径缓存 `FilePicker:704-710,735` 可减少同进程再次认领，但 publicDownloadFolder 其他调用不读该缓存；冷启动模块缓存重置 |
| 手机实际宿主入口 | `phone/src/main/ets/entryability/EntryAbility.ets:932-934,984` 建 NodeRuntime/DshHost 并 start，证明不是只接 entry 的死代码 |
| 目录 fallback/内置浏览器 | FilePicker `240,271,351`；entry Web `3559,3594,4081`；phone Web `3333,3368,3767` 均走 publicDownloadFolder，覆盖选择器不可用、错误以及内置浏览器列根 |

由此推翻“handheld 或 persisted=true 就完全不会探写”的全局主张：它们只短路**所选任意目录的直接探针**，不短路共享下载根的探针。应用下载根路径受包名控制，不能任意指向全盘；用户选中目录的路径受 picker 返回值控制。两类影响面必须分开。

设备判据是 `DeviceFacts.ets:144-165`（raw phone/tablet 为手持，desktop/2in1 或 desktopForced 为桌面），`FilePicker.ets:462-469` 只把 PHONE/TABLET 算 handheld，UNKNOWN 按非手持。`DeviceFacts:102-124` 的 Edge/Pro Max/MateBook/QXS 识别可改变直接所选目录分支，但**不改变 publicDownloadFolder 无形态判断**这一事实。不能把 UNKNOWN 路径直接当成某个已知手机必然走桌面。

### 持久授权、文件能力及全局兜底

- `FolderGrants.ets:173-208` 最终 persisted 来自 checkPersistentPermission 的首个 true；check 超时、异常、空结果或 false 都返回 false。persist 调用成功本身不决定结果，登记失败也不是 persisted=false 的充分条件。故桌面探写不只发生在权限被用户明确拒绝时，check 超时亦可进入。
- `FilePicker.ets:310-311` 的公共目录权限申请结果没有用来阻断探写；不能凭注释说“权限不足所以一定打不开”，也不能凭 manifest 权限说“一定能打开”。持久授权与本次可写是不同谓词，本轮没有设备权限状态证据。
- `FolderGrants.ets:220-247` 恢复的是 URI 授权，不是文件原字节。`FilePicker:401-419` 的 catch/finally、`703-725` 的上层 catch 和 fallback 只处理可用性，不保留既存探针文件。
- 检查了 fs-local 的原子写机制（实际核心 `dsh-fs-local/lib/index.js:522-618`）；它属于 Node 文件服务，不能拦截这里 ArkTS fileIo 直调。即使其原子写保留/发布策略正确，也不能给本探针补事务保护。
- 核验 Node 侧全局 fs 包装：`hostcore/app/main.js:1390-1419` 只计时并透传；`hostcore/app/fs-probe-cache.cjs:405-410,529-535` 写前清负缓存再调原操作。两者既不备份，也不包围 ArkTS API。
- 未发现会把此固定名预存文件自动备份/还原的全局保护。系统备份、云空间或文件管理器回收站是否能事后恢复不在本轮可证范围，不能当自动回滚，也不能声称绝对无法通过任何外部手段恢复。

影响限于探针路径对应文件。不能从这里推导任意文件批量删除、整个目录清空、符号链接任意目标破坏或每次选目录都损坏。共享下载根中必须已经存在准确同名文件且本次操作获准；无同名文件时正常创建/删除临时文件，不构成本次候选的既存数据损失。

## 随包真实性

- 配方 `hostcore/core-recipe.json:3,15` 指向 `0.2.2-rc.2+dshm.1` 与 ondevice。
- `hostruntime/src/main/ets/runtime/NodeRuntime.ets:224` 实际入口是 HSP `resourceDir/resources/app/main.js`，不是从 core zip 假设存在 app 安装器。
- 对源码与随资源副本作只读 SHA-256 比较：`hostcore/app/dshm-installer.js` 与 `hostruntime/src/main/resources/resfile/resources/app/dshm-installer.js` 均为 `6ec712788e96e99628f9a9638f96407838ebc3306ac87e35a77a379876e8199a`；两个 main.js 均为 `4f76b5db1e62e8b892a5baea4281871a8772a448383bd75a1e2241781234c287`。因此 installer/main 引用可直接对应随资源副本相同行。
- 只读内存打开 `hostruntime/src/main/resources/resfile/dsh-core-0.2.2-rc.2+dshm.1-openharmony-arm64.zip`，未解压落盘。其 `dsh-core-0.2.2-rc.2+dshm.1/` 下 manager 的 `lib/index.js`、`lib/types/operations.js`、两桥 `lib/index.js`、`profiles/ondevice/package.json` 与当前 work 树逐字节相同。相关 manager/桥/种子引用不是仅依赖工作树推测。
- zip 中 manager `package.json` 的 main/default 导出为 `lib/index.js`；ondevice 种子 `package.json:6-16` 的 dependencies 空、bundles 为核心 dsh-base/dsh-web-app，patchReload=startup。它不是保存任意用户旧版本安装内容的种子备份。
- 未读取已签名 app/hap 中 abc，也未验证设备当前激活版本。随包 resfile 与 zip 的证据上限不是“已安装设备逐字一致”。

## 安全复现结果

仅执行 `node -e` 的自包含内存代码，无 fs、网络、生产 import、定时器、进程配置修改或文件写入。

```text
memory-order-model {"ok":false,"error":"download failed","oldPresent":false,"profile":"1.0.0"}
actual-JS-TDZ-model {"ok":false,"error":"Cannot access 'tmp' before initialization","oldPresent":false,"profile":"1.0.0"}
SDK-contract-memory-model {"preexistingPresent":false,"actualSystemAPI":false}
```

第一项用对象 `old` 模拟安装目录，先 delete 再抛下载错误；第二项在相同 try 块内先 `void tmp` 再 `const tmp`，实际执行 JavaScript TDZ。第三项用 Map 模拟 SDK 的清零/写入/删除契约。模型只能解释与核对因果及语言行为，**不能算生产安装器或真实系统 API 的最小复现**。未为取得复现而接触真实用户文件。

## 搜索覆盖与剩余缺口

全工程相关符号/引用搜索覆盖 `installSpec`、`dshm-installer`、`install-queue`、`prefetch`、`backup/rollback/restore`、`probePathWritable`、`publicDownloadFolder`、`claimPublicDownloadFolder`、`pickFolder`、固定探针名、设备形态与 fileIo SDK 关联。沿生产入口读取了队列解析/执行/结果、两桥、实际 manager 安装/更新/恢复、profile 自愈、救援恢复、两端目录桥与默认工作区、宿主启动认领，以及相关随包字节。测试脚本的搜索命中未当运行证据，也未执行会落盘的门禁。

这不是逐字全仓已读的声明。尚未确认：设备上外装社区市场的具体版本与 prefetch 提交算法；实际 ROM 的公共目录 path/URI 授权与 fileIo 错误时副作用；真实已装旧插件与新包故障样本；HMR 当前动态服务是否存在；已部署 abc/设备激活核心与仓库资源是否一致。上述缺口不能反证直接队列的删除顺序，也不能以“没运行过”把 SDK 明文定义的 TRUNC 误说成独占创建；同样不能拿静态闭环冒充已发生事故。
