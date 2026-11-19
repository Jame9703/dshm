# 186 · 新增功能代码审核与双端回归（核心 `+dshm.72`）

> 2026-10-17。范围：上一个 AGC 件 `1.1.3 / core .56` 之后的新增与更新功能，
> 明确排除 A2A。PC `86E0226429000417` 与手机 `62T0225B18039433` 均覆盖安装验证。

## 1. 审核发现与修复

### 1.1 卡片四档 token 全 0（P0）

真机现象：余额正常，四档 token 始终为 `0`。

根因：`FormBindingData` 跨进程会把数据序列化为字符串，而卡片侧
`@LocalStorageProp` 仍声明为 `number`；数字字段回落到默认值 0。

修法：

- `buildCardBinding()` 统一把四档 token 转成十进制字符串；
- 卡片 UI 改为 `string` 接收，再显式 `Number()` 后绘图；
- 0 / 非法值画 `0%`，正数才保留 4% 最小可见宽度。

PC 重新添加卡片后，无障碍树实测四档值为
`136.0w / 31.4w / 143.8w / 143.8w`，用户确认显示正常。

### 1.2 卡片点击直达会话失败（P1）

真机返回 `session-not-found`。原脚本优先找 `[data-session-id]`，但上游实际稳定
锚点是 `[data-row-key="session:<id>"]`。

修法：

- 优先按 upstream `data-row-key` 精确选会话；
- 手持档抽屉收起时先展开，轮询至会话行出现后点击；
- 标题只做包含匹配兜底，不依赖哈希类名；
- 点中后收起手机抽屉。

PC 返回 `clicked-row-key`；手机返回 `opening-drawer` 后实测点击成功并回到目标会话。

### 1.3 卡片更新失败被误记成功（P1）

旧 watcher 在发起 `updateForm` 前就记录全局 `lastRaw`，失败后同一内容不再重试，
且异常被空 catch 吞掉。

修法：

- 改为按 `formId` 记录“已成功推送”的版本；
- 只有 Promise resolve 才记成功；失败下一拍重试；
- 失败写 hilog，成功也留可读日志。

真机日志：

```text
DSHM-CARD: 准备更新卡片 forms=1
DSHM-CARD: 卡片更新成功 formId=1652041098
```

### 1.4 浏览器工具错误面

修复三处：

- `browser_text` 的 script / CDP 两条路径从 4k 恢复到 20k；
- `browser_click` / `browser_type` 的扩展内 `{ok:false}` 不再被工具层包装成成功；
- 单标签窗口最小化后轮询 `chrome.windows.get` 确认，失败如实返回。

扩展升级为 `0.11.0 / dshm-host-bridge-11`，v11 目录已在 PC/手机共享区部署并做 sha256 双匹配。

### 1.5 浏览器自动化改为 PC-only

用户明确：手机没有扩展能力且没有海泰浏览器，移动端不管。

宿主编译期注入 `DSHM_DEVICE_FORM`：

- PC / 2in1：`desktop`；
- 手机：`phone`；
- 平板：`tablet`。

Host 与插件双层 gate：

- 只有 `desktop` 注册 Browser Bridge、`/dshm-open-link` 和 `browser_*`；
- 手机/平板即使插件被加载，也不会注册工具。

手机真机日志：

```text
[dshm-tool-browser] 不注册浏览器工具：当前形态=phone（仅 PC / 2in1）
```

PC 浏览器 v11 实测：

- `/dshm-browser/status`：`clients=1 / 0.11.0`；
- `navigate`：`load=complete / via=cdp-pagenavigate`；
- `tabs`：返回百度与扩展页；
- `get_text`：返回百度首页正文。

## 2. 门禁

主门禁 **32/32 PASS**，另补核心树与专项门禁：

| 门禁 | 读数 |
|---|---|
| 四形态布局 | 768/0 |
| 手持返回 | 40/0 + 5 臂 |
| 平板/三键窗口壳 | 86/0 + A–P |
| 卡片 | 35/0 + 12 臂 |
| 浏览器自动关闭 / PC-only | 26/0 + 10 臂 |
| 外开桥 | 22/0 + 6 臂 |
| VM bash | 396/396 |
| 核心补丁 | 233/0（29 处注入 + 1 撤除守卫） |
| 插件启用 | 自带行 4/4 |
| 核心入口 | 3,698/3,698 可解析 |
| 权限 | 恒 8 条 |
| APK 面 | 0 文件 / 0 目录 / 0 归档条目 |

`compat-drift`：rc.2 端点 144/144，无漂移。

## 3. 双端覆盖安装

| 设备 | 结果 |
|---|---|
| PC 2in1 | 核心 `.72` 启动；`links=10 size=3440` 不变；会话/插件/账户接口正常 |
| 手机 | 核心 `.72` 启动；`links=11 size=3440` 不变；快捷方式和直达会话正常 |

双端最近日志无 `DSHM host fatal`、插件未激活、`DUPLICATE_BACKEND`、
`SIGABRT/SIGSYS/SIGILL/SIGSEGV`、`tcg_region_init` 或 OOM。

`update-device.ps1` 在 PC 仍会按其既有 debug-exec 判据报 `EPERM/缺` 红项；
这是 release/应用域执行边界，不是 Host 启动失败。同轮 HTTP/API、字节码和端侧功能均正常。

## 4. 边界

- 浏览器自动化只承诺 PC；手机/平板不再展示 `browser_*`。
- A2A 按用户口径不在本轮范围。
- 平板当前未连接，平板三键/顶栏的最终截图仍待平板真机。

**未 commit / 未 push。**
