# 285 · 深色玻璃复测通过 + 探针 `dark` 字段误报

> 日期：2026-10-29 18:15 ｜ 状态：**只读复测，未改任何代码**
>
> 用户口径：「继续复测一下，开发端落实了」。
> 承接 [`284`](284-深色主题复测（深色玻璃规则从未生效-html应为body）.md)（深色规则从未生效的定性与修法）。
>
> 关联：[`282`](282-Web内沉浸光感只读诊断（标记选择器内核全通过卡在白底与旧包）.md)（亮色诊断）、
> [`283`](283-Web内沉浸光感（垫片实现·三次失败复盘与最终口径）.md)（开发端实现）。

---

## 0. 一页结论

| 项 | 结果 |
|---|---|
| `docs/284` §5.1 选择器改 `body` | ✅ **已落实**（源码 2 处） |
| `docs/284` §5.2 深色补 `backdrop-filter` | ✅ **已落实**（源码 2 处） |
| `docs/284` §5.4 探针补 `dark` / `rect` / `ua` | ✅ **已落实**（源码 11 处） |
| **深色材质实际生效？** | ✅ **是** —— `computedBg=rgba(38, 44, 58, 0.82)`，连续 3 拍稳定 |
| **亮色材质回验？** | ✅ **是** —— 切回亮色后 `rgba(214, 223, 240, 0.86)`，连续 2 拍稳定 |
| 亮暗两分支闭环 | ✅ **是**（其他字段不变、唯 `computedBg` 翻转，见 §4.1） |
| **探针 `dark` 字段可信？** | ❌ **不可信** —— 亮暗两态**恒报 `none`**，不随主题变化 |

**一句话**：**深色与亮色两档玻璃都已实测生效，主题切换正确**；唯一遗留是
**新加的 `dark` 探针字段因 falsy 判定恒报 `none`**，属可观测性缺陷（不影响渲染），需一行小修。

---

## 1. 复测原始读数

装包时间：设备 `entry.hap` **18:11**，源码 **18:06** ⇒ **产物晚于源码，本次未被"改完不出包"绊到**。

`~/diag-web-console` 中本次会话全部 `glass diag`（原文，仅去掉 `frameKids` 长串）：

```text
10:12:01.834Z  cssSupports=yes glassTop=-1  cols=0 bd=n/a                    computedBg=n/a                    dark=no-body  rect=n/a
10:12:02.377Z  cssSupports=yes glassTop=13  cols=0 bd=n/a                    computedBg=n/a                    dark=none     rect=n/a
10:12:02.937Z  cssSupports=yes glassTop=13  cols=0 bd=n/a                    computedBg=n/a                    dark=none     rect=n/a
10:13:01.925Z  cssSupports=yes glassTop=13  cols=1 bd=blur(40px) saturate(1.8) computedBg=rgba(38, 44, 58, 0.82)  dark=none     rect=1366x963
10:14:01.929Z  cssSupports=yes glassTop=13  cols=1 bd=blur(40px) saturate(1.8) computedBg=rgba(38, 44, 58, 0.82)  dark=none     rect=1366x963
```

**UA 全貌**（`docs/282` §5 曾「无读数」，本次补上）：

```text
Mozilla/5.0 (PC; OpenHarmony 7.0) AppleWebKit/537.36 (KHTML, …
```

⇒ 内核为 **OpenHarmony 7.0 ArkWeb**，`cssSupports=yes` 与之自洽。

---

## 2. 深色材质：确认生效（本次核心结论）

### 2.1 判据

| 判据 | 亮色期望 | 深色期望 | **本次实测** |
|---|---|---|---|
| `computedBg` | `rgba(214, 223, 240, 0.86)` | `rgba(38, 44, 58, 0.82)` | **`rgba(38, 44, 58, 0.82)`** ✅ |
| `computedBackdrop` | `blur(40px) saturate(1.8)` | 同左（深色已补声明） | **`blur(40px) saturate(1.8)`** ✅ |
| `cols` | ≥1 | ≥1 | **1** ✅ |
| `rect` | 非 0 | 非 0 | **1366x963** ✅ |

**`docs/284` §5.3 立的硬判据「同一会话内深色读数必须与亮色不同」——本次成立。**
上一轮深色时读数是 `rgba(214, 223, 240, 0.86)`（亮色值，说明不生效）；
本轮变成 `rgba(38, 44, 58, 0.82)`（深色值）⇒ **深色分支第一次真正跑通**。

### 2.2 观感预期（对照 `docs/284` §3 的量化）

