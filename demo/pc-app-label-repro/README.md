# 平板「PC 应用」分类最小复现 Demo

用途：向鸿蒙工程师复现一个现象——**平板（单形态设备）上安装的应用仍被系统显示为「PC 应用」，分屏与悬浮窗（小窗）入口不可用**。

本 demo **不含业务代码**：仅一个入口 Ability + 一个诊断页。唯一变量是 `entry/src/main/module.json5` 的 `deviceTypes` 声明。

## 1. 复现变量

| 项 | 变体 A（复现） | 变体 B（对照） |
|---|---|---|
| `module.deviceTypes` | `["tablet", "2in1"]` | `["tablet"]` |
| `abilities.EntryAbility.supportWindowMode` | **未声明**（缺省 ⇒ `["fullscreen","split","floating"]`） | 同左 |
| 页面逻辑 | 完全相同 | 完全相同 |

官方规则（《智慧多窗简介》→ 适配注意事项）：

- `deviceTypes` **包含 `2in1` 且不包含 `phone`** ⇒ 系统判定为 **PC 应用**；
- **在 Tablet 上运行的 PC 应用，不支持悬浮窗**；
- 分屏触发方式为手势：应用全屏时从屏幕底部上滑至左上方热区。

因此变体 A 命中 PC 应用判定，变体 B 不命中。`supportWindowMode` 在两侧都缺省，以排除该字段的干扰。

## 2. 构建

工程使用 HarmonyOS Stage 模型，targetSdk 26，compatibleSdk 6.1.0(23)。

1. 用 DevEco Studio 打开本目录，自动生成默认调试签名（本仓库**不内置任何个人签名材料**）。
2. 或命令行：先为本工程配置可用的 `signingConfigs`，再执行：

```sh
devecocli build --product default
```

产物：`entry/build/default/outputs/default/entry-default.hap`。

切换变体：

```sh
python3 tools/switch-variant.py A   # deviceTypes = ["tablet","2in1"]，复现
python3 tools/switch-variant.py B   # deviceTypes = ["tablet"]，对照
```

每次切换后重新构建。**两个变体不要同时安装在同一台设备上**（同为 entry HAP，会覆盖）。

## 3. 真机取证步骤（平板）

1. 安装变体 A，冷启动。页面顶部显示 `deviceTypes = ["tablet", "2in1"]` 与 `supportWindowMode 未声明`。
2. **查看 PC 应用角标**：上滑进入最近任务，观察本应用任务卡片是否带「PC 应用」标识。
3. **分屏**：应用全屏时，从屏幕底部上滑至左上方热区，再选择另一个支持分屏的应用。
   - 记录页面上的 `windowStatus` 是否变为 `5 SPLIT_SCREEN`；
   - 记录窗口宽度是否约为屏幕宽度的一半。
4. **小窗/悬浮窗**：从最近任务、Dock 或多窗手势尝试「悬浮窗」，记录是否不可用。
5. 卸载变体 A，安装变体 B，重复第 2–4 步。

## 4. 预期结果

| 观察项 | 变体 A（含 2in1） | 变体 B（仅 tablet） |
|---|---|---|
| 最近任务角标 | 显示「PC 应用」 | 不显示 |
| 悬浮窗 / 小窗 | 不支持（官方规则） | 应可用 |
| 分屏（手势） | 请实测记录是否可用 | 请实测记录是否可用 |
| `supportWindowMode` | 缺省，默认含 split/floating | 缺省，默认含 split/floating |

结论判定：**若 A 与 B 只有 `deviceTypes` 不同，而角标/小窗行为不同，即可确认根因是 PC 应用分类，而非 `supportWindowMode` 配置**。

## 5. 与真实工程的对应

主工程 `DSHM` 的 `entry/src/main/module.json5` 同样声明：

```
"deviceTypes": ["tablet", "2in1"]
```

且 `abilities.EntryAbility` 无 `supportWindowMode` 字段。已构建签名包内 HAP 的 `module.json` 解析结果一致（全部 ability 的 `supportWindowMode` 为 ABSENT）。因此本 demo 的变量设置与真实包完全一致。

## 6. 注意事项

- 本 demo 不涉及权限、签名、核心容器，不与主工程共享构建配置。
- 请勿把两个变体同时安装在同一设备；取证时先卸载再安装。
- 若需要使用 `devecocli` 命令行构建，请自行补充本机 `signingConfigs`（交付包中刻意留空）。
