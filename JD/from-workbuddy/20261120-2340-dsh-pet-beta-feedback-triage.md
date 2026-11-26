# Beta 包端测试反馈研判：dsh-pet 诊断与修复手册（2026-11-20）

> 输入：`~/Download/DSHM-dsh-pet-诊断与修复手册-2026-11-20.md`（下称「手册」），用户标注为「beta 包端测试反馈」。
> 对应看板：JD-020（dsh-pet 桌面环境落地 + Beta 包）。
> 结论一句话：**这不是 Beta 的缺陷反馈，而是另一条渲染通道的诊断；手册把 `display` 改成 `web`，恰好关掉了 Beta 桌面宿主的启动条件。Beta 实现的正是手册 §4 里说「要另做一个工程」的方案 B。**

---

## 0. 先定位：两条通道，别混为一谈

手册环境与 Beta 内嵌宿主**是同一套核心、同一台机**，但走的是两条不同的渲染通道：

| | 手册诊断的通道 | Beta `150928` 的通道 |
|---|---|---|
| 宿主 | `dsh 0.2.2-rc.5+dshm.1` / `ondevice` / `127.0.0.1:3121` | 同一套（`hostcore/core-recipe.json:3,15`、`hostcore/app/main.js:1603,2048`），打进 HAP |
| 宠物渲染位置 | DSH 网页内 `shell.overlay` 浮层（`src/client/pet/multi.ts`） | ArkTS `PetAbility` 透明置顶子窗 + `pages/PetWeb` |
| 页面来源 | dsh-pet 客户端 overlay | dsh-pet 自带的 `runtime/electron-helper/index.html`，经 `/dsh-pet-native/probe.html` 同源注入 shim |
| 桌面悬浮 | 依赖 Electron 拉起（手册 §4） | `DSH_PET_IN_PROCESS=1` 禁掉 Electron，自己起子窗（`dshm-pet-host.cjs:99`） |
| 触发条件 | `display=web`/`both` → `isWebVisible` | `display=desktop`/`both` → Beta 门控 |

**手册 §4 的原话**：

> **B**：真要「桌面级」悬浮，得单独做一个 ArkTS 应用（透明 + 置顶窗口 + Web 组件加载同一套页面），这是另一个工程，不是插件配置能解决的。

这个「另一个工程」**已经做完并出包了**：JD-017（独立模式零 Electron、渲染页出蓝毛小女仆）→ JD-018/019（ArkTS 子窗 + petBridge，PARTIAL 已修 DPR/拖动/穿透）→ JD-020（`PetAbility` 落地 + Beta `150928`）。手册作者显然是在**没启用/没测到** Beta 桌面宿主的前提下写的，所以「桌面悬浮做不到」是对「dsh-pet 原样」成立，对「装了 DSHM Beta 的设备」不成立。

---

## 1. 手册四条结论 × Beta 逐条对照

| # | 手册结论 | 对 Beta 的判定 | 说明 |
|---|---|---|---|
| 1 | `display=desktop` 网页端不渲染；**已改成 `web`** | ⚠️ **这是本次反馈最关键的动作，且会直接让 Beta 桌宠不启动** | Beta 门控只认 `desktop\|both`（`EntryAbility.ets:2357`、`PetAbility.ets:76`）。改成 `web` 后 `hasDesktopPet=false` → `PetAbility` 不启动 / 运行期自动退出。设备当前 `display=web`（手册 §6），所以现在装 Beta 看不到桌面桌宠是**预期行为**，不是黑框 bug |
| 2 | 141 个素材名被污染，全部 404；**已改名并验证 200** | ✅ 通用利好，Beta 同样受益 | 无论网页 overlay 还是 `/dsh-pet-native` 渲染页，动画/表情/字体最终都取 `profiles/ondevice/node_modules/dsh-pet/assets`。修好后 Beta 子窗才能拿到 200、出小人（详见 §3） |
| 3 | Electron 无 `openharmony` 目标，桌面悬浮「不可修」 | ✅ 结论正确，且**正是 Beta 立项原因**；对 Beta 不成立 | Beta 根本不用 Electron：`DSH_PET_IN_PROCESS=1` + ArkTS 子窗 + `WINDOW_TOPMOST`。手册 §3「顺带停掉 Electron 404 噪音」在 Beta 里是冗余但无害 |
| 4 | ArkWeb 可能不认 VP9-alpha，「需你刷新看一眼」 | ⚠️ 通道不同，不能直接套用；给验证动作，别急着下结论 | 详见 §4 |