| 状态 | 合成色 | 观感 |
|---|---|---|
| 修复前（深色下仍铺亮色材质） | `rgb(187, 195, 210)` 压 `rgb(21,21,23)` | 刺眼亮块 |
| **修复后（本轮）** | `rgba(38,44,58,0.82)` 叠暗底 ≈ **`rgb(35, 40, 52)`** | **与暗底融合，正常玻璃观感** |

⇒ 深色模式下"两列不再是刺眼亮块"这一关键改善**应当肉眼可见**。

---

## 3. 新发现：探针 `dark` 字段误报（P1）

### 3.1 现象

深色规则**明明命中了**（`computedBg` 是深色值），探针却报 **`dark=none`**。
两者矛盾，说明 `dark` 字段的取值逻辑有缺陷。

### 3.2 根因：falsy 判定把「空串属性」当成「无属性」

`WebApp.ets:1450`：

```js
var darkAttr = document.body ? (document.body.getAttribute('data-ds-dark-theme') || 'none') : 'no-body';
```

`||` 在左侧为 **falsy** 时取右值，而**空字符串是 falsy**：

| `<body>` 上的属性 | `getAttribute` 返回 | `(… || 'none')` | CSS `[data-ds-dark-theme]` 匹配 |
|---|---|---|---|
| `data-ds-dark-theme=""`（**空串**） | `""` | **`'none'` ← 误报** | **✅ 匹配** |
| `data-ds-dark-theme="true"` | `"true"` | `'true'` | ✅ 匹配 |
| 无该属性 | `null` | `'none'` | ❌ 不匹配 |

**CSS 的属性存在性选择器 `[attr]` 只判「属性是否存在」，不看值** ——
所以空串属性**照样命中深色规则**，而探针把它报成了"没有"。

⇒ **`dark=none` 与深色 Material 生效并不矛盾**：属性存在、值为空串、CSS 匹配成功、
但 JS 探针因 falsy 判定丢了信息。**这解释了本轮唯一的「读数互相打架」。**

### 3.3 修法（一行级）

把 `||` 改成显式 `null` 判定，并区分「空串」与「缺失」：

```js
var bodyAttrRaw = document.body ? document.body.getAttribute('data-ds-dark-theme') : null;
var darkAttr = document.body === null
  ? 'no-body'
  : (bodyAttrRaw === null ? 'absent' : (bodyAttrRaw === '' ? 'empty(命中)' : bodyAttrRaw));
```

**期望读数**：深色下应为 **`dark=empty(命中)`**（或 `true`），而不是 `none`。
有了它，`docs/284` §5.4 想要的「规则没命中 vs 属性没挂上」才真正可分。

### 3.4 为什么这个 bug 值得修（不是吹毛求疵）

探针的价值在于**无 DOM 通道时它是唯一事实来源**（`docs/283` §1 纪律）。
一个会在"生效"时报"未生效"的字段，比没有字段更危险 ——
下一次排查会直接照着 `dark=none` 得出"深色没挂上"的**反向错误结论**。
本轮我已经差点被它误导。

---

## 4. 亮色回验：已闭环 ✅（用户切回亮色后实测）

**补测时间**：用户于 18:15 左右切回亮色，探针随即产出两条亮色读数。

### 4.1 亮暗切换的精确前后对照（这是本报告最有力的一组证据）

切色前后**其他所有字段完全不变**，唯独 `computedBg` 翻转：

| 时刻 | `cols` | `computedBackdrop` | **`computedBg`** | `rect` |
|---|---|---|---|---|
| 10:15:01（深色末拍） | 1 | `blur(40px) saturate(1.8)` | **`rgba(38, 44, 58, 0.82)`** | 1366x963 |
| 10:16:02（亮色首拍） | 1 | `blur(40px) saturate(1.8)` | **`rgba(214, 223, 240, 0.86)`** | 1366x963 |
| 10:17:07（亮色稳态） | 1 | `blur(40px) saturate(1.8)` | **`rgba(214, 223, 240, 0.86)`** | 1366x963 |

**判读要点**：

- `cols=1`、`rect=1366x963`、`backdrop` 三者**全程一致** ⇒ 元素、尺寸、模糊强度都没变；
- **只有 `computedBg` 随主题翻转** ⇒ 证明**切换的是主题分支，不是别的东西**；
- 亮色连续 2 拍稳定（10:16:02 / 10:17:07）⇒ 不是切换瞬间的中间态。

⇒ **`docs/284` §5.3 的硬判据「深色读数必须与亮色不同」——现已双向成立。**

### 4.2 两分支最终状态

