# 270 · 「关于」菜单项与开源组件声明（顶栏入口 · 逐条清单 · Beta 重编）

> ⚠️ **历史读数**：文中「1 个 ohpm 依赖（sherpa-onnx）」已失效；`sherpa_onnx` 已移除，当前 ohpm 依赖为 0（`tools/gen-oss-notices.mjs` 的 `OHPM_COMPONENTS = []`）。

> 📌 **后续形态（2026-11-11）**：本页描述的「单页四节」已被两次用户裁决改写 ——
> ①`关于` 从「应用」菜单独立出来，含「版本信息 / 开源组件声明」两个子项；
> ② 两个子项**各自单页**，面板内不再并列页签（`AboutPanel.ets` 的 `initialTab` 只读）；
> ③ 两个入口用**同一套容器**：`92% × 72%`、最宽 `560vp`，内容靠左上（版本页下方留白）；
> ④ 面板底 = `#F7FFFFFF` + `backdropBlur(12)`（固定浅色，1px 白描边压暗边）。**不用**
> `backgroundBlurStyle` 也不用 `sys.color.*` —— 本应用 `setColorMode(COLOR_MODE_NOT_SET)`
> 跟随系统，深色系统下两者都会把面板染成深灰（用户两次反馈的"黑黑的"）。
> ⑤ 内容用 `Scroll.align(Alignment.TopStart)` 强制左上对齐（Scroll 默认 Center，
> 内容短时会垂直居中）。
> ⑥ 顶栏再收口（同日最终裁决）：「应用」菜单（主页 / 刷新）连同实现**整体删除**，
> 顶栏只剩一颗**三点菜单**（`DotsMenu`，三个 3vp 实心圆点，间距 2.5vp、盒高 22vp），
> 点击弹出「版本信息 / 开源组件声明」。圆点取顶栏前景色跟随外观，hover 垫与官方图标
> 按钮同值。
> ⑦ 同日再调：面板外那层"点空白关闭"的遮罩由 30% 黑改为 **全透明** —— 呼出面板时
> Web 背景不再被压暗（用户要求"背景不要做其他的变化"），`backdropBlur(12)` 也因此不再
> 吸到黑色，圆角暗角从根上消失。
> ⑧ 侧栏入口收口（同日）：**自绘浮动 ⊞ 整体删除**（`ensureFab` / `syncFab` / `#dshm-sidebar-fab`
> / `HANDHELD_FAB_*` 常量与设置面板的顶部让位一并移除）。收起态（56px 图标轨）改为把
> **dsh 官方 `button[data-sidebar-opener]` 强制常显**（只抬 opacity / visibility /
> pointer-events，不动 display），面板与右侧栏打开时临时隐去。全链路只剩官方一颗按钮。
> ⑨ 官方 rail 的图标交换（同日，读随包核心 `dsh-client-ui-sidebar@0.2.2-rc.1` 确认）：
> `.…_collapsed .…_toggle` 收起态显示的是**品牌标 railMark**，侧栏图标 `panelIcon` 被
> `display:none`、只在 `:hover` 时交换出来 —— 用户看到"按钮没了、鼠标碰到才出现"。
> 现固化交换结果：收起态 `panelIcon{display:inline !important}` + `railMark{display:none !important}`。
> 同时 `syncOpener()` 每拍判断轨内 toggle 是否真的可用，可用就写
> `data-dshm-rail-opener="1"`，把 frame leading 座位里重复的 `[data-sidebar-opener]`
> 收掉 —— 平板档的"两颗按钮"由此消失。
> ⑩ 「内容由 AI 生成」标识的范围收口（同日，三端同步）：只在**会话区的输入框卡片**上显；
> 离开会话（设置 / 插件详情 / 文件预览 / 空白新页）一律不显。前两版走的是"每拍找最宽的
> 输入框 → fixed 定位"，仍然会被设置页 / 插件详情里的 textarea 命中（用户截图复报）。
> 最终改为**真嵌**：不再猜"当前是不是会话页"，而是把标识节点 `appendChild` 进官方会话
> 输入座位 `[class*="composerSeat"]`（CSS Modules 后缀匹配，实际类名 `wSkVaW_composerSeat`），
> 用 `position:absolute` 相对座位摆到卡片工具栏那一行的空白带。
> 座位只由会话页渲染 —— 切页时它整个卸载，标识随之消失；另外 `suppressed()` 仍保留
> 「面板打开 / 任何 ≥90% 视口的 dialog 或 data-shortcut-modal」作为双保险。
> 若 React 重渲染把外来子节点清掉，下一拍（≤1s）会自动补挂。
> ⑪ 状态栏通知的两处修复（同日，三端同步）：
> **① 点击直达会话** —— 能力层一直把 `want.parameters.dshRoute` 解成 `dshLaunchRouteJson`，
> 但 entry / phone 的 Web 壳**都没人读这个键** ⇒ 点通知只是把应用拉到前台。
> 现在两壳都加 `@StorageProp('dshLaunchRouteJson') @Watch(...)` + `aboutToAppear` / `onPageShow`
> 三层消费（消费即清空、`parseNotifyRoute` 白名单 fail-closed），解析出 `sessionId` 后走既有的
> `dispatchWebAction('open-session')` 注入链路（与桌面卡片直达会话同一实现；页面未就绪自动挂起、`onPageEnd` 补发）。
> 另外 `publishCompletion` / `publishProgress` 原先构造的 draft **没有 route** ⇒ `buildAgent` 返回
> undefined、通知根本没有 WantAgent；现改为读 `task-state.json` 的 `sessionId`（Host 端本来就在写）
> 并拼 `{page:'sessions', sessionId}` 路由。
> **② 通知栏分组** —— `groupOf()` 原先只返回 `'待决'` / `'进展'` 两个常量，`groupName` 相同即被系统
> 折叠 ⇒ **所有会话的通知挤成一条**。现改为按会话分组 `dsh.session.<sessionId>`：同会话的多条
> （进度 / 完成 / 待决）折叠为一组，不同会话各自一条；拿不到 sessionId 时返回空串，
> `publish()` 见空串不设 `groupName`（设空串会让它们又聚成一组）。
> ⑫ 侧栏按钮去重收口（同日，用户报"手机小窗里左上角两个按钮"）：
> 真因是两条渲染路径同时可见 —— 图标轨顶部 `_toggle`（收起态强制常显后）与 frame
> leading 座位里的 `[data-sidebar-opener]`。修法不是再藏一颗，而是**每拍实测**：
> `syncOpener()` 用 `document.elementFromPoint()` 判断轨内那颗**真的点得到**（`getBoundingClientRect`
> 不扣祖先的 `overflow` 裁剪，0 宽列 / 抽屉出屏时仍返回正宽高，只用它会把唯一入口一起藏掉），
> 可用才写 `data-dshm-rail-opener="1"` 收掉 leading 那颗；不可用则保持 0、让 leading 那颗兜底。
> 判据顺序与 `findToggle()` 一致（先 `aria-label` 文案、再 `_toggle` 后缀），避免命中设置页的开关。
> 同时全仓清理：两壳死常量 `INSERT_TEXT_JS`（1.5KB，零调用）、entry 里描述"桌面档隐藏官方按钮"
> 的失效注释块（§E 已于此前撤销），以及三处门禁里对 `FAB_ID` / 自绘 ⊞ 的旧断言与变异体。
> ⑬ 移动端回车（同日，用户裁决"换行就是换行，发送是 dsh 的按钮"）：官方
> `dsh-client-ui-conversation` 的 KEY_ENTER 处理器把**裸 Enter** 直接 `handlers.submit()`，
> 而手机 / 平板软键盘的换行键发的正是裸 Enter ⇒ 想换行却把消息发了出去。
> 新增 `MOBILE_ENTER_SHIM_JS`（两壳同源、document-start 注入）：捕获阶段把裸 Enter 转成
> 官方自己的 **Shift+Enter** 语义 —— `preventDefault + stopImmediatePropagation` 拦死原事件，
> 再向同一目标补发 `shiftKey:true` 的 keydown；官方处理器见到 shiftKey 立刻 `return false`，
> 由 Lexical 内置 KEY_ENTER 命令插入换行（不伪造 DOM、不 execCommand、不碰发送按钮）。
> 五条边界：① 只在 `html.dshm-handheld` 生效（PC / 2in1 保持 Enter 发送）；
> ② 输入法组字中（`isComposing` / keyCode 229）不拦；③ 带任何修饰键不拦（Ctrl+Enter 发送照旧）；
> ④ 命令菜单 / @ 引用 / 斜杠菜单 / 工作区菜单等任何可见弹层在场时不拦（Enter 仍是"选中"）；
> ⑤ 只认 `[data-composer-seat]` 内的 `[data-lexical-editor="true"]`，设置搜索框 / 插件表单 /
> 终端输入一律不碰。发送仍走输入框右侧那颗官方按钮。
> 本页其余内容（生成器判据、逐条清单口径、Beta 重编记录）仍然有效。

