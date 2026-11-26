# Beta 测试反馈提示词（dsh-pet 桌面宿主）

> 直接复制给测试同学/测试设备。目标：只测「dsh-pet 插件自己的桌宠能否在 DSHM Beta 桌面上显示并交互」，不是测 DSHM 自绘宠物。
> 2026-11-20 23:40 修订：吸收《DSHM-dsh-pet-诊断与修复手册》反馈，补 display 前置警告、素材 200 体检、VP9 判据；研判见 `20261120-2340-dsh-pet-beta-feedback-triage.md`。

> ⚠️ **复测前必读（最容易踩的坑）**：诊断手册为了让「网页端」显示，把宠物 `display` 改成了 `web`。**Beta 桌面宿主只在 `display=desktop` 或 `both` 时才启动**（`EntryAbility`/`PetAbility` 配置门控）。若沿用 `web` 配置，桌面桌宠不会启动、也不会有黑框——这是预期行为，不是缺陷。**测 Beta 桌面桌宠必须先把 `display` 改回 `desktop`**（两端都要才用 `both`，但会双份）。
> 同时注意：手册的「桌面悬浮做不到」结论针对 dsh-pet 原生 Electron 路线；Beta 走的是 ArkTS 透明子窗（即手册 §4 的方案 B），两者不是一回事。

## 提示词正文

请按下面步骤测试 DSHM Beta 的桌宠宿主，并按模板反馈。测试前确认：

- 设备：鸿蒙 PC / 2in1（平板暂不支持桌面桌宠）
- 包：`com.dshm.dshmbeta`，`1.1.8 / 1010019`，路径 `dist/beta/DSHM-beta-1.1.8-1010019-20261120T150928/`
- 插件：`dsh-pet@0.4.9`（先装插件，再重启 DSHM）
- 插件配置：`$DSH_HOME/dsh-pet/main-config.jsonc` 中至少一只宠物 `display` 为 **`desktop`**（或 `both`）；**切勿为 `web`**，`web` 会让 Beta 桌面宿主不启动
- 复测前置：若设备当前是手册修复后的 `web`，先改回 `desktop` 再完全退出 DSHM 重启：

  ```bash
  TOKEN=$(python3 -c "import json;print(json.load(open('/data/storage/el2/base/haps/entry/files/dsh/home/host-ready.json'))['token'])")
  curl -s -H 'Content-Type: application/json' -d '{"id":"main","display":"desktop"}' \
    "http://127.0.0.1:3121/dsh-pet-7340/pet-display?token=$TOKEN"
  curl -s "http://127.0.0.1:3121/dsh-pet-7340/config?token=$TOKEN" \
    | python3 -c "import sys,json;p=json.load(sys.stdin)['main']['pets'][0];print(p['id'],p['display'],p['size'])"
  ```
- 素材体检：装插件后跑 `python3 ~/Download/dsh-pet-fix-assets.py --check`，并确认 `.../dsh-pet-7340/thumb/main/待机呼吸休闲.webm?token=$TOKEN` 返回 **200**（141 个素材名曾被污染，坏名会导致只出气泡不出小人）

### 一、安装阶段

1. 安装 Beta（覆盖安装，不要卸载）。
2. 启动一次，确认主界面正常。
3. 安装 `dsh-pet@0.4.9` 插件（记录安装命令与完整报错，尤其“首次安装失败”的原文）。
4. 打开「设置 → 桌宠」确认能看到宠物设置；点一次「保存」。
5. 完全退出 DSHM 再启动。

### 二、桌面显示

| # | 操作 | 记录 |
|---|---|---|
| 1 | 启动后观察桌面 | 是否出现插件自己的宠物（不是 DSHM 画的圆）；有没有多出 `dsh-pet-host` 黑框 |
| 2 | 右键宠物 → 「在桌面显示」 | 多久出现；黑框是否消失 |
| 3 | 右键宠物 → 「不在桌面显示」 | 宠物是否消失；黑框是否残留 |
| 4 | 插件设为仅网页显示（`display=web`）后重启 | 桌面是否完全干净（不应有黑框，且 Beta 子窗不启动属预期） |
| 5 | 桌面只出气泡/空白时刷新页面并开 F12 | 搜 `[dsh-pet]`：`素材加载失败 404` ⇒ 素材名又坏（跑 `--fix`）；`MEDIA_ERR_SRC_NOT_SUPPORTED` ⇒ VP9-alpha 疑不被 ArkWeb 支持（记录，不自行判定） |

### 三、交互

