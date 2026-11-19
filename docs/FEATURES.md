# 功能台账（Feature Ledger）

> **这是本项目防「修好这个、坏了那个」的核心文档。**
> 每一条在版功能都必须能回答三件事：**实现在哪、契约是什么、哪道门禁守着它**。
> 改功能 / 改实现 / 新增功能时，**同一次改动内**更新本表；门禁红了先查对应行。
>
> 事实优先级：代码与设备 > 门禁与 `dist/acceptance/` > 本表 > 历史归档。
> 本表不抄版本号；版本以 `AppScope/app.json5` 与 `hostcore/core-recipe.json` 为准。

---

## 0. 怎么用这张表

1. **动手前**：按功能域找到目标行，看「实现位置」与「门禁」，先跑一次相关门禁做基线。
2. **动手后**：跑同一批门禁；任何 ok→fail 当场修，不许延后。
3. **改契约**（桥方法、权限、模块设备面、页面选择器、配置键）：必须同时改门禁与本表，
   否则视为破坏契约。新增门禁必须带 `--self-test` 变异体。
4. **新功能**：先在本表登记一行，再写代码；没有门禁的，至少给出可执行的验收判据。

---

## 1. 当前在版功能（1.1.8 / 1010018）

### 1.1 启动、核心与宿主

| 功能 | 形态 | 实现位置 | 契约 / 判据 | 门禁 |
|---|---|---|---|---|
| 核心树随包安装、升级与回滚 | 三端 | `hostruntime/src/main/ets/core/BundledCore.ets`、`hostruntime/src/main/ets/core/CoreStore.ets`、`hostcore/app/boot-seed.cjs` | resfile 只允许 1 份容器；sha 与 `hostcore/core-recipe.json` 一致；覆盖安装保数据 | `check-bundled-core-rollback`、`assert-resfile-sync` |
| 宿主 Node 运行时（`--jitless`） | 三端 | `hostruntime/src/main/ets/runtime/NodeRuntime.ets`、`hostcore/app/jitless-env.cjs` | 不申请 JIT；`WebAssembly === undefined` 属预期 | `check-worker-jitless`、`check-node-runtime-startup` |
| libnode `io_uring` 中性化 | 三端 | `tools/patch-libnode-io-uring.mjs` | syscall 槽位中性化后再签名 | `check-libnode-io-uring` |
| `bin/dsh` 按当前核心选版本 | 三端 | 核心树 `bin/dsh`（随包） | 路径从脚本自身推导；禁止写死版本号 | `check-dsh-cli-current-core` |
| 启动编排与就绪探测 | 三端 | `hostcore/app/startup-work.cjs`、`hostcore/app/main.js` | 端口 / 就绪文件探测；宿主慢启动不得误判「核心不可连」 | `check-startup-work`、`check-ws-self-heal` |
| 更新事务 / 安装单飞 | 三端 | `hostcore/app/dshm-update-transaction.cjs` | 失败可恢复；并发安装只跑一份 | `check-bundled-install-singleflight`、`check-installer-integrity` |
| 单宿主 / 端口隔离 | PC/2in1 | `hostruntime/src/main/ets/runtime/DshHost.ets` | 一个宿主进程一套端口；跨模块不得重复起 | `check-host-port-isolation`、`check-host-module-singleflight` |
| 内存守卫与生命周期 | 三端 | `platform/src/main/ets/notify/NotificationCenter.ets`、`hostcore/app/main.js` | 资源按代次回收；退出不泄漏 | `check-memory-guard`、`check-memory-host-lifecycle` |
| 启动救援插件 | 三端 | `hostcore/plugins/dshm-boot-rescue` | 内置与外部同名插件解耦，只跑一套 | `check-boot-rescue`、`check-boot-rescue-id` |
| 用户数据保全 | 三端 | `hostcore/app/dshm-user-rows.js` | 升级 / 覆盖安装不得删 `el2` 数据 | `check-user-data-preserved` |

### 1.2 三端壳与布局

