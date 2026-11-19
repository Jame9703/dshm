# 421-碰一碰传文件（DSHM 端实现与修复方案）

> 状态：**已落地（2026-11-17：WP1/WP2/WP3/WP5 + 诊断增强）**；WP4 与 WP6 的键值格式未做，差异见 §8。本文按「开发端可直接执行」写：每个工作包给改动文件、函数、代码骨架、验收判据。
> 背景调研见 [`418-碰一碰传文件调研（ShareKit沙箱接收·WorkBuddy逆向对照）.md`](418-碰一碰传文件调研（ShareKit沙箱接收·WorkBuddy逆向对照）.md)；本文**更正**其 §6 的两条判断，见 §1.3。

## 0. 一句话

DSHM 侧只接上了「ArkTS 接收器 + Web 注入」两段，**注册寿命、窗口覆盖面、能力表**三处结构性缺口让它等于没实现；
按本文 6 个工作包改完，PC 档碰一碰即可把文件放进当前会话输入框（不自动发送）。

---

## 1. 现状审计

### 1.1 已有件（不是从零开始）

| 件 | 位置 | 状态 |
|---|---|---|
| ArkTS 接收器 | `entry/src/main/ets/system/KnockShareReceiver.ets` | 有，能注册、能 receive、能 base64 读出 |
| 建窗即注册 | `EntryAbility.ets:1430` → `:1693 bootstrapKnockReceiver()` | 有，但**只在主窗分支** |
| 页面接线 | `WebApp.ets:5718 startKnockReceiver()` | 有，但 `:5811 aboutToDisappear` 会 `stop()` 掉 |
| Web 垫片 | `WebApp.ets:3393 KNOCK_SHIM_JS` | 有：base64 → File → 合成 `paste`，退路 `drop` |
| 诊断 | `filesDir/diag-knock` | 有，但缺 `utd`/`records`/在线心跳 |

### 1.2 三处结构性缺口

| 编号 | 缺口 | 现状代码 | 后果 |
|---|---|---|---|
| **G1** | 注册与**页面**同寿命 | `WebApp.aboutToDisappear` → `receiver.stop()` → `harmonyShare.off('dataReceive')` + `started=false` + `pending=[]` | 页面销毁/重载一次，窗口还在，接收方已注销；系统只能按默认逻辑落盘 |
| **G2** | 只注册**主窗** | `EntryAbility.ets:1419` 的 `if (launchParams.kind === WindowKind.MAIN)` 分支里才调 `bootstrapKnockReceiver` | 会话窗（独立 UIAbility 实例）**完全没有注册**；碰会话窗必然落默认 |
| **G3** | 能力表窄 + 数量上限 5 | `KnockShareReceiver.ets:242` 只有 `FILE/IMAGE/MEDIA`；`MAX_PER_CAPABILITY=5` | `FILE`(`general.file`) 是**空叶子类型**（UTD 表实读：无子类型、无扩展名、无 MIME），文档类 `.md/.pdf/.docx/.txt` 都在 `general.object` 分支下，匹配不上；多选第 6 个文件触发系统"数量异常"弹窗 |

G1/G2 是"碰了没反应"的确定来源。G3 是**能力面的硬缺口**：只要发送端按扩展名推 UTD（官方推荐做法，`.md → general.markdown`），文档类就必然落空；它是不是本次的**主因**，由 §2 的 A/B 一碰定（改这一包成本最低，建议直接改）。

### 1.3 对 418 §6 的两条更正

1. **"注册成功但系统不投递 ⇒ 指向签名"证据不足。** 把 `diag-knock` 时间轴与 `Huawei Share/` 落盘对完：15 份副本里没有一次能确认"接收方在线却被跳过"——
   - 11-17 19:58–21:14 那 9 次：应用在 15:03:50 已 `onPrepareToTerminate` 退出，21:37 才重启；
   - 11-16 21:51/21:53：在 21:50:27 `off ok` 之后；
   - 11-16 20:58/20:59/21:27：与 `start` 同一分钟，无法判定。
   签名是**待验证的环境前提**（验收要用 AGC 邀请测试包），不是当前修复依据。
