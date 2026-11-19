# 246 · Edge / Pro Max 双左侧栏入口去重（原生顶栏优先）

> **结论已被 `docs/247` 替代（2026-10-24 用户侧载复验）**：
> “原生顶栏可见就隐藏 Web 入口”范围过宽，会让 Edge 只剩顶栏按钮而左侧栏保持收起。
> 最终分档与修复以 `docs/247` 为准。

> 日期：2026-10-24
>
> 应用：`1.1.6 / 1010007`
>
> 核心：`0.2.1-rc.3+dshm.93`

## 1. 现象

MatePad Edge 与 MatePad Pro Max 同时出现两个左侧栏入口：

- 原生自绘顶栏左上角的侧栏按钮；
- 官方 Web UI 内的侧栏按钮或页面浮动入口。

普通 PC、平板和手机不要求统一隐藏 Web 入口；只有原生顶栏实际显示时才去重。

## 2. 根因

旧实现按 `dshm-desktop` / `dshm-pc` 形态类推断是否隐藏官方按钮，并且额外在
`tagLayout()` 里写 `toggle.style.display = 'none'`。这两条都不是顶栏可见性的真源：

- Edge 的 `desktopForced`、Pro Max 的设备类型与 Web 形态类可能落在不同分支；
- 原生顶栏只由 `shouldShowAppTopBar(rawType, desktopForced, landscape)` 决定；
- React 重建侧栏节点后，内联隐藏可能残留，无法随顶栏显隐恢复。

## 3. 修复

原生侧新增同步桥：

```ts
'nativeSidebarVisible': (): boolean => this.shouldShowTopBar()
```

该方法与原生 `if (this.shouldShowTopBar()) { this.TopBar() }` 共用同一判据。
Web 垫片每 300ms 同步一次：

```text
shouldShowTopBar() → nativeSidebarVisible()
  → html[data-dshm-native-topbar="1"]
```

CSS 在属性为 `1` 时同时隐藏：

- 官方「收起侧边栏 / 打开侧边栏」按钮（中英文两种 aria-label）；
- `#dshm-sidebar-fab` 浮动入口。

桥缺席或调用异常时写入 `0`，保持 fail-open：宁可短暂看到入口，也不会把唯一入口
藏死。官方按钮仍保留在 DOM 中，`findToggle()`、`stateOf()` 和程序化点击继续可用。

## 4. 门禁

已通过：

- `node tools/check-sidebar-shim-css.mjs`：11/0；
- `node tools/check-sidebar-shim-css.mjs --self-test`：4 个变异体全部判红；
- `node tools/check-feature-wiring.mjs`；
- `node tools/check-pc-api26.mjs` 与 `--self-test`；
- `node tools/check-permission-surface.mjs` 与 `--self-test`；
- `node tools/check-pc-only-surface.mjs`；
- `node tools/check-edge-desktop-policy.mjs`；
- `node tools/check-internal-undici.mjs`；
- `node tools/check-memory-guard.mjs`；
- `node tools/check-decor-button-mode.mjs`；
- `node tools/assert-resfile-sync.mjs`；
- `node tools/check-resfile-core-zip.mjs`；
- `node tools/check-doc-refs.mjs`。

## 5. 产物

修复后的 AGC 正式签名 release：

```text
dist/release-test/DSHM-1.1.6-1010007-core93-sidebarfix-release-20261024.app
size    460,635,211 B
sha256  efc40be9c5f1c331902b97b655ebe9b64a2e74a47e2a86c99f754c36736b62e9
```

修复后的 DSHM Beta 合包：

```text
dist/beta/DSHM-beta-1.1.6-1010007-core93-sidebarfix-combined/
  DSHM-beta-1.1.6-1010007-combined-debug.app
size    465,948,314 B
sha256  7105483b4ecd0b1dd710ccd45c33cc01476fb7588cdfe18c60204417c40ff04c
```

两个 `.app` 的 `hap-sign-tool verify-app` 均成功。当前环境没有可用 `hdc`
设备目标，因此本轮的 Edge / Pro Max 可见性验收由用户侧载完成。

## 6. 验收重点

1. Edge / Pro Max 横屏且原生顶栏显示时，只保留顶栏左侧按钮；
2. 顶栏因竖屏、分屏或窗口状态消失时，Web 侧入口能自动恢复；
3. 普通平板与手机原有入口不变；
4. 点击剩余入口仍能正常展开 / 收起官方侧栏；
5. 旋转、切到其他会话、打开设置面板后不出现重复或入口消失。