| 功能 | 形态 | 实现位置 | 契约 / 判据 | 门禁 |
|---|---|---|---|---|
| 设备分档（desktop / tablet / phone / foldable） | 三端 | `platform/src/main/ets/system/DeviceFacts.ets` | `EDGE_FAMILY_TOKENS` 只含 `QXS`；`MRX/MRR/MRD/MRO/DRA` 不得加回 | `check-edge-desktop-policy` |
| PC 顶栏 / 三键 / 托盘 | PC/2in1 | `entry/src/main/ets/system/StatusBarTray.ets`、`entry/src/main/ets/pages/WebApp.ets` | 关闭收进后台；三键跟随主题 | `check-decor-button-mode` |
| 平板侧栏几何（展开 280 / 收起 56） | 平板 | `entry/src/main/ets/pages/WebApp.ets` | 写死几何只在 `min-width:1024px` 生效；窄档交官方抽屉 | `check-sidebar-shim-css`、`check-phone-sidebar-core-compat` |
| 手机抽屉 + 单颗 ⊞ | 手机 | `phone/src/main/ets/pages/WebApp.ets` | 只一颗官方入口；窄视口不挤压主区 | `check-phone-viewport-grid`、`check-mobile-enter` |
| 折叠屏单屏 / 多屏 | 折叠 | `entry/src/main/ets/pages/WebApp.ets`、`phone/src/main/ets/pages/WebApp.ets` | 单屏走手机抽屉；多屏跟平板 | `check-foldable-sidebar`、`check-dual-shell-parity` |
| 设置面板官方排除 | 三端 | `entry/src/main/ets/pages/WebApp.ets`、`phone/src/main/ets/pages/WebApp.ets` | 设置面板及内部 dialog 全形态排除玻璃 | `check-pc-settings-chrome` |
| 沉浸光感材质 | PC/平板 | `entry/src/main/ets/pages/WebApp.ets` | `systemMaterial` / `uiMaterial`；API < 26 守卫 | `check-web-glass-skin` |
| 网页右键 / 长按菜单接管 | PC/平板 | `entry/src/main/ets/pages/WebApp.ets`（`handleWebContextMenuShow`） | 语境判定 + 动作映射（链接/图片/输入框/纯选区）；任何异常一律回退系统默认菜单 | `check-web-glass-skin`（材质一致）+ 真机判据四类 |
| 自由窗口装饰 | PC/2in1 | `entry/src/main/ets/entryability/EntryAbility.ets` | 系统装饰 + 可拖拽 | `check-free-window-decor` |
| 手持返回键分层消费 | 手机/平板 | `phone/src/main/ets/pages/WebApp.ets` | 先关弹层，再退页面 | `check-handheld-back` |
| 双壳一致性 | 平板/手机 | 两壳同构点 | 共享逻辑改动必须两壳同步 | `check-dual-shell-parity` |

### 1.3 终端与执行环境

| 功能 | 形态 | 实现位置 | 契约 / 判据 | 门禁 |
|---|---|---|---|---|
| PC 原生终端（PTY） | PC/2in1/Edge/ProMax | `entry/src/main/cpp/`、核心树 PTY 插件 | 仅 desktop 档注册；sh/zsh/bash 三模式 | `check-bash-terminfo`、`check-edge-desktop-policy` |
| guest VM 终端 | 平板/手机 | `hostcore/plugins/dshm-vm-bash` | 一进程一 VM；按需冷启动 | `check-vm-bash`、`check-host-vm-graceful-stop` |
| 终端会话生命周期 | 三端 | `hostcore/plugins/dshm-vm-bash/lib/index.js` | 句柄与代次回收；退出不留孤儿 | `check-guest-terminal-lifecycle`、`check-guest-handle-lifecycle` |
| VM 资源档（2 vCPU / 内存分档） | 平板/手机 | `hostcore/plugins/dshm-vm-bash/lib/vm.js` | 2 vCPU；guest 内存经济档 512 / 性能档 1024 MiB；TCG 128 / 512 MiB；启动地板不变 | `check-vm-memory-tier`、`check-vm-bash` |
| 工具链落位（busybox / python / git / tmux / gh） | 三端 | `tools/place-toolchain.mjs` | 闭包完整、SONAME 软链齐全 | `assert-exec-fix`、`assert-python-bridge` |
| CLI 垫片语义 | 三端 | `tools/assert-cli-shim.mjs` | 假壳必须显式拒绝，不得静默成功 | `check-cli-shim-semantics` |
| 输出背压 / 取消 | 三端 | 核心树 subprocess 层 | 长输出不撑爆内存；取消可回收 | `check-node-output-bounds` |