2. **"能力表抄 WorkBuddy 即可"不成立。** WorkBuddy 字节码还原出来的注册就是 `FILE+IMAGE+MEDIA`（与 DSHM 逐字相同），其文档 §3.4 的「FILE / OBJECT」是按扩展名归纳的说法，不代表注册了 `general.object`。

复核命令（3 行）：

```sh
tail -30 /data/storage/el2/base/haps/entry/files/diag-knock
ls -l "~/Huawei Share" | head
python3 -c "import json;d=json.load(open('/system/etc/utd/conf/uniform_data_types.json'))['UniformDataTypeDeclarations'];print([x['typeId'] for x in d if 'general.file' in x.get('belongingToTypes',[])])"
# 最后一条期望输出 []：general.file 没有任何子类型
```

---

## 2. 落地前判别实验（30 分钟，决定 G3 的优先级）

保持 DSHM **主窗前台**且 `diag-knock` 最后一行是 `on ok`，逐条做：

| # | 动作 | 期望（修好后） | 判据 |
|---|---|---|---|
| A | 碰一个 `.md` | 进输入框 | diag 出现 `target` 行 |
| B | 碰一张 `.jpg` | 进输入框 | 同上 |
| C | 关掉页面再打开（不重启应用），立刻碰 | 进输入框 | diag 最后一条仍是 `on ok`（G1 修好后应如此） |
| D | 打开会话窗，碰在会话窗上 | 进该窗输入框 | diag 出现该窗 `windowId` 的 `on ok` |

判读：

- A 不通、B 通 ⇒ **G3 就是根因**（文档类 UTD 没覆盖）；
- A/B 都不通、diag 无 `target` 行 ⇒ **G1/G2 或签名**；继续 C/D，C 通了说明 G1，D 通了说明 G2；
- A/B 都不通、C/D 都通 ⇒ 只剩签名；用 AGC 邀请测试包复测，侧载包不通过不算 bug。

---

## 3. 实现方案（6 个工作包）

### WP1 注册与窗口同寿命（G1）

**改动**

| 文件 | 函数 | 动作 |
|---|---|---|
| `KnockShareReceiver.ets` | `stop()` | 拆成 `release()`（窗口销毁才 off）与 `detachPage()`（只摘页面钩子） |
| `WebApp.ets:5811` | `aboutToDisappear` | 改调 `detachPage()`，不再 `stop()` |
| `EntryAbility.ets:1707` | `onWindowStageDestroy` | 调 `KnockShareReceiver.release(windowId)` |

**骨架**

```ts
/** 页面销毁：只摘钩子，不 off、不丢挂起队列。 */
detachPage(): void { this.onFiles = undefined; }

/** 窗口销毁：此时才真正注销系统监听并清队列。 */
release(): void { this.stop(); this.pending = []; this.receivedPaths = []; }
```

**判据**：`diag-knock` 不再出现"页面消失就 `off ok`"；页面重载后仍只有一条 `on ok`（幂等空跑）。

### WP2 每个窗口都注册（G2）

**改动**

| 文件 | 动作 |
|---|---|
| `EntryAbility.ets:1430` | `bootstrapKnockReceiver(windowStage)` 移出 `MAIN` 分支，每个 WindowStage 都调 |
| `EntryAbility.ets:1693` | 记录本实例的 `knockWindowId`，供 `onWindowStageDestroy` 释放 |
| `KnockShareReceiver.ets` | 单例改为**按 windowId 索引**的 Map（一窗一实例，一窗一个 `RecvCapabilityRegistry`） |

**骨架**

```ts
export class KnockShareReceiver {
  private static readonly byWindow: Map<number, KnockShareReceiver> = new Map();

  static acquire(ctx: common.UIAbilityContext, windowId: number): KnockShareReceiver {
    const hit = KnockShareReceiver.byWindow.get(windowId);
    if (hit !== undefined) return hit;
    const r: KnockShareReceiver = new KnockShareReceiver(ctx, windowId);
    KnockShareReceiver.byWindow.set(windowId, r);
    return r;
  }
  static release(windowId: number): void {
    const r = KnockShareReceiver.byWindow.get(windowId);
    if (r === undefined) return;
    r.release();
    KnockShareReceiver.byWindow.delete(windowId);
  }
}
```

