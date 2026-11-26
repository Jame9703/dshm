# JD-014 结论：PC/2in1 悬浮桌宠 POC 编译与真机验证

- **接收**：[`from-workbuddy/20261120-1212-pet-float-poc.md`](../from-workbuddy/20261120-1212-pet-float-poc.md)（2026-11-20 12:12）
- **执行**：DevEco，2026-11-20 12:30–14:46，本机即测试机
- **总判定：PARTIAL** —— 编译/安装/8 项取证全完成；6 问中 5 问 PASS，**Q2「主窗容器透明」FAIL**，且它是桌宠视觉形态（圆形无底）的决定性否定。

## 产物与设备

| 项 | 值 |
|---|---|
| 现行产物 | `demo/pet-float-poc/entry/build/default/outputs/default/entry-default-signed.hap`，sha256 `fda2fc8c4fa67f153e73c88ee8b5dce08823cc61e10289d5fe8ef5b83584e45b`（DevEco 重编重签·迭代 2 探针版） |
| 过程件 | WorkBuddy 迭代 0 `.app` sha `59bebfdd…`（交接单）；DevEco 首编 `.app` sha `587eef86…`；迭代 1 HAP sha `ade79670…` |
| 设备 | HUAWEI MateBook 14（MNTXM-24B，2in1）/ OpenHarmony-7.0.0.109 / API 26 / 2880×1920（密度 1.75，逻辑像素=物理/1.75）/ `127.0.0.1:45595` |
| 安装 | `hdc install -r` 覆盖成功（bundle `com.dshm.dshdemo`），启动正常 |
| 取证库 | [`20261120-pet-poc-evidence/`](20261120-pet-poc-evidence/)（19 文件 14 MB，含 `SHA256SUMS.txt`） |

## 6 问逐项

| # | 问题 | 结论 | 关键证据 |
|---|---|---|---|
| 1 | 自由窗口主窗 + `setWindowTopmost(true)` 跨应用置顶 | **PASS** | `windowStatus=4`（FLOATING）`freeWindow=true`；a11y z 序 [0]；聚焦浏览器与宠物重叠区采样 3/3 为宠物黄 `#FFE08A` ⇒ 聚焦窗口也压不住置顶宠物 |
| 2 | 主窗容器透明 + 去阴影 | **FAIL** | 表面恒为不透明容器色：亮 `#DEEBF7`=(222,235,247)、暗 `#333333`=(51,51,51)、失焦 (64,64,64)；页面底透明只露出容器色；掩码主窗 1300004。去阴影本身 OK（边缘扫描无暗带） |
| 3 | 隐藏标题栏后 `startMoving()` 拖动 | **PASS** | 工具注入 swipe：窗口精确位移 (-727,-252)；用户手动鼠标拖动 150+ 行 touch Move 流（真人实测） |
| 4 | 透明区域点击仍被拦截（预期拦截） | **PASS（如预期）** | 表面 6 点采样点击全部被应用消费（touch 日志命中）；窗口边缘 ~8-16 px 为 WM 缩放边框（拖拽实测 576→676）；四角为缩放手柄；真穿透仅存在于窗口 rect 之外 |
| 5 | 右键菜单：记录窗口状态 / 退出 | **PASS** | `14:45:18.534 windowStatus=4 freeWindow=true source=menu` → `14:45:28.849 onBackground` → 进程消失 + a11y 0 节点 + 原位置像素变为下层窗口内容 |
| 6 | 失焦/后台后动画与进程继续 | **PASS** | PID 46148 全程稳定（13:37–14:45 约 68 分钟零重启）；失焦 5+ 分钟渲染不中断（切 inactive 容器色）；30 s 计时检查 PASS；`onBackground` 仅真实退出时触发 |

## 8 项取证清单

| # | 操作 | 结果 | 留证 |
|---|---|---|---|
| 1 | 启动 POC | 右下角圆形宠物，无标题栏/三键 | `02-launch.jpeg` |
| 2 | 切其他应用 | 微信之上仍最上层；聚焦浏览器之上仍渲染在上 | `06-topmost.jpeg`、`08-topmost-vs-focused.jpeg` |
| 3 | 四角与边缘 | 四角=不透明容器色；边缘无阴影暗带 | `04a/04b/04c-*.jpeg` + 像素读数 |
| 4 | 按住拖动 | 窗口跟随；自动/手动两路验证 | `03-drag.jpeg`、`05-drag2.jpeg` |
| 5 | 点击四角透明区 | 全部拦截（预期）；边缘拖拽触发 WM 缩放 | `04a/b/c` + hilog touch 段 |
| 6 | 右键→记录窗口状态 | 日志原文见下 | `menu3.json`、`pre_exit.json` |
| 7 | 右键→退出 | 窗口关闭、进程退出 | `12-post-exit.jpeg`、`post_exit.json` |
| 8 | 失焦/后台 30 s | 进程/渲染均存活 | `09-after30s.jpeg` |

## 关键读数

### 透明链归因（Q2 FAIL）