> 日期：2026-10-28 ｜ 状态：**已落地**（含 Beta 包重编与交付）
>
> 起因（用户口径）：把应用里的「关于版本」与「开源许可与版权」剥离出来，**顶栏新建一个
> 「关于」菜单项显示这两项内容**；开源声明采用给定规范格式：
> ① 逐条列出**所有**第三方开源库名称与许可证；② 提供 GPL 系列等所需源码地址与版权信息；
> ③ 技术支持（问题反馈 / 官方文档）。
>
> 上游口径：上架规范强调"列全、列对"，漏项或不写会被驳回。

---

## 1. 改了什么

| 面 | 改动 |
|---|---|
| 菜单 | 顶栏「DSHM」菜单里的「开源许可与版权」「关于版本」两项**剥离**，合并为一个 **「关于」**（位置：主页 / 刷新 / **关于** / 会议模式） |
| 新面板 | `entry/src/main/ets/view/AboutPanel.ets` —— 浮层四节：**版本信息** / **开源组件声明** / **源码与版权信息** / **技术支持** |
| 数据 | `entry/src/main/resources/rawfile/licenses/OSS-NOTICES.json`（结构化，面板读它）+ `OSS-NOTICES.txt`（同内容的纯文本，便于外部核对） |
| 生成器 | `tools/gen-oss-notices.mjs` —— 从**实际随包内容**生成清单，并带**完整性强校验** |
| 旧文件 | `rawfile/licenses/LICENSES.txt` 里那段模糊的 "Bundled third-party components"（只写"相关组件包括…"）替换为**指向逐条清单**的说明；MIT 全文与商标声明原样保留 |