### 1.4 文件、工作区与权限

| 功能 | 形态 | 实现位置 | 契约 / 判据 | 门禁 |
|---|---|---|---|---|
| 文件访问栅栏（沙箱 ∪ 用户目录） | 三端 | 核心树 `dshm-fs-fence`、`hostcore/app/fs-probe-cache.cjs` | 读写都掐；三入口同一判据 | `check-fs-fence`、`check-fs-local-permission`、`check-fs-probe-cache` |
| 目录授权持久化 | 平板/手机 | `platform/src/main/ets/system/FilePicker.ets` | picker 授权只活一个进程 ⇒ 必须持久化并跨启动恢复 | `check-folder-grants-startup`、`check-picker-api23` |
| 工作区认领 | PC/平板 | `hostcore/plugins/dshm-workspace-claim` | 默认工作区登记不得自建 | `check-workspace-claim` |
| 文件预览与读字节 | 三端 | `entry/src/main/ets/view/FilePreviewPane.ets` | 空响应必须报错而非白屏 | `check-file-location` |
| 权限面 entry 18 / phone 9 | 三端 | `entry/`、`phone/src/main/module.json5` | 条数 + 顺序 + reason 逐位钉死；ACL 以发布 Profile 为准 | `check-permission-surface`（含 `--self-test`） |
| 0 APK 面 | 三端 | 全仓 | 不得出现 apk 文件 / 目录 / 随包条目 | `check-no-apk-surface` |
| AI 生成标识 | 三端 | `entry/src/main/ets/pages/WebApp.ets`、`phone/src/main/ets/pages/WebApp.ets` | 只挂会话正文，离开会话页即移除 | `check-ai-disclosure-scope` |
| 品牌面 / 身份 | 三端 | `AppScope/`、各模块资源 | 正式身份不得残留 beta 字符串 | `check-brand-surface` |

### 1.5 插件、市场与技能

| 功能 | 形态 | 实现位置 | 契约 / 判据 | 门禁 |
|---|---|---|---|---|
| 插件安装 / 卸载 | 三端 | `hostcore/app/dshm-installer.js`、`hostcore/app/dshm-install-command.js` | manifest 与模块格式校验；失败可回滚 | `check-plugin-manifest`、`check-plugin-module-format` |
| 插件市场桥 / 皮肤安装 | 三端 | `hostcore/plugins/dshm-market-bridge` | 装完重放挂载契约；面板宽度不越界 | `check-market-bridge`、`check-market-panel-width` |
| profile pnpm 桥 | 三端 | `hostcore/plugins/dshm-profile-pnpm` | `requestedFields` / `isVersionList` 契约 | `check-profile-pnpm-bridge` |
| 技能单源同步 | 三端 | `hostcore/app/dshm-skills.js` | 技能文档单源在 HSP，运行时 `resRoot/ohos-skills` | `check-skill-single-source`、`check-skill-sync` |
| 插件渲染 / 桥面 | 三端 | `entry/src/main/ets/pages/WebApp.ets`、`phone/src/main/ets/pages/WebApp.ets`、`dshcompat/` | 桥方法必须登记，未登记不得暴露 | `check-bridge-contract`、`check-bridge-surface`、`check-bridge-methodlist` |
| 插件补丁校验 | 三端 | `hostcore/app/dshm-compat.js` | 上游补丁锚点存在，缺锚点显式告警 | `check-core-openharmony-patches` |
| 内置成品插件 | 三端 | `hostcore/plugins/*` | 11 个自带插件随包，不得删 | `check-plugin-render-arity` |