补充：`display=web` 时手册日志 `桌面判定：pets=1，桌面可见=1 → hasDesktopPet=true` 是 **dsh-pet 自己的桌面判定**，Beta 的 watcher 读的是同一个 `/dsh-pet-7340/config` 的 `display` 字段，两者同源、链路一致（手册 §1/§7 与 `EntryAbility.ets:2346`）。所以「右键在桌面显示」改 `display` → 2s 内 Beta watcher 就能感知，触发链路没问题。

---

## 2. 最关键：`display` 语义互斥矩阵

`display` 是「在哪一端渲染」，不是「能不能渲染」。两条通道对它的解释**正好互补/互斥**：

| `display` | 网页 overlay（`isWebVisible`） | Beta ArkTS 子窗（门控） | 设备现象 |
|---|---|---|---|
| `web` | ✅ 显示 | ❌ **不启动** | 手册当前状态：网页里有小人，桌面没有 |
| `desktop` | ❌ 不显示 | ✅ 启动 | 网页里空、桌面子窗里有小人 —— **这才是测 Beta 该用的值** |
| `both` | ✅ 显示 | ✅ 启动 | ⚠️ **会出现双份宠物**（网页一只 + 子窗一只），见 §5 待决策 |
| `none` | ❌ | ❌ | 全都不显示 |

由此可直接回答「为什么反馈里说上不了桌面」：

- 手册为了让**网页端**能看见小人，把 `display` 从 `desktop` 改成了 `web`（§1、§6、§8 回滚命令）；
- 这个改动**正好**把 Beta 桌面宿主的唯一触发条件关掉了；
- 因此在这台设备上按现状装 `150928`，`PetAbility` 不会启动 → 既没有桌宠，也（因为门控生效）不该有黑框。**「无黑框 + 无桌宠」是本轮门控修复后的正确表现**，与 23:1x 反馈的「多出黑框」是两个不同阶段的问题。

**复测前必须把 `display` 改回 `desktop`（只测桌面）或 `both`（两端都要）**，命令见 §6。手册 §8 已给出可直接用的回滚命令。

---

## 3. 141 个素材名：通用利好 + 责任线索

- 现象与修复：手册 §2 已把 `assets/webm`(114) / `memes`(26) / `fonts`(1) 共 141 个带 `\n19 mtime=...` 尾巴的坏名改回干净名，并逐个验证 `/thumb` `/font` `/pic/memes` 返回 200。
- **对 Beta 的影响**：`dshm-pet-host.cjs` 的 `/dsh-pet-native` 只 serve `runtime/electron-helper` 目录内的 html/js/css；宠物本体素材是**页面运行时**通过 dsh-pet 自己的 `/dsh-pet-7340/thumb|font|pic` 取的，源头就是这份 `assets`。所以坏名时 Beta 子窗里同样会「只剩气泡、没有小人」；改名修复后 Beta 也能正常出动画。
- 插件定位已核对：`findPetRoot()`（`dshm-pet-host.cjs:44-82`）的 BFS 会命中 `home/profiles/ondevice/node_modules/dsh-pet`（手册 §0 的安装路径），`helperDir` 取 `runtime/electron-helper`（手册 §4 的入口目录）——Beta 能找到手册里这份插件。
- **责任线索（需排查，不擅自下结论）**：手册 §2.3 提到 `~/Download/com.dshm.dshmbeta/pet-rename-backup.json`（2026-11-19 00:53，141 条「坏名 → 干净名」映射，包名为 Beta 的 bundle），指认坏名来自「之前一次把 `ls`/`stat` 元数据拼进文件名的改名脚本」。该文件确实存在，内容确为 `\n19 mtime=` 形态。本次核对：当前工程源码与 `tools/` 内**没有**该改名脚本，git 历史也查不到 `*pet-rename*`，推测是设备端/Download 侧的一次性操作。
  → 建议排查 Beta 的安装/更新流程（尤其插件解包、`place-host-app`、`pack-core`）是否会再次污染文件名；手册 §2.5 的幂等脚本 `dsh-pet-fix-assets.py --check/--fix` 默认扫描目录正是这份 assets，可作为每次装插件后的体检步骤。

