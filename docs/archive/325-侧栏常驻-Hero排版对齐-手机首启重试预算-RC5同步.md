# 325 · 侧栏常驻 / Hero 排版对齐官方 / 手机首启重试预算 / 上游 RC5 同步

> 日期：2026-10-31 ｜ 状态：**已实施，审核通过，出包**

---

## 0. 一页结论

| # | 用户口径 | 根因 | 处置 |
|---|---|---|---|
| ① | 「选完工作区自己还回去了…PC 平板就一直常驻」 | 展开与否**掺进了形态判定** | 规则只认用户显式偏好，否则常驻展开 |
| ② | 「会话区改成 我们要构建什么？」 | — | Hero 文案替换 |
| ③ | 「字体跟 dsh 官方看齐，与 logo 高度差不多」 | 我们写了 650/30px，官方是 500/26px | 字号/字重/行高抄官方，logo 32px 与之同高 |
| ④ | 「同步上游 0.2.1 RC5」 | — | `rc.5+dshm.99`，30 处端侧补丁全在 |
| ⑤ | 「手机初次启动又会卡住进不去」 | 重试预算 37.8s 在解包期耗尽 → 停在 ERROR | 解包期不消耗预算 + 预算扩到 30 次 + 退避封顶 |

---

## 1. 侧栏：形态不再参与展开判定

### 1.1 根因

旧规则（`sidebarExpandedForMode`）：

```ts
if (stored !== undefined) return stored;
return mode !== LayoutMode.DOUBLE;   // ← 双栏默认收起、三栏默认展开
```

**只要有第二个因素能决定同一件事，它就会在用户没操作时把状态改掉。**
真机上：选工作区 → 布局重算 → `mode` 在 DOUBLE / TRIPLE 间跳 → 侧栏自己翻转。

### 1.2 新规则

```ts
if (stored !== undefined) return stored;   // 用户点过就听用户的
return true;                                // 从没点过 ⇒ 常驻展开
```

单栏（手机）不受影响：那个档位的呈现由 `sidebarPresentationOf` 恒给 OVERLAY。

### 1.3 门禁

`check-layout-fixtures` 的侧栏判据整体重写，并新增一条**核心回归**：

> 「形态不再影响展开态」—— 同一 `stored` 在 double / triple 下必须给出相同结果。

这条在旧实现下必红（未存过时 double=false、triple=true）。

> ⚠️ 该门禁在本机是**环境受阻**（需要 CLT 的 `platform` 模块解析，退出码 3），
> 本轮改用直接对纯函数跑行为矩阵验证，结果：double/triple 未存过均为 `panel`，
> 用户收起后换形态仍收起。

---

## 2. Hero 排版：对齐官方

官方 `_headline` 的事实（`dsh-client-ui-conversation`）：

```
font-size:26px / font-weight:500 / line-height:32px / color:label-primary
```

我们此前是 `font: 650 30px` —— **比官方更粗更大**，所以显眼得不协调。

现在：

| 项 | 旧 | 新 |
|---|---|---|
| 字号 / 字重 / 行高 | 650 / 30px / 1.15 | **500 / 26px / 32px**（抄官方） |
| logo 尺寸 | 44×44 | **32×32**（= 该行行高，视觉同高） |
| 窄屏 | 24px | 21px / 行高 26px，logo 26px 等比 |

文字：`惊鸿启动！` → **`我们要构建什么？`**

---

## 3. 手机首启卡住：重试预算在解包期耗尽

### 3.1 日志证据

- `2026-10-31 10_25_02.log`（手机）：**3 个 mission**、进程 `60479` 退出后新进程 `64766` 起来
- `64766` 的 chromium / nweb 计数 **0**（首启进程是 5 / 3）⇒ Web 引擎没起来
- `web engine is nullptr` + `api level of arkweb core is 0` 只出现在**首启**日志，正常运行的两次为 0

### 3.2 代码根因

`scheduleAutoRetry()` 指数退避：

```
600 + 1200 + 2400 + 4800 + 9600 + 19200 = 37,800 ms ≈ 37.8 秒
```

6 次用尽 ⇒ `phase = ERROR`。而首启要解包 **330MB / 35637 文件**的核心树，
远超 37.8 秒 —— 用户看到的就是"卡住"，杀掉重开那次树已解好，所以能进。

### 3.3 修法（三处）

| # | 改动 | 作用 |
|---|---|---|
| 1 | `launchUrl` 为空（宿主还在解包）时**不消耗预算**、1.5s 后再试 | 解包期无限等待，不再烧预算 |
| 2 | `AUTO_RETRY_MAX` 6 → **30** | 覆盖真实解包时长 |
| 3 | 退避加上限 `AUTO_RETRY_DELAY_CAP_MS = 3000`，并把指数截到 `2^8` | 避免 `600·2^29`（89 小时）这种天文数字 |

---

## 4. 上游 RC5 同步

| 项 | 值 |
|---|---|
| 配方 `coreVersion` | `0.2.1-rc.4+dshm.98` → **`0.2.1-rc.5+dshm.99`** |
| 容器 | 95.2 MB / 40794 条目，sha256 `b35224a1…` |
| 解包 | 329.5 MB / 35637 文件 |
| 端侧补丁 | **240 项断言全过**（30 处注入都在，上游原文已消失） |

### 4.1 打包器拦住的真问题（值得记）

`pack-core` 的 peer 精确钉法守卫报出 **11 处**版本漂移：

```
@deepseek-ai/dshm-tool-fs-remove: @deepseek-ai/dsh-fs 钉在 0.2.1-rc.4，树里是 0.2.1-rc.5
…（7 个自带插件共 11 条）
```

这正是 2026-10-16 事故的形态（peer 没跟着升 ⇒ 上游兼容闸门把 profile 行整条停用
⇒ `fs` 服务缺失 ⇒ session-controller 永远 pending）。已全部升到 `rc.5`。

### 4.2 顺带修掉两处"抄版本号"

| 文件 | 问题 | 处置 |
|---|---|---|
| `check-brand-surface` | AGC 草稿版本**写死** `0.2.1-rc.4+dshm.98` | 改为**从配方动态取** `coreVersion` |
| `check-meeting-ai-plugin` | 注释举例写死版本 | 改为"配方的上游基版本" |

---

## 5. 验证

```text
assembleApp -p product=default   BUILD SUCCESSFUL
assembleApp -p product=phone     BUILD SUCCESSFUL
48 道门禁（含核心树依赖 3 道）    FAILED=0
check-core-openharmony-patches   240 passed / 0 failed
check-resfile-core-zip           resfile 只 1 份容器，与配方、产出三方一致
```

### 5.1 编译期抓到的自身错误

改 Hero 注释时在**模板字符串内**写了反引号（包名），把模板提前闭合 ⇒ 一批
`arkts-no-any-unknown` / `Cannot find name 'client'` 报错。已把注释里的反引号改成普通文字，
并复核模板内反引号数 = 2、插值点 = 2。

---

## 6. 真机验收要点

| # | 场景 | 期望 |
|---|---|---|
| 1 | PC/平板选工作区 | 侧栏**保持常驻**，不再自己收回 |
| 2 | 点左侧按钮 | 收起/展开生效，且换窗口大小后**保持**用户的选择 |
| 3 | 会话区 | 彩色 logo + 「我们要构建什么？」，字号与官方一致、与 logo 同高 |
| 4 | 手机**首次安装**启动 | 一直停在启动页直到进入，不出现错误页 |
| 5 | 核心版本 | 设备上应为 `0.2.1-rc.5+dshm.99` |
