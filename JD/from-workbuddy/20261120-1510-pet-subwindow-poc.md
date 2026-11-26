# 交接单：独立子窗桌宠 POC 编译与真机验证

- **ID**：JD-015
- **提交方**：WorkBuddy
- **接收方**：DevEco（编译 / 安装 / 真机取证）
- **日期**：2026-11-20 15:10
- **状态**：待编译 / 待测试
- **前置**：JD-014（主窗 POC）结论 Q2 FAIL —— 主窗容器不透明 + 主窗掩码 `1300004`；本单验证替代架构「宿主主窗 + 独立子窗」。

## 1. 要验证什么

只回答 6 个问题，全部通过后才接入主工程：

1. **宿主主窗能否移到屏幕外**（320×72 最小尺寸），不再出现方形容器卡片；
2. **独立子窗能否真透明 + 圆形掩码**（圆外透出桌面）；
3. **圆外点击能否穿透**（掩码 0 = 透明且不可交互）；
4. **父窗 topmost 能否让独立子窗跨应用置顶**；
5. **子窗能否用 `startMoving()` 拖动**；
6. **宿主失焦/后台 30s 后子窗是否仍在**（独立子窗「不跟随主窗前后台切换」）。

## 2. 源码与关键实现

| 项 | 值 |
|---|---|
| 工程 | `demo/pet-subwindow-poc/` |
| bundleName | `com.dshm.dshdemo`（复用本机 debug 签名，覆盖同名 demo） |
| deviceTypes | `["2in1"]` |
| supportWindowMode | `["floating"]` |
| 权限 | 仅 `ohos.permission.WINDOW_TOPMOST`（无 `SET_WINDOW_TRANSPARENT`） |
| 宿主主窗 | `resize(320,72)` + `moveWindowTo(-2000,-2000)` + 隐藏装饰/三键 + `setWindowTopmost(true)` |
| 子窗 | `createSubWindowWithOptions('PetSub', { decorEnabled:false, zLevelAboveParentLoosened:true })` + `setWindowBackgroundColor('#00000000')` + `setWindowMaskWithAlpha(圆形掩码)` |
| 页面 | `pages/Host`（黑底占位）、`pages/Pet`（圆形宠物 + 拖动 + 右键退出） |

关键文件：
- `demo/pet-subwindow-poc/entry/src/main/ets/entryability/EntryAbility.ets`
- `demo/pet-subwindow-poc/entry/src/main/ets/pages/Pet.ets`
- `demo/pet-subwindow-poc/entry/src/main/module.json5`

产物（WorkBuddy 侧已构建）：
- `demo/pet-subwindow-poc/build/outputs/default/pet-subwindow-poc-default-signed.app`
- size `55,898 B`，sha256 `271af1505ef8791cdbc0925f3446689ffea6a590860bb5defb19563635186f8a`
- HAP 清单：`deviceTypes=["2in1"]`、`supportWindowMode=["floating"]`、权限仅 `WINDOW_TOPMOST`

## 3. 编译安装

```sh
cd demo/pet-subwindow-poc
CODEBUDDY_SAFE_DELETE_ENABLED=0 devecocli build --product default
devecocli device list
devecocli run --skip-build
```

签名说明同 JD-014：`build-profile.json5` 指向本机 `default_demo_*.p7b`（bundle `com.dshm.dshdemo`）；如无该物料，请用 DevEco Studio 为本工程生成调试签名，bundle 必须与 profile 一致。

## 4. 取证清单（逐项留证）

| # | 操作 | 预期 | 关键读数 |
|---|---|---|---|
| 1 | 启动 | 右下角圆形宠物；宿主主窗不可见或仅极窄边缘 | `hilog PetSubPoc: host rect=...`；截图 |
| 2 | 切浏览器/微信 | 宠物仍最上层 | 截图（含聚焦窗口重叠区像素） |
| 3 | 点击宠物圆外桌面图标 | **穿透**：图标可选中/响应 | 录屏或前后截图 |
| 4 | 按住宠物拖动 | 子窗跟随移动 | 前后截图 + `drag` 日志 |
| 5 | 右键宠物 | 菜单可退出/记录状态 | 菜单截图 + 日志 |
| 6 | 宿主失焦/后台 30s | 宠物仍显示 | 截图 + `ps` |
| 7 | 退出 | 子窗/宿主一起消失 | 截图 |

`hilog` tag：`PetSubPoc`（domain `0xD002`）。重点：
- `host rect=` 的 left/top 是否为负值（被系统吸附回屏内会变成 0 或可见坐标）；
- `sub rect=` 是否在预期位置/尺寸；
- `setup failed` / `1300004` / `401` / `801`。

## 5. 已知边界与判读

- 掩码在**子窗**上应可用；若仍 `1300004`，说明当前系统实现与文档不符，需立即回调。
- 宿主主窗若无法移出屏幕，会留下 320×72 黑色块；请记录 `host rect`，不要把它当"透明失败"，这是父窗限制。
- 独立子窗不跟随父窗前后台，但**父窗销毁会一起销毁**；退出用右键菜单。
- 圆外穿透是掩码语义（0 不可交互），若实测仍拦截，请记录点击坐标与下层窗口响应。
- 本 POC 不包含插件协议与资源加载，只验证窗口形态。

## 6. 边界与红线

- 只改/只装 `demo/pet-subwindow-poc/`；不改主工程 `entry`/`phone` 的权限面、版本号、交付件。
- 不 `git commit` / `push`；不动 `signing/**`、`.certs/**`、`dist/**`。
- 安装会覆盖 `com.dshm.dshdemo` 应用。
- 失败如实记录错误码与 `host rect` / `sub rect`。

## 7. 完成后

结论写入 `JD/from-deveco/20261120-pet-subwindow-poc-result.md`：

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

并更新 `JD/STATUS.md`（JD-015）。