**注意**：不要顺手把通知、连接池这些**全局单例**改成按窗多实例（它们共享同一进程，多实例会重复发通知/重复认证）。
`WebApp.startKnockReceiver()` 里取窗口 id 也改为**本页自己的** `window.getLastWindow(ctx)`，不再依赖只有主窗才发布的 `AppStorage dshMainWindowId`。

### WP3 能力表与数量（G3）

**骨架**（`KnockShareReceiver.ets:242`）

```ts
private static readonly MAX_PER_CAPABILITY: number = 20;

capabilities: [
  // 逻辑根：文档 / 文本 / 压缩 / 媒体 / 可执行 …… 全在 general.object 分支下
  { utd: uniformTypeDescriptor.UniformDataType.OBJECT, maxSupportedCount: KnockShareReceiver.MAX_PER_CAPABILITY },
  // 物理根：utd 恰为 general.file 的未知扩展名文件
  { utd: uniformTypeDescriptor.UniformDataType.FILE,   maxSupportedCount: KnockShareReceiver.MAX_PER_CAPABILITY },
],
```

- `OBJECT` 能一条盖住 `.md/.txt/.pdf/.docx/.xlsx/.pptx/.zip`（官方 FAQ：*"如支持全部数据类型，可声明 general.object"*）。
- 若真机上 `on()` 对 `OBJECT` 报错（未实测），回退成三条：`TEXT` + `COMPOSITE_OBJECT` + `ARCHIVE`。
- `maxSupportedCount` 是**单次**上限，超过会走系统"数量异常"弹窗；20 够日常，别设 500。

### WP4 接收目录与文件消费

**现状**：`receive(filesDir 根)`（`:347`），传输期间整个 filesDir 被临时授权。

**改**：一次性空目录 + 失败回退。

```ts
private receiveDir(): string {
  const dir: string = `${this.ctx.filesDir}/knock/${Date.now()}`;
  fileIo.mkdirSync(dir, true);
  return dir;
}
// handleTarget 里：target.receive(fileUri.getUriFromPath(this.receiveDir()), cb)
// onResult / catch 后：rmdir 整个目录（`fileIo.rmdirSync(dir)`），失败留痕
```

- 若 `receive()` 返回错误（目录不可用），**回退** `filesDir` 根重试一次——这是 418 §6 里"系统只放行已授权根"疑虑的保险。
- `MAX_FILE_BYTES` 16 MiB → 32 MiB（`runJavaScript` 的脚本体积上限）；
  超过 32 MiB 走二期：`onInterceptRequest` 把文件以同源路径供 `fetch`，页面 `fetch` 后 `new File()`。二期不在本次范围。

### WP5 Web 侧投递（当前最脆的一环）

**上游事实**（`dsh-client-ui-conversation/src/client/input/file-intake.ts:65-77`）：

```ts
const paste = (event) => {
  if (event.defaultPrevented || event.clipboardData === null) return;
  const origin = event.composedPath().find(v => v instanceof Element);
  if (origin instanceof Element && origin.closest(EDITABLE) !== null) return;  // ← 焦点在输入框里会被吞
  const { files } = clipboardFiles(event.clipboardData);
  if (files.length === 0) return;
  const target = pasteTarget(document);                                        // ← 没有 composer 就静默丢
  if (target === undefined) return;
  event.preventDefault();                                                      // ← 只有真的接住才 prevent
  target.add(files, ...);
};
```

⇒ 三条硬约束：

1. 合成 `paste` 的**事件路径里不能有可编辑元素**（现有 shim `document.dispatchEvent` 正好满足，别改成往输入框上派发）；
2. **必须有一个已注册且 `accepts()` 的 composer**，首页/无会话时 `pasteTarget` 为 `undefined`，文件被静默丢弃；
3. `preventDefault` 只在**接住**时调用 ⇒ 可用 `event.defaultPrevented` 判定是否真的投递成功。

**改 shim（`KNOCK_SHIM_JS`）**

```js
function emit(payload) {
  const file = toFile(payload);
  if (!file) return 'bad-payload';
  const dt = new DataTransfer(); dt.items.add(file);
  const ev = new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true });
  document.dispatchEvent(ev);                    // 目标必须是 document（见约束 1）
  if (ev.defaultPrevented) return 'paste';       // 官方 intake 接住了
  // 退路：官方 document 级 drop（drop-events.ts；需 canAcceptDrop 为真、types 含 'Files'）
  const dev = new DragEvent('drop', { dataTransfer: dt, bubbles: true, cancelable: true });
  document.dispatchEvent(dev);
  if (dev.defaultPrevented) return 'drop';
  return 'unrouted';                             // ← 关键：不再谎报 paste
}
```