| # | 操作 | 记录 |
|---|---|---|
| 1 | 鼠标按住宠物拖 300–500px | 窗口是否 1:1 跟随（不是只走 1/3） |
| 2 | 触摸拖拽 | 是否可用 |
| 3 | 点击宠物身体外透明区 | 是否穿透到桌面/下层窗口 |
| 4 | 右键宠物 | 插件菜单是否完整、不被屏幕边缘裁切 |
| 5 | 切到浏览器/微信 | 宠物是否仍在最上层 |
| 6 | 空闲 10s 后再点/拖宠物 | 是否还能交互（不应永久穿透） |
| 7 | 宿主最小化/切后台 30s | 宠物是否还在；恢复后是否正常 |

### 四、与 DSHM 联动

| # | 操作 | 记录 |
|---|---|---|
| 1 | 发一条普通对话 | 宠物是否有工作状态/动画变化 |
| 2 | 触发一次长任务/子代理 | 宠物是否显示忙/完成/出错 |
| 3 | 开启碎碎念 | 是否按周期冒泡（文字/语音） |
| 4 | 查询余额/查看待办 | 菜单动作是否生效；无反应时记录错误 |
| 5 | 插件内聊天 | 是否能正常对话、记忆是否保留 |

### 五、稳定性

| # | 操作 | 记录 |
|---|---|---|
| 1 | 连续运行 10 分钟 | 宠物动画是否卡死、窗口是否漂移 |
| 2 | 重启 DSHM | 桌宠是否自动恢复 |
| 3 | 停用/卸载 dsh-pet | 桌宠与黑框是否都消失 |
| 4 | 同时开多个窗口/应用 | 桌宠是否仍置顶、是否抢焦点 |

### 六、必须附带的证据

1. 设备型号 + 系统版本 + API；
2. Beta 版本（1010019）与 dsh-pet 版本（0.4.9）；
3. 插件安装的完整报错文本（如有）；
4. 每个失败项的截图/录屏（含时间）；
5. 日志：

```sh
hilog | grep -E "dsh-pet-host|entry/pet"
```

重点看：
- `[dsh-pet-host] /dsh-pet-native 已注册，pluginRoot=...`（应命中 `profiles/ondevice/node_modules/dsh-pet`）
- `entry/pet: pet subwindow ready: ...`
- `无 desktop/both 宠物，PetAbility 退出`（出现此行 ⇒ `display` 没改回 `desktop`）
- `/dsh-pet-native 不可用（插件路径未找到/路由未注册）`（出现此行 ⇒ 插件路径/路由未注册，带回 `pluginRoot`）
- `setBounds move rejected` / `setInteractive rejected`
- `desktop 宠物已关闭，PetAbility 退出`（右键「不在桌面显示」后应出现）

6. `$DSH_HOME/dsh-pet/main-config.jsonc` 中相关宠物的 `display/size` 两项（**务必附 `display` 实际值**，用于区分「配置没改回」与「代码没启动」）；
7. 素材体检结果（`--check` 输出 + 上述 webm 的 HTTP 码）；
8. 插件安装首次报错原文与 `pluginRoot` 日志（用于排查安装流程是否再次污染素材名）。

### 七、反馈模板（直接填）

```
设备/系统/API：
Beta 版本：
dsh-pet 版本：
插件安装：成功 / 失败（报错原文：）
复测前 display 实际值：desktop / both / web（若为 web，是否已改回：）
素材体检：__ 个待修复；待机呼吸休闲.webm HTTP __
设置页：有 / 无；保存后：
启动桌面：宠物出现 / 黑框 / 都没有
右键在桌面显示：用时 __s；结果：
右键不在桌面显示：结果：
鼠标拖动：1:1 / 比例 __；触摸：
外点穿透：可以 / 不可以
右键菜单：完整 / 裁切（截图为证）
置顶：是 / 否
空闲后恢复：可以 / 不可以
DSHM 联动：工作状态 / 碎碎念 / 余额 / 待办（分别填）
10 分钟稳定性：
重启恢复：
日志关键行：
截图/录屏：
```

### 八、判定口径

- **PASS**：桌面显示、在/不在桌面切换、拖动、穿透、菜单、置顶、联动全部可用，且无黑框；
- **PARTIAL**：宠物能显示，但拖动/穿透/联动有一项异常；
- **FAIL**：只有黑框、宠物不出现、或启动即崩溃。

> 当前 Beta 是 **dsh-pet 适配器**；其他宠物插件若要上桌面，需要按 DSHM 桌面宠物协议接入，不能把“只有 dsh-pet 能显示”当成所有插件都已支持。
