# DevEco 执行提示词（JD-015 子窗桌宠 POC）

> 直接复制下面「提示词正文」给 DevEco。范围仅限 JD-015 的编译与真机验证；**PASS 后不要改主工程**，把结论回给 WorkBuddy。

---

## 提示词正文

你是 DevEco，负责编译、安装与真机取证。请先完整阅读：

- `JD/from-workbuddy/20261120-1510-pet-subwindow-poc.md`（JD-015 交接单）
- `JD/from-deveco/20261120-pet-float-poc-result.md`（JD-014 结论：主窗透明 FAIL）
- `demo/pet-subwindow-poc/README.md`

### 一、任务范围

只做 `demo/pet-subwindow-poc/` 的 PC/2in1 真机验证，回答 6 个问题：

1. 宿主主窗（320×72）移到屏幕外后，是否不再出现方形容器卡片；
2. 独立子窗是否真透明 + 圆形掩码（圆外透出桌面）；
3. 宠物圆外点击是否穿透（掩码 0 = 透明且不可交互）；
4. 父窗 `setWindowTopmost(true)` 能否让独立子窗跨应用置顶；
5. 子窗能否用 `startMoving()` 拖动；
6. 宿主失焦/后台 30s 后，子窗是否仍在（独立子窗「不跟随主窗前后台切换」）。

**不要改主工程** `entry` / `phone` 的权限面、版本号、交付件；不要 `git commit` / `push`；不要动 `signing/**`、`.certs/**`、`dist/**`。

### 二、编译与安装

```sh
cd demo/pet-subwindow-poc
CODEBUDDY_SAFE_DELETE_ENABLED=0 devecocli build --product default
devecocli device list
devecocli run --skip-build
```

- bundleName 固定 `com.dshm.dshdemo`，会覆盖本机同名 demo 应用；不要改 bundle。
- `build-profile.json5` 指向本机 `default_demo_*.p7b`。若你的环境没有该 profile，用 DevEco Studio 为本工程生成调试签名，**bundle 必须仍为 `com.dshm.dshdemo`**。
- 若 `devecocli device list` 为空：用 IDE 设备面板连接，或 `hdc tconn 127.0.0.1:45595` 后重试。

### 三、6 项验证与取证

| # | 操作 | 预期 | 必须记录 |
|---|---|---|---|
| 1 | 启动 | 右下角圆形宠物；宿主主窗不可见或仅极窄边缘 | `hilog PetSubPoc: host rect=left,top,w,h`；截图 |
| 2 | 切浏览器/微信 | 宠物仍在最上层 | 两张截图（含重叠区像素） |
| 3 | 点击宠物圆外桌面图标 | **穿透**：图标可选中/响应 | 录屏或前后截图 |
| 4 | 按住宠物拖动 | 子窗跟随移动 | 前后截图 + `startMoving` 日志 |
| 5 | 右键宠物 | 菜单含「退出桌宠 / 记录窗口状态」 | 菜单截图 + `windowStatus` 日志 |
| 6 | 宿主失焦/后台 30s | 宠物仍显示 | 30s 后截图 + `ps` |

另外记录：
- `hilog PetSubPoc: sub rect=left,top,w,h`；
- 任何 `setup failed` / `401` / `801` / `1300004` 的完整原文；
- 宿主主窗若被系统吸附回屏内，记录实际 `host rect`，并明确写“父窗未离屏”，不要把它当成“子窗透明失败”。

证据目录：`JD/from-deveco/20261120-pet-subwindow-evidence/`，附 `SHA256SUMS.txt`。

### 四、判定与回填

结论写入 `JD/from-deveco/20261120-pet-subwindow-poc-result.md`，格式：

```
JD-015 结论：PASS / PARTIAL / FAIL
产物：路径 + sha256
设备：型号 / 系统版本
host rect：left,top,w,h（是否在屏内）
sub rect：left,top,w,h
1 启动：截图
2 置顶：截图/像素
3 圆外穿透：结果
4 拖动：结果
5 菜单：结果
6 后台存活：结果
异常码：401/801/1300004 原文
```

并更新 `JD/STATUS.md` 的 JD-015 行。

### 五、判定口径

- **PASS**：6 项全过，且圆外点击确实穿透；
- **PARTIAL**：窗口能显示、拖动/置顶通过，但圆外点击不穿透或宿主主窗无法离屏；
- **FAIL**：子窗掩码仍 `1300004`、子窗无法透明、或独立子窗不显示。

**PASS 后不要继续改主工程**：把结论、`host rect`/`sub rect`、穿透结果回给 WorkBuddy；主工程接入（PetAbility、PetStateWatcher、权限 18→19）由 WorkBuddy 在下一轮完成。

若 FAIL：保留日志与截图，明确失败项与错误码，不要用“能力受限”笼统带过。

### 六、回复格式

`JD-015 结论：PASS/PARTIAL/FAIL + 产物 sha256 + host/sub rect + 6 项结果 + 异常码原文`