**路由（一期，不做自动建会话）**

- 在会话页 / 新建会话页：直接按上面投递；
- 首页（无 composer）：文件留在 ArkTS 挂起队列，Web 层用 `MutationObserver` 监听 `[data-composer-card]` 出现（≤60 s），出现即补发；同时给一条轻提示"碰一碰收到 N 个文件，进入会话后自动放入"；
- 60 s 内没进会话：留在队列，`onPageEnd` 时再试一次（现有 `deliverKnockFiles` 已有该入口）。

**注意**：`Target.add(files)` 之后是官方上传管线，失败会在 UI 上给红字，不需要 shim 兜。

### WP6 诊断契约（验收全靠它）

`diag-knock` 每行统一成键值对，便于 diff 与脚本判读：

```
t=2026-11-17T14:08:06.775Z ev=on    win=759 utd=-               n=-  size=-  msg=caps=OBJECT,FILE max=20
t=2026-11-17T14:31:02.101Z ev=alive win=759 utd=-               n=-  size=-
t=2026-11-17T14:31:20.442Z ev=target win=759
t=2026-11-17T14:31:20.901Z ev=data  win=759 utd=general.markdown n=1 size=3228 path=.../knock/1763.../pnpm复测.md
t=2026-11-17T14:31:21.003Z ev=result win=759 code=0
t=2026-11-17T14:31:21.440Z ev=inject win=759 path=paste
```

- `ev=alive`：窗口 `WindowStageEventType.ACTIVE` 时写一行（判断"碰的那刻在不在线"）；
- `ev=data` 必须记 `utd`——**这是 G3 的唯一现场证据**；
- `ev=inject` 的取值只能是 `paste|drop|unrouted|bad-payload`，`unrouted` 即"页面层没收下"。

---

## 4. 验收清单（真机 PC 档）

| # | 场景 | 预期 | 判据 |
|---|---|---|---|
| 1 | 主窗、会话内，碰 1 个 `.md` | 附件 chip 进输入框，不自动发送 | `ev=data utd=general.markdown` → `ev=result code=0` → `ev=inject path=paste` |
| 2 | 主窗、会话内，碰 1 张 `.jpg` | 同上 | `utd=general.jpeg` |
| 3 | 首页（无会话）碰 | 提示 + 进入会话后自动补发 | `ev=inject path=unrouted` 后 `ev=inject path=paste` |
| 4 | 页面重载后立刻碰 | 仍能收到 | 全程无 `off`；`ev=alive` 在碰之前有 |
| 5 | 会话窗碰 | 进该窗输入框，不串窗 | `ev=on win=<会话窗id>` |
| 6 | 一次选 6 个文件 | 全部到达（≤20） | `ev=data n=6` |
| 7 | 40 MiB 视频 | 不进（超出 32 MiB 上限） | `ev=data size=41943040` 后 `skip 超限` |
| 8 | 平板档 | 不注册 | `skip desktopForced=false` |
| 9 | 无回归 | 侧栏/拖拽/粘贴/文件选择器不受影响 | 131 条全量基线全绿 |

签名前提：**1–8 必须在 AGC 邀请测试包（release profile）上过一遍**。侧载 debug 包只用于开发期定位（`"type":"debug"` profile 见 `signing/`）。

---

## 5. 风险与边界

| 项 | 说明 |
|---|---|
| `OBJECT` 过宽 | 未真机实测；`on()` 报错则回退 `TEXT + COMPOSITE_OBJECT + ARCHIVE` |
| 合成事件 | 依赖上游 intake 不校验 `isTrusted`；上游若加门槛，`ev=inject` 会变 `unrouted`，改走二期 `onInterceptRequest` + 真 `fetch` 通道 |
| 多窗注册 | 只给"接收器"做按窗多实例；通知/连接/长时任务仍是全局单例，别一起改 |
| 大文件 | 32 MiB 是 `runJavaScript` 的实用上限；更大走二期 |
| 签名资格 | 系统侧是否按包签名放行沙箱投递，d.ts 无据、只有 WorkBuddy 文档经验；以 release 包实测为准 |
| 磁盘 | 落盘目录在 `filesDir/knock/<ts>`，`onResult` 后必须 `rmdir`；异常退出残留由启动时清扫兜底 |