**为什么必须程序化生成**：上一次那份文本既没列名字也没列许可证，还把 PC 工程早已移除的
组件写成"相关组件"。手抄清单必然漂移，而上架规范要的是"列全、列对"。

---

## 2. 生成器的判据（`tools/gen-oss-notices.mjs`）

| 来源 | 判据 |
|---|---|
| 核心树 npm 依赖 | 遍历 `dist/core/work/dsh-core-<ver>/node_modules`，**只取包根**（`isPackageRoot`），记 `name/version/license` |
| ohpm 依赖 | 逐条登记并**验其 LICENSE 文件存在**（当前只有 `sherpa-onnx@1.13.3`，Apache-2.0，已实读其 LICENSE 首行确认） |
| 随包运行时/工具/VM 件 | 每条都带 `evidence` 路径，**验存在才登记** —— 例如将来真的移除了 VM，QEMU/Slirp/内核那几条会自己消失，而不是继续宣称有 |
| 随包原生库 | `hostruntime/libs/arm64-v8a/` **并集** 已出 `.app` 里 `hostruntime-default.hsp` 的 `libs/arm64-v8a/`（后者含构建期由 SDK 复制进去的库，如 `libc++_shared.so`）——**只看源码目录会漏**；并集里任何一个未登记即**判失败**（exit 2） |
| Alpine guest 包 | 从 `resfile/vm/guestpkgs/*.tar.gz` 文件名解析包名+版本，逐条映射许可证 |

**完整性强校验当场生效过**：第一次运行就抓出 `libsharpyuv` / `libwebp` / `libwebpdemux` /
`libwebpmux` 四个我漏登记的随包库 ⇒ 补登记后才允许出包。这正是这道闸门存在的意义。

`--check` 模式用于回归：核心升级或换随包件后忘了重跑生成器 ⇒ 判红。

---

## 3. 本次生成的清单读数（核心 `0.2.1-rc.4+dshm.97`）

| 项 | 数量 |
|---|---|
| 核心树 npm 依赖 | **624 个包**（12 种许可证） |
| 许可证分布 | MIT 最多，其后 Apache-2.0、BSD-3-Clause、ISC、BSD-2-Clause、MPL-2.0、LGPL-3.0-or-later、Python-2.0、Unlicense 等 |
| ohpm 依赖 | **1 个**（sherpa-onnx，Apache-2.0） |
| 随包运行时与工具 | **10 项**：Node.js(MIT)、CPython 3.12(PSF-2.0)、Git(GPL-2.0)、FFmpeg 9.0.1(GPL-2.0-or-later，随包附 LGPL 文本)、BusyBox(GPL-2.0)、QEMU(GPL-2.0)、HiSH 运行件(MIT / Copyright (c) 2025 hackeris)、Linux kernel 6.12.60(GPL-2.0)、Alpine rootfs 3.22、efi-virtio.rom(GPL-2.0) |
| 随包原生共享库 | **53 个第三方** + 5 个自有件（自有件不计入第三方：`libdshhost.so` 等） |
| 需给源码地址的条目 | **32 条**（GPL/LGPL/MPL 系列，逐条列上游地址） |
| 文本规模 | `OSS-NOTICES.txt` 748 行 / `OSS-NOTICES.json` 83,151 B |

