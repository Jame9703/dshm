# PC 设置页附加配色撤除

## 官方与壳层边界

当前配方核心中的官方 `dsh-client-ui-settings-general/src/client/SettingsRoot.tsx` 使用 portal 渲染设置面板，`SettingsRoot.module.css` 的遮罩取 `--dsw-alias-bg-mask-1`，面板取 `--dsw-alias-bg-layer-2`。官方遮罩从 `--dsh-frame-chrome-top` 以下开始，保留原生窗口条；没有让外部原生顶栏变暗的桥。

entry 壳此前另加了 `webModal`：网页探测设置/dialog 后通知 ArkUI，在 TopBar 上画固定40%黑罩。系统三键不在这层遮罩内。固定值也不等于官方浅色24%、深色50%的遮罩令牌。该额外层已撤除，相关侦测、桥、状态与注册一并清除。

entry 玻璃脚本此前还对设置dialog覆盖背景、模糊、阴影和圆角。现在只在PC桌面标记下排除设置面板及其内部dialog，恢复官方设置面板样式；普通平板和非设置dialog保留原有行为。

三键仍由系统绘制，沿用现有随实际DSH主题选择明暗的策略，未改窗口背景、主题映射、菜单材质或拖拽/避让。官方设置背景遮罩仍存在，因此本次不是将设置页后方强制变白。

## Beta 主题线索复核

用户提供的 Beta 二次诊断称 profile 第 831 行有 `ui-theme.preference: light`，并称 07:41:12 设置 mutate 后由 dark 切为 light。当前工作区源码 profile 与物化 core profile 均未检出 `ui-theme` 条目；本机可读的 Beta 日志归档实际早于该时间，无法复核所述 mutate。

官方 `ui-theme` 默认 preference 为 `system`。启动会将当前 preference 写入 `data-ds-theme-source`；随后主题桥按实际生效 light/dark 更新系统栏、窗口底色和三键模式。官方设置行 `setTheme()` 将用户选择持久化，scope adoption 再读取已接受的持久化 preference。因此若较新的现场 profile 或用户设置实际为 `light`，页面切浅色和装饰 `mode=light` 属预期配置结果，不能仅凭时间相邻改成 `dark` 或 `system`。现有旧归档中 `diag-decor-caps mode=light` 早于同次启动的 `diag-glass dark=true`，说明装饰诊断与网页主题曾暂时分离，但不是 07:41 事件的证据。

## 验证边界

entry/default 已成功编译，ArkTS快速检查无severity-1错误；lint实际检查1文件、零error。主题、桥、玻璃和About等七项专项通过，完整原序113项回归113/0、OK→BAD=0，受保护7文件执行前后摘要一致。选择器桩随后加强为识别参数、区分role与仅aria-modal节点，新增撤除门禁共七个负控制。完整回归证据由 `dist/acceptance/pc-settings-chrome-20261114/` 保存。

未进行设备UI验收，不能由离线结果承诺实际黑闪或像素表现已经消失。本次未重打核心、未重出Beta/AGC；此前交付的双包不包含这次改动。若要判定用户所述 preference 是否异常回写，仍需同一设备同一时间段的运行 profile、主题设置 mutate 前后值及对应 diag-glass/diag-decor 日志；不得以固定 preference 覆盖用户持久化选择。