---

## 4. VP9-alpha：先分清是哪条通道的 `<video>`

手册 §5 的担忧（OpenHarmony 6.0.0.36 起 ArkWeb 取消 VP8/VP9）针对的是**网页 overlay 里的 `<video>`**；Beta 子窗加载的是 `runtime/electron-helper` 渲染页，是另一套 DOM，但用的是同一批 `.webm` 素材、同一个 ArkWeb 内核。

已有证据**倾向于「能播」但不宜直接互相抵消**：

- JD-017（`from-deveco/20261120-dsh-pet-probe-result.md`）：独立模式渲染页出「蓝毛小女仆」+ 气泡 + 名牌，**2s 内 15% 像素动画变化** —— 说明素材被解码并播放了，不是空 `<video>`；
- JD-018/019：ArkTS 子窗里宠物本体持续渲染、拖动/穿透/菜单取证成立。

但手册说得对：这两条证据是 POC/子窗环境，不等于「设备 DSH 网页 overlay 刷新后也一定显示」。所以不替用户下结论，给一个 30 秒判据，写进复测提示词：

1. 刷新 DSH 页面，看右上角（`top-right`，marginX 24 / marginY 100）有没有小人；
2. 只有气泡/空白 → F12 搜 `[dsh-pet]`：`素材加载失败 404` ⇒ 名字又坏了，跑 `--fix`；`MEDIA_ERR_SRC_NOT_SUPPORTED` ⇒ VP9 不被支持；
3. 若确认为 VP9，手册 §5 方案 A（用 `main-character.png` 静态立绘兜底，动画退化为静态）是性价比最高的兜底，且**上游已有 Safari 丢 alpha 的 `.mov` 分支可参照**，可作为后续给 dsh-pet 的改法（手册 §9 建议 1）。

---

## 5. 对 Beta 代码的结论：无需改动、无需重出包

逐项确认 `150928` 已具备处理本次反馈的能力：

| 关注点 | 现状 | 证据 |
|---|---|---|
| 无宠不弹黑框 | 配置门控已落地 | `EntryAbility.ets:2324-2368`；`PetAbility.ets:123-146,149-161` |
| 静态路由可用性预检 | 启动前查 `/dsh-pet-native/probe.html` 200 | `PetAbility.ets:84-101,131-135` |
| 查询并发防误杀 | `checkBusy` 返回 true（按「仍在显示」处理） | `PetAbility.ets:60-62` |
| 右键在/不在桌面显示 | watcher 2s 轮询 `display`，自动启停 | `EntryAbility.ets:2330-2364` |
| 零 Electron | `DSH_PET_IN_PROCESS=1` | `dshm-pet-host.cjs:96-107` |
| 拖动 1:1 | shim 还原 `screenX/Y` 为物理 px | `dshm-pet-shim.js:1-24` |

手册没有暴露 Beta 代码的新缺陷；核心问题是「测试配置前提与 Beta 触发条件互斥」+「测试方不知道 Beta 有独立桌面宿主」。**因此本轮不改 ArkTS、不重出包**，改的是测试指引与看板登记。

**一个需要用户/产品决策的架构项（本次不擅自改）**：`display=both` 会同时让网页 overlay 和 Beta 子窗渲染 → **双份宠物**。若最终要「网页里也有、桌面也悬浮」，二选一：

- (a) 约定 `both` 时 Beta 子窗不启动（只留网页 overlay），桌面悬浮仅 `desktop`；
- (b) `both` 时让 shim/宿主隐藏网页 overlay，只留子窗。