| 分支 | 选择器 | 期望值 | 实测 | 结论 |
|---|---|---|---|---|
| 深色 | `html.dshm-glass-top body[data-ds-dark-theme] .dshm-glasscol` | `rgba(38,44,58,0.82)` | ✅ 同 | **通过** |
| 亮色 | `html.dshm-glass-top .dshm-glasscol` | `rgba(214,223,240,0.86)` | ✅ 同 | **通过** |

**权重推理与实测一致**（这次推理没被实推翻）：

```text
亮色: html.dshm-glass-top .dshm-glasscol                         → (0,2,1)
深色: html.dshm-glass-top body[data-ds-dark-theme] .dshm-glasscol → (0,3,2)
```

- 深色下两条都命中，深色权重更高 ⇒ 深色胜出 ✅
- 亮色下深色不匹配，只有亮色命中 ⇒ 亮色值 ✅

### 4.3 主题切换链路健康度

`onThemeMode` 桥调用累计 **8 次**（本轮两次切换均被送达）⇒ 主题事件链路正常，非"通知丢了"。

> 提醒：`dark` 字段在亮色下**依然报 `none`**（6 次读数全是 `none`），
> 进一步印证 §3 的结论 —— 该字段**恒为 `none`、不随主题变化**，是 falsy 判定的缺陷，
> 不是"亮色下没有深色属性"这一事实。**修复前请勿依据 `dark` 字段做任何判断。**

---

## 5. 需要开发端继续落实的事项

| # | 事项 | 判据 | 优先级 |
|---:|---|---|---|
| 1 | 修 `dark` 探针字段的 falsy 判定（§3.3） | 深色下读 `dark=empty(命中)` 或 `true`，亮色下读 `absent`；**不再是两态恒 `none`** | **P1** |
| 2 | ~~亮色回验~~ | ✅ **已闭环**（§4.1：`rgba(214, 223, 240, 0.86)`，连续 2 拍稳定） | ~~P0~~ 完成 |
| 3 | 把「亮暗各取一次、两次必须不同」写进 `docs/283` §4 验收清单 | 清单里应有暗色那一档 | P1 |
| 4 | 主题切换瞬间的闪烁检查（`docs/284` §5.5 遗留） | 切换时不应有一帧亮块闪出 | P2 |
| 5 | 深色下 `backdrop-filter` 已补声明 — 复核是否有冗余 | 亮/深两块各自声明，可接受；若合并需注意 | P2 |

---

## 6. 复核命令

```bash
cd /data/storage/el2/base/haps/entry/files

# 1) 当前探针（本次深色已生效的证据）
grep -a "glass diag" diag-web-console | tail -3
# 期望：computedBg=rgba(38, 44, 58, 0.82)   ← 深色
#       切亮色后应为 rgba(214, 223, 240, 0.86)

# 2) 确认源码已改（三处）
grep -n "html.dshm-glass-top body\[data-ds-dark-theme\]" \
  ~/data/DSHM-deveco-workspace/entry/src/main/ets/pages/WebApp.ets
# → 2 处（亮色/深色各一条选择器）

# 3) 确认深色规则也声明了 backdrop-filter
sed -n '1164,1170p' ~/data/DSHM-deveco-workspace/entry/src/main/ets/pages/WebApp.ets

# 4) 产物晚于源码（本轮已满足：源 18:06 / 包 18:11）
stat -c '%y  %n' ~/data/DSHM-deveco-workspace/entry/src/main/ets/pages/WebApp.ets \
  /data/storage/el1/bundle/entry.hap
```

---

## 7. 门禁

| 门禁 | 结果 |
|---|---|
| `check-sidebar-shim-css` | ✅ rc=0 |
| `check-doc-index` | ✅ rc=0（编号文档全收录） |
| `check-doc-refs` | ✅ rc=0（引用落点全在界内） |
| `check-design-tokens` | ✅ rc=0（没有新增裸值） |

---

## 8. 一句话交接

**亮暗两档玻璃都已实测生效并正确随主题切换** —— 深色 `rgba(38, 44, 58, 0.82)`、
亮色 `rgba(214, 223, 240, 0.86)`，切换前后 `cols` / `rect` / `backdrop` 三者不变、
唯 `computedBg` 翻转，证据见 §4.1；`docs/284` §5.1/§5.2/§5.4 三项修法均已落实，
产物 18:11 晚于源码 18:06。

**唯一遗留**：探针 `dark` 字段用 `||` 判空串属性，导致亮暗两态**恒报 `none`**（不影响渲染，
但会误导后续排查）。改法是把 `||` 换成显式 `=== null` 判定，并区分 `empty` / `absent`。