---

## 6. 改动文件清单

| 文件 | 函数/常量 | 改动 |
|---|---|---|
| `entry/src/main/ets/system/KnockShareReceiver.ets` | `stop`/新增 `release`/`detachPage`、`byWindow` Map、`capabilities`、`MAX_PER_CAPABILITY`、`MAX_FILE_BYTES`、`receiveDir()`、`writeDiag` 格式 | ~120 行 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | `onWindowStageCreate`（1430 行附近）移出 MAIN 分支、`bootstrapKnockReceiver`（1693）记录 windowId、`onWindowStageDestroy`（1707）release | ~20 行 |
| `entry/src/main/ets/pages/WebApp.ets` | `startKnockReceiver`（5718）改用本页 windowId、`aboutToDisappear`（5811）改 `detachPage`、`KNOCK_SHIM_JS`（3393）加 `defaultPrevented` 判定与 `unrouted`、注入脚本（3444）透传 utd/size | ~80 行 |
| `docs/418-…md` | 文首状态块 | 已加 2026-11-17 更正注记（指向本文） |
| `docs/README.md` | §9 全量索引 | 已加 421 一行（`check-doc-index` 要求） |

门禁：`devecocli build --modules entry` + `dist/acceptance/` 131 条全量基线（`gen-full-yml-gates.py`）全绿后出**当前版本**（1010017，未升版）侧载包自测，再走 AGC 邀请测试。

---

## 7. 参考

- 沙箱接收与"类型不匹配 → 走华为分享默认逻辑"：[分享内容直达应用界面](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/knock-share-pc-phones-sandbox)
- 一步直达与接收规则：[目标设备接收分享数据一步直达体验](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/share-access-one-step)
- 能力表兜底写法（`general.object`）：[Share Kit FAQ](https://www.cnblogs.com/HarmonyOSSDK/p/19390918)
- 轻碰交互约束（俯视≤5°/正视≤25°/侧视>35°、同账号、亮屏）：[手机与 PC/2in1 碰一碰概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/knock-share-pc-phones-overview)
- 本机 UTD 表：`/system/etc/utd/conf/uniform_data_types.json`
- 上游 intake：`dsh-client-ui-conversation/src/client/input/file-intake.ts`、`dsh-client-ui-attachment/src/client/drop-events.ts`

## 8. 落地记录（2026-11-17）

- **已落地**：WP1（页面 `detachPage` / 窗口 `release`）、WP2（`byWindow` 一窗一实例，
  会话窗也注册）、WP3（`general.object + general.file`，单次上限 20；OBJECT 被拒时
  回退 `TEXT+COMPOSITE_OBJECT+ARCHIVE+FILE`）、WP5（shim 按 `defaultPrevented` 判
  paste/drop；无 composer 时文件留页面队列 60s 内补投，返回 `deferred`；`unrouted`
  回 ArkTS 队列）。
- **与本文字面不同**：
  1. WP4 未改接收目录：保持 `filesDir` 根（与 WorkBuddy 生产参考逐位一致），
     16 MiB 上限未动；
  2. WP6 未改成键值行：保留原有可读格式，只在 `读出` 行补 `utd`、`inject` 行补
     文件名与结果；
  3. 版本未升 1010018（版本号铁律：用户未要求升级），仍为 1.1.8 / 1010017。
- **真机冒烟**（MateBook 2in1，覆盖安装）：`files/diag-knock` 出现
  `windowId=770 type=32 showing=true getLast=770` /
  `knockShare on ok windowId=770` / `on ok windowId=770 caps=object,file max=20`
  ⇒ OBJECT 能力被系统接受，未走回退。
- **交付**：`dist/beta/DSHM-beta-1.1.8-1010017-20261117T144135/`（canonical）+
  `local-install/`（本机调试签名可侧载版，README-LOCAL.txt 内含 §4 测试步骤与判据）。
- **仍未验证**：真实碰一碰投递。侧载 debug 包若仍无 `target` 行，只能由 AGC 邀请
  测试（正式分发）复测；不能据此判代码失败。