当前门控是「`desktop|both` 都启动」，即会出现双份。建议先按「只测桌面用 `desktop`」推进验证，再决定 `both` 语义。

---

## 6. 复测前必做（可直接复制）

设备当前 `display=web`（手册 §6）。只测 Beta 桌面宿主，改回 `desktop`：

```bash
TOKEN=$(python3 -c "import json;print(json.load(open('/data/storage/el2/base/haps/entry/files/dsh/home/host-ready.json'))['token'])")
curl -s -H 'Content-Type: application/json' \
  -d '{"id":"main","display":"desktop"}' \
  "http://127.0.0.1:3121/dsh-pet-7340/pet-display?token=$TOKEN"

# 确认生效
curl -s "http://127.0.0.1:3121/dsh-pet-7340/config?token=$TOKEN" \
  | python3 -c "import sys,json;p=json.load(sys.stdin)['main']['pets'][0];print(p['id'],p['display'],p['size'])"

# 素材 200 体检（装机后每次都跑）
python3 ~/Download/dsh-pet-fix-assets.py --check
curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:3121/dsh-pet-7340/thumb/main/待机呼吸休闲.webm?token=$TOKEN"
```

改完后**完全退出 DSHM 再启动**，2s 内应命中：

```
hilog | grep -E "dsh-pet-host|entry/pet"
# 预期：
# [dsh-pet-host] /dsh-pet-native 已注册，pluginRoot=...profiles/ondevice/node_modules/dsh-pet
# entry/pet: pet subwindow ready: http://127.0.0.1:3121/dsh-pet-native/probe.html?...
```

若出现 `无 desktop/both 宠物，PetAbility 退出` ⇒ `display` 没改成功；若出现 `/dsh-pet-native 不可用` ⇒ 插件路径没找到或 `registerPetHost` 未注册，把 `pluginRoot` 日志带回。

---

## 7. 待办与决策请求

1. **【测试方】** 按 §6 把 `display` 改回 `desktop` 后重测 `150928`，重点回填：黑框是否复现、桌面是否出插件自己的小人、拖动是否 1:1、素材是否 200。
2. **【用户/产品】** 定 `both` 语义（§5 双份宠物取舍）。
3. **【WorkBuddy】** 排查 Beta 安装/更新流程是否会再次污染插件素材文件名（§3 责任线索）；若确认，加装机后 `--check` 自检并显式报错，避免静默 404。
4. **【后续/上游】** 若真机确认 VP9 不支持，按手册 §5 方案 A + §9 建议 1 做静态立绘兜底；同时把「安装后素材自检」「`openharmony` 时别下载 Electron 并给降级提示」两条建议提给 dsh-pet 作者。
5. **仍待验证的旧项**（未在本次反馈覆盖）：右键「在/不在桌面显示」实时启停、触摸拖拽、空闲后交互恢复、DSHM 联动（工作状态/碎碎念/余额/待办）。

---

## 8. 证据索引

- 输入手册：`~/Download/DSHM-dsh-pet-诊断与修复手册-2026-11-20.md`（§1 display、§2 素材、§4 Electron/方案 B、§5 VP9、§8 回滚、§9 上游建议）
- 改名脚本：`~/Download/dsh-pet-fix-assets.py`（默认扫描 `.../profiles/ondevice/node_modules/dsh-pet/assets`）
- 旧改名备份：`~/Download/com.dshm.dshmbeta/pet-rename-backup.json`（141 条，2026-11-19 00:53）
- Beta 门控：`entry/src/main/ets/entryability/EntryAbility.ets:2324-2390`
- Beta 子窗/预检：`entry/src/main/ets/entryability/PetAbility.ets:58-161`
- 宿主伴生层：`hostcore/app/dshm-pet-host.cjs:44-82,96-169`、`hostcore/app/dshm-pet-shim.js:1-24`
- 核心身份：`hostcore/core-recipe.json:3,15`、`hostcore/app/main.js:1603,2048`
- 历史结论：`JD/STATUS.md` JD-017/018/019/020
