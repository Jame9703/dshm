# JD-038 结论：平板/折叠屏竖屏侧栏修复（并入 AGC 1010020 重建）

- **接收**：[`from-workbuddy/20261121-2340-tablet-portrait-sidebar.md`](../from-workbuddy/20261121-2340-tablet-portrait-sidebar.md)（自标 JD-036；与看板既有 JD-036「全盘权限 reason」重号，按提交时间顺延为 **JD-038**）
- **执行**：DevEco，2026-11-21 23:45–23:50
- **总判定**：修复已并入 AGC 包，构建/门禁/包体核验通过；**版本保持 1.1.8 / 1010020**（用户上一轮明确升到 1010020；交接单写的 1010019 已按用户指令覆盖）。

## 1. 修复复核（只改 Web shim CSS）

`entry/src/main/ets/pages/WebApp.ets` 的 `SIDEBAR_SHIM_JS`：

- 平板「收起态 56px 轨」移出 `@media (min-width:1024px)` ⇒ 竖屏也保留轨道与官方 opener；
- 收起态 opener 显式 `display:inline-flex !important`（覆盖官方 narrow 的 `display:none`）；
- 展开态 280 仍只在 ≥1024 生效（竖屏展开交官方抽屉，不挤主区）。
- ArkTS/手机/PC 规则未动；包内 `entry` HAP 的 `modules.abc` 已检索到新规则
  `button[data-sidebar-opener]{display:inline-flex !important;opacity:1 …}`。

## 2. 门禁（两处门禁按“新行为”更新）

```sh
node tools/check-sidebar-shim-css.mjs            # PASS 32/0
node tools/check-sidebar-shim-css.mjs --self-test# 21 个变异全部判红
node tools/check-feature-wiring.mjs              # ✅ 全部功能接线都在
node tools/check-decor-button-mode.mjs           # 第一组 9/0、第二组 134/0
node tools/check-permission-surface.mjs          # entry 19 / phone 9
python3 dist/acceptance/rerun-gates.py …         # 133/0（dist/acceptance/20261121-full-gates-jd038.txt）
```

- `check-sidebar-shim-css`：原断言「收起态只调透明度/可见性、不动 display」是针对旧实现；
  本轮按产品要求必须显式覆盖官方 `display:none`，断言改为要求
  `display:inline-flex !important`（仍禁止 `display:none`），自检 M13/M14/M15 同步。
- `check-feature-wiring`：接线串同步为 `...{display:inline-flex !important;opacity:1...`。

## 3. AGC 产物

| 项 | 值 |
|---|---|
| 文件 | `dist/release-test/dshm-1.1.8-1010020-dshm.1-AGC-invite-20261121T154503.app` |
| 大小 | 663,707,866 B |
| sha256 | `6a08e132fb7610eb05c7e0e8468d4320ad7019012ff0aa90afad76fc864b7859`（与同名 `.sha256` 一致） |
| 验签 | `hap-sign-tool verify-app` success |
| pack.info | `com.dshm.dshclient` / **1.1.8 / 1010020**；entry=tablet,2in1（含 PetAbility）、phone=phone、hostruntime=三端 |
| 权限面 | entry 19 / phone 9 |
| 发布 Profile | type=release、app_gallery、bundle/AppID 正确；allowed-acls **8 条** |
| 宿主 JS | HSP `resources/resfile/resources/app/main.js` 含 `deferRegister` 5 处 |
| 核心 | HSP 内 `dsh-core-0.2.2-rc.5+dshm.1-…zip` 恰好 1 份 |

> 本包是 **1010020 的重建**（上一包 `…T145804` 不含平板竖屏修复）；AGC 控制台请用**本包**（1010020）。

## 4. 待用户真机（交接单 §5）

1. 单形态平板竖屏：侧栏收起时左上角按钮可见，点击展开/收起；
2. 竖屏↔横屏往返，按钮始终在、状态不漂移；
3. 收起→展开→收起无第二颗按钮、不遮挡内容；
4. 折叠屏单屏竖屏同上；折叠展开（双屏/三屏）侧栏与按钮正常（异常回传 `hilog | grep dshm-sidebar`）。

## 5. 边界

- 未上传 AGC、未提交审核；release 包不可本地侧载。
- 未改版本号（保持用户指定的 1.1.8 / 1010020）；未改核心版本；未改 ArkTS/业务逻辑。
