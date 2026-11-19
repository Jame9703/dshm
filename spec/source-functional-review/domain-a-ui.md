# A 双壳与交互（T003）

## 阅读及可达链

深读 `platform/src/main/ets/system/DeviceFacts.ets` 全文、`InputDevices.ets` 全文、`WindowChrome.ets` 全文；两壳 `pages/WebApp.ets` 的形态桥/侧栏分类与目录桥片段；phone 的返回及 Web 区域变化片段。定位实际核心 `dist/core/work/dsh-core-0.2.2-rc.2+dshm.1/node_modules/@deepseek-ai/dsh-client-ui-sidebar/lib/client.js`；其压缩长行仅定位，不冒称全文深审。

- 设备：`readDeviceFacts:158–194` → `nativeTerminalOnly`；UI 则由 WebApp 缓存 handheld/phone/foldable → `platformForm` 同步桥 → 注入脚本 `applyHandheld`。
- entry：`WebApp.ets:4233–4234` 回传 form 和 pcMode，`1262–1344` 分类；phone：`3912–3917` → `1210–1282`，采用 setFlag 对称挂摘。
- phone 返回：`5565–5579` 先查 Web 后退，再 `consumeWebBack:5603–5639`，网页返回白名单可消费，否则最小化。有 1200ms 兜底，不能只因异步桥就认定返回被吞。
- InputDevices 有逐设备异常隔离、总枚举失败 null、同函数 off；但是否被当前 Web 入口消费本轮未闭合，不把该工具模块当作键鼠已完整生效的证据。

## A-R1：entry 形态类挂摘不对称（P2 风险/待UI）

位置 `entry/src/main/ets/pages/WebApp.ets:1298–1337`。进入 desktop 分支会加 `dshm-desktop` / pcm 时加 `dshm-pc`，回 phone/tablet 分支只加 handheld/tablet，没有摘 desktop/pc；由原生 pcMode 翻转并不改变 form=tablet 的场景，key 仍会改变但不执行清理。

反证：entry 的 platformForm 对普通平板始终 tablet，因此单纯普通平板自由窗口并不必然进入 desktop 分支，不将“切自由窗再切回必坏”报为确认缺陷。phone 使用 setFlag 对称更新，不能类推同错。当前能否在同一 entry Web 文档里发生 form 分类跨越及残留类对应的实际 CSS 冲突尚未闭合，保留风险而非确认。

建议方向：按最终分类对所有互斥类对称清理；先补当前可达切换序列及实际 CSS 冲突证据。

## 边界

未验证：键盘焦点/IME、触控拖拽、多窗、折叠屏分屏实际视口、系统返回回调顺序、侧栏实际 DOM 交互/无障碍、状态栏真实颜色。DeviceFacts 的 readFoldSnapshot 使用默认 display 宽度而非窗口宽度（299–350），但是否在目标场景失配需要官方及真机，不以注释宣称来定缺陷。未得到 A 域确认缺陷，不等于 UI 正常。