---

## 4. 与用户给定规范的对应

| 规范要求 | 落实 |
|---|---|
| 必须列出所有第三方开源库名称 | 624 npm + 53 原生库 + 10 运行时/工具 + 1 ohpm，全部逐条列出 |
| 每个库对应许可证类型 | 每条都是 `名称 - 许可证`；并给出核心树 npm 的**许可证分布**汇总 |
| 建议格式「库名称 - 许可证版本」 | 面板与 TXT 都是编号列表 `1. <名称> <版本> - <许可证>` |
| 无开源组件时的写法 | 清单末尾明确写「以上为随包全部第三方开源组件；**本应用未使用上述清单之外的第三方开源库**」 |
| GPL 系列需给源码/版权信息 | 「三、源码与版权信息」逐条列上游地址；随包另附 `LICENSE.GPL-2.0.txt`、FFmpeg 的 COPYING 全文 |
| 技术支持 | **问题反馈 / 官方文档 / 隐私政策**三项（见下"一处待你确认"） |

### 一处待你确认（**没有项目邮箱**）

全仓 `grep` 不到任何邮箱（AGC 元数据里也只有隐私政策 URL），所以「问题反馈」用的是
**公开 Issues 入口**，且**只在一处常量里**（`tools/gen-oss-notices.mjs` 的 `SUPPORT`）：

```
问题反馈：https://github.com/sol5766/dshm/issues
官方文档：https://github.com/sol5766/dshm
隐私政策：https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2058241561019327424
```

若你有正式支持邮箱，改那一处后重跑 `node tools/gen-oss-notices.mjs` + 重编即可
（**不要**用 `support@example.com` 这类占位——上架审核会核这个字段）。

---

## 5. 交付件（Beta 合并 APP，含「关于」）

| 项 | 值 |
|---|---|
| 路径 | `~/Download/com.dshm.dshclient/DSHM-beta-1.1.6-1010007-combined-debug.app` |
| 大小 / SHA-256 | `511,711,515 B` / `8365099cb7463062ed826f98ce35e12c0b275b05e97a3e6e1f3a3a6489851342` |
| 工作区留档 | `dist/beta/DSHM-beta-1.1.6-1010007-20261028T093157/` |
| 构建读数 | `BUILD SUCCESSFUL in 32 s 645 ms`；`CompileArkTS` 0 error |
| 包内验证 | `entry-default.hap` 内 `resources/rawfile/licenses/OSS-NOTICES.json` 83,151 B + `OSS-NOTICES.txt` 35,559 B + `LICENSES.txt` 2,611 B；`ets/modules.abc` 内含 `开源组件声明` / `源码与版权` / `技术支持` / `licenses/OSS-NOTICES.json` 四个探针串（⇒ 面板与读取路径真进了包） |

---

## 6. 回归读数（本轮实跑）

| 门禁 | 结果 |
|---|---|
| `check-dead-code` | ✅ 无死代码（剥离旧方法后没有留下未使用的成员/import） |
| `check-feature-wiring` | ✅ 功能接线全在 |
| `check-dead-handlers` | ✅ **从误报红修到绿**：`MeetingPanel.onTick` 是标准 prop 默认值（第 940 行确实在用 `this.onTick(...)`），旧判据不认"赋值右侧带返回类型注解"的箭头形态 ⇒ 扩展 `isPropDefault` 覆盖该形（判据仍严格：右箭头必须紧跟 `{`，真死按钮不放过） |
| `gen-oss-notices --check` | ✅ 声明与当前随包内容一致 |

---

## 7. 维护约定（下次核心升级时）

1. 升核心 → 跑 `node tools/pack-core.mjs --place-in-app`；
2. 跑 `node tools/gen-oss-notices.mjs` **重新生成**声明（新增/升级的 npm 依赖会自动进清单）；
3. 跑 `node tools/gen-oss-notices.mjs --check` 并纳入出包前检查（否则"声明落后于包"无人发现）；
4. 若有**新的随包原生库**且未登记，生成器会**判失败并点名**，在 `NATIVE_LIBS` 里补"上游项目 + 许可证"即可。