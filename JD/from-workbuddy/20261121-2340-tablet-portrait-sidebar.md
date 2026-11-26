# JD-036 平板/折叠屏竖屏侧栏按钮修复（并入 AGC 包）

- 提交方：WorkBuddy
- 接收方：DevEco（编译 AGC 包）
- 时间：2026-11-21 23:40
- 关联：JD-035（AGC 云调试包）；本单修复并入同一个 AGC 包

---

## 1. 反馈

单形态平板**竖屏**时，左侧边栏按钮不在了；转**横屏**才出现。折叠屏竖屏一并检查。

---

## 2. 根因（三处叠加）

`SIDEBAR_SHIM_JS` 的平板规则（`entry/src/main/ets/pages/WebApp.ets`）：

1. **平板几何全包在 `@media (min-width:1024px)`**：平板竖屏典型 736–950vp，媒体查询不命中 ⇒ 平板规则一条都不生效；
2. **手持抽屉规则用 `:not(.dshm-tablet)` 排除平板**：竖屏既不走平板常驻规则，也不走手机/折叠屏的抽屉规则 ⇒ 只剩官方 narrow/drawer 行为；
3. **收起态 opener 只改 `opacity/visibility/pointer-events`**：官方 narrow 态对 `button[data-sidebar-opener]` 是 `display:none`，不改 `display` 就仍然不可见。

横屏 ≥1024 命中平板规则（56px 轨 + opener 常显），所以「一横就出来」。

---

## 3. 修复（只改 Web shim CSS，ArkTS 逻辑不动）

### 3.1 平板「收起态 56px 轨」移出媒体查询

```css
html.dshm-tablet[data-dshm-sidebar="collapsed"]:not([data-dshm-right="open"]) .dshm-frame
  { grid-template-columns: 56px minmax(0,1fr) 0 !important }
html.dshm-tablet[data-dshm-sidebar="collapsed"] .dshm-sbcol
  { position:relative; ...; visibility:visible; width:auto; ... }
```

- 任何宽度都生效 ⇒ 竖屏收起时也保留 56px 轨道与官方 opener 入口；
- **展开态 280 仍只在 ≥1024**：竖屏展开交官方抽屉，避免主区被挤（保持 2026-11-18 结论）。

### 3.2 收起态 opener 补 `display`

```css
html[data-dshm-sidebar="collapsed"] button[data-sidebar-opener]
  { display:inline-flex !important; opacity:1 !important; visibility:visible !important; pointer-events:auto !important }
```

- 覆盖官方 narrow 态的 `display:none`；
- 手机 / 平板 / **折叠屏单屏**（判为 phone）收起态都命中。

### 3.3 折叠屏

| 形态 | 结论 |
|---|---|
| 折叠屏**单屏竖屏** | `platformForm()` 答 `phone` ⇒ 走 3.2 的全局收起态规则，**一并修复** |
| 折叠屏双屏/三屏 | 走桌面档（官方布局），预期正常；若真机仍不显示，需单独抓 `[dshm-sidebar]` 日志再查 |

---

## 4. 验证

| 项 | 结果 |
|---|---|
| `devecocli build --product default --build-mode debug` | **BUILD SUCCESSFUL** |
| `node tools/check-decor-button-mode.mjs` | **134/0 PASS**（对照臂 A–X 有效） |

---

## 5. 真机测点（DevEco / 用户）

1. **单形态平板竖屏**：侧栏收起时左上角按钮**可见**；点击可展开（抽屉式），再点收起；
2. 竖屏旋转到横屏、再转回：按钮始终在，状态不漂移；
3. 平板竖屏/横屏各做一次「收起 → 展开 → 收起」，无第二个按钮、无遮挡内容；
4. **折叠屏单屏竖屏**：同上；展开态下侧栏整幅显示、主区不被挤压；
5. 折叠屏展开（双屏/三屏）：侧栏与按钮正常（若异常，回传 `hilog | grep dshm-sidebar`）。

---

## 6. 边界

- 只改 `SIDEBAR_SHIM_JS` 的 CSS 拼接；不改 ArkTS、不改手机/PC 规则、不改 280/56 的横屏取值；
- 展开态竖屏仍交官方抽屉（不写死 280），避免「会话区侵入左栏」回归；
- 与 JD-035 的 AGC 包合并：编译时把本修复一并带入，包身份不变（`com.dshm.dshclient` / 1.1.8 / 1010019）。