1. `setWindowContainerColor('#00000000')`（8 位 ARGB）→ **401**（Parameter error；decor 隐藏前后均拒）
2. `setWindowContainerColor('#000000')`（6 位）→ 成功，但为不透明黑
3. 页面底透明 + 容器色默认 → 表面显示**容器色**而非桌面（三种容器色读数见上表 Q2）
4. 探针 `#00FF0000`（alpha=00）→ 视觉无变化，证实 bg 的 alpha 通道被读取但不改变不透明表面
5. `setWindowMaskWithAlpha(四角=0 掩码)` → **1300004**（原文见下），主窗不支持，与交接单 §5 预判一致

### 输入模型（Q4 细化）

- a11y bounds 内：应用全消费（表面即拦截面）
- bounds 外 ~8-16 px：WM 缩放边框（消费输入，拖动实测改窗口尺寸 576→676）
- 四角：缩放手柄
- 主窗方案不存在"圆外穿透"；穿透诉求只能换窗口形态

### 存活性（Q6）

- 失焦不隐藏、不中断渲染；用户按 Home 后窗口仍在
- 68 分钟进程零重启；30 s 计时检查通过

## 日志与异常码原文

| 时间/场景 | 原文（hilog tag `PetPoc`，domain 0xD001） |
|---|---|
| 14:45:18.534 | `windowStatus=4 freeWindow=true source=menu`（菜单「记录窗口状态」，WindowStatus 枚举 FLOATING=4） |
| 14:45:28.849 | `onBackground`（菜单「退出桌宠」触发，随后进程退出） |
| 启动 +6 s 探针 | `probe bgColor#00FF0000` 成功、视觉无变化（alpha 读取证实） |
| 启动 +18 s 探针 | `step fail: probe setWindowMaskWithAlpha(corners=0) code=1300004 Only subwindows and float windows are supported` |
| 迭代 1 | `step fail: containerColor#00000000 code=401`（Parameter error；6 位 `#000000` 同位通过） |
| 未出现 | 201 / 801（`WINDOW_TOPMOST`、`SET_WINDOW_TRANSPARENT` 均 normal 授予，链路无权限错误） |

> 迭代 1/2 的启动 step 序列已被 hilog 分钟级滚出缓冲，原文以执行时直读记录为准；菜单/退出/触摸段在落盘时仍在缓冲（`PetPoc` 共 156+ 行）。

## 架构结论（回填 JD-010 方案复核）

- **主窗自由窗口做桌宠：功能可行（置顶/拖动/菜单/存活全过），视觉不可行（无法透明，必带方形容器卡片底）**
- 圆形无底形态必须换窗口形态：ArkUI **子窗/全局悬浮窗**（`setWindowMaskWithAlpha` 文档口径即子窗+悬浮窗）
- 与 JD-010 复核"主窗不可逐像素穿透"结论一致，并追加更强否定：**主窗连透明都做不到**

## 工具链发现（自动化盲区，已记 `docs/PITFALLS.md` §3.10）

- `uitest uiInput`：无鼠标右键注入（仅触摸/按键/文本）
- `uitest dumpLayout -i`：不含 ArkUI 弹窗/上下文菜单层（菜单开着也 dump 不出菜单节点，只能靠用户确认 + 屏幕像素）
- `verify_ui`：服务端 400（structured-outputs 后端冲突）×2，与 JD-011 同源，本会话不可用
- `/system/bin/uinput`：有 `-M` 鼠标注入（含右键 `-c 1`）但仅相对位移，用户正在用机时不可靠
- `hidumper -s MultimodalInput -a '-c'`：可读光标 `lastPhysicalX/Y`
- 本轮右键菜单验证最终采用「人工右键 + 系统侧四重取证（hilog/ps/a11y/像素）」闭环，可作为后续桌面 UI 验证范式

## 源码改动披露（仅 `demo/pet-float-poc/`，取证必需）

- `entryability/EntryAbility.ets`：逐步 `tryStep`（单步失败不中断链路）+ 三个延时探针（bg `#00FF0000` @6 s、恢复 @12 s、掩码 @18 s）；迭代 2 隔离容器色变量
- `pages/Pet.ets`：onTouch 打点（逻辑像素）、onAppear 自动 `logWindowStatus`、菜单「记录窗口状态」带 `source=menu`
- 窗口链与菜单项逻辑未变；主工程零改动；未提交任何 git 变更

## 现场还原与副作用

- POC 已按测试流程经「退出桌宠」正常退出（进程/窗口消失，非强杀）
- 副作用：13:33 `aa start` 微信 BrowserAbility 出现过瞬时 sceneboard 全屏与一个微信小窗（用户应用自身行为，未动用户数据）
- 设备 `/data/local/tmp/petpoc/` 为取证截图/布局缓存，无害可清
- 用户桌面其余窗口未受影响

## 判定

**JD-014：PARTIAL** —— Q1/Q3/Q4/Q5/Q6 PASS；Q2 FAIL（主窗不透明 + 掩码 1300004），导致主窗路线不能满足"圆形无底桌宠"的视觉要求，建议 JD-010 方案按「子窗/悬浮窗」修正后另行 POC。