### 1.6 云同步与数据

| 功能 | 形态 | 实现位置 | 契约 / 判据 | 门禁 |
|---|---|---|---|---|
| 云同步策略 / 开关 | 三端 | `hostcore/plugins/dshm-cloud-sync` | 以系统「云空间」开关与账号为前提；无会员也要给出准确文案 | `check-cloud-sync-policy` |
| 同步模型 / 计划 | 三端 | `platform/src/main/ets/sync/SyncEngine.ets` | 设备 + 日期维度；去重主键固定 | `check-sync-model`、`check-sync-planner` |
| 会话同步范围 | 三端 | `platform/src/main/ets/system/SessionSyncScope.ets` | 只同步声明范围内的表 | `check-session-sync-scope` |
| 导入 / 恢复 | 三端 | `platform/src/main/ets/sync/ImportRunner.ets` | 双向进度；重复导入不产生副本 | `check-sync-model` |
| 云空间 AGC 配置 | 服务端 | `metadata/` | 容器 `DSHM` / 类型 `sync_units` 与端侧 DDL 逐字一致 | 人工 + `check-cloud-sync-policy` |

### 1.7 分享、链接与互操作

| 功能 | 形态 | 实现位置 | 契约 / 判据 | 门禁 |
|---|---|---|---|---|
| 碰一碰收文件 | PC 档 | `entry/src/main/ets/system/KnockShareReceiver.ets`、`entry/src/main/ets/pages/WebApp.ets` | 一窗一实例；`general.object + general.file`；页面销毁只 detach；只注入不自动发送 | `check-knock-share-wiring`（含 7 变异自检） |
| 外链打开 | 三端 | `entry/src/main/ets/system/OpenLinkBridge.ets` | 只接管 http(s)；宿主与外壳同一判据 | `check-open-link-bridge` |
| 内置浏览器 | 三端 | `hostcore/plugins/dshm-tool-browser` | 工具调用结束自动关闭；截图通道可用 | `check-browser-autoclose`、`check-browser-screenshot` |
| 快捷方式 / 意图 | 手机 | `phone/src/main/ets/insightintents/StartNewSessionImpl.ets` | 入口指向正确模块 | `check-mobile-enter` |

### 1.8 语音、通知与卡片

| 功能 | 形态 | 实现位置 | 契约 / 判据 | 门禁 |
|---|---|---|---|---|
| 系统语音识别 | 三端 | `entry/src/main/ets/speech/SystemSpeechRecognizer.ets`、`phone/src/main/ets/speech/SystemSpeechRecognizer.ets` | 走系统 Core Speech Kit；权限先实现后声明 | `check-native-capture-lifecycle`、`assert-speech-syntax` |
| 完成提示音 | 三端 | `entry/src/main/ets/entryability/EntryAbility.ets`、`phone/src/main/ets/entryability/EntryAbility.ets`、`platform/src/main/ets/notify/NotificationCenter.ets` | 只在一轮真正结束时播 | `check-done-sound-system` |
| 任务通知 | 三端 | `platform/src/main/ets/notify/NotificationCenter.ets` | 按会话分组；点击直达会话 | `check-done-sound-system`（通知链同源） |
| 长时任务保活 | 三端 | `platform/src/main/ets/` 保活层、`hostcore/app/main.js` | 熄屏续期；活跃判据看真实在途事实 | `check-keepalive-wiring`、`check-workload-refs` |
| 服务卡片 / 用量 | PC/平板 | `entry/src/main/ets/form/UsageFormAbility.ets`、`entry/src/main/ets/form/pages/UsageCard.ets` | 卡片状态与 `workload` 一致 | `check-usage-card` |
| 思考过程翻译 | 三端 | `hostcore/plugins/` + 设置项 | 默认关；开关可回滚 | `check-cot-translation`、`check-cot-translation-live` |

### 1.9 构建、发布与门禁

| 功能 | 形态 | 实现位置 | 契约 / 判据 | 门禁 |
|---|---|---|---|---|
| Beta 包 | 三端 | `tools/build-beta.mjs` | 临时 beta 身份；`finally` 逐字还原；权限面不变 | `check-beta-build-entry` |
| AGC 包 | 三端 | `tools/build-agc.mjs` | release 签名；Profile `allowed-acls` 自验；不可侧载 | `check-agc-wiring` |
| 核心容器 | 三端 | `tools/pack-core.mjs` | `--place-in-app`；resfile 只 1 份 | `check-resfile-core-zip`、`assert-resfile-sync` |
| 发布产物一致性 | 三端 | `dist/release-test/`、`dist/beta/` | `.app` + `.sha256` + `SHA256SUMS.txt` 一致 | `check-bundled-core-rollback` |
| 文档与引用 | 仓库 | `docs/`、`tools/check-doc-*.mjs` | 编号文档全收录；行号引用不漂移 | `check-doc-index`、`check-doc-refs` |
| 死代码 / 接线 | 仓库 | `tools/check-dead-code.mjs`、`tools/check-feature-wiring.mjs` | 新能力必须被接线与登记 | `check-dead-code`、`check-feature-wiring` |
| 功能对等矩阵 | 仓库 | `docs/parity-matrix.md` | 39 个官方能力面全覆盖，非 DONE 必须登记缺口 | `check-parity` |

---

## 2. 历史里程碑（1.1.0 → 1.1.8）

> 这里只记「哪一版交付了什么」。细节与当时的读数在 `docs/archive/` 对应文档里，**不作为现行口径**。

| 版本 | 里程碑 | 详见（归档） |
|---|---|---|
| 1.1.0 | 侧边栏文件预览、终端接入、插件与 Node 诊断、PTC 运行能力、端侧核心升级 | `docs/archive/100-v1.1.0发布说明…md` |
| 1.1.3 | 正式版同步（beta → 正式身份）、AGC 包、APMS 问题查询接入 | `docs/archive/171-*`、`180-*` |
| 1.1.4 | API 26 可落地清单、内测三包、MatePad Edge 永久 desktop | `docs/archive/190-*`、`202-*`、`207-*` |
| 1.1.5 | AGC 邀请测试包与一致性复核 | `docs/archive/229-*` |
| 1.1.6 | 平板侧栏常驻、手机 bash 路径修复、多 HAP 结构改造、内存收口、升级数据迁移 | `docs/archive/236-*`、`239-*`、`240-*`、`243-*`、`265-*` |
| 1.1.7 | 长时任务熄屏续期、快捷方式模块修正、AGC 邀请测试候选 | `docs/archive/326-*`、`334-*`、`340-*`、`341-*` |
| 1.1.8 | 启动并行化、guest pnpm 修复、通知与轮次状态收敛、2in1 终端 bash 修复、全盘权限落地、救援插件解耦、AI 标识收敛、碰一碰、沉浸材质、设置面板排除、侧栏竖屏闸 | `docs/archive/399-*`、`408-*`、`419-*`、`420-*`、`421-*`、`422-*` |

---

## 3. 维护规则

1. **一功能一行**；同一功能的多处实现写在同一行，用逗号分隔。
2. 「实现位置」必须是**真实路径**（`file:line` 不用写，避免漂移）；路径变了同一次改。
3. 「门禁」必须是 `tools/check-*.mjs` / `assert-*.mjs` 里真实存在的脚本名；
   没有门禁的功能，判据列必须写成可执行的验收步骤。
4. 功能下线：行不删，状态改「已下线」并注明日期与原因；对应门禁同步删除或改钉。
5. 每版出包前复核本表：新增功能是否入表、门禁是否覆盖、归档链接是否仍有效。
