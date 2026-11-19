# 交接单：编译出包任务（1.1.8 / 1010018，核心 rc.5）

- **ID**：JD-011
- **提交方**：WorkBuddy
- **接收方**：DevEco（编译 / 出包 / 真机验证）
- **日期**：2026-11-19 11:40
- **状态**：待 DevEco 执行

## 1. 本次要产出

1. **AGC 包**：`com.dshm.dshclient`，`1.1.8 / 1010018`，核心 `0.2.2-rc.5+dshm.1`，用于上传重提审核。
2. **（可选）Beta 包**：本地/邀测验证用。

## 2. 源码当前状态（自上次出包以来的全部改动）

| # | 变更 | 状态 |
|---|---|---|
| 1 | 核心同步 `0.2.2-rc.4 → 0.2.2-rc.5`；容器已重打并放入 resfile（`sha256 61749b16…`，单容器） | 已完成 |
| 2 | 版本 `versionCode 1010018` / `versionName 1.1.8` | 已完成 |
| 3 | `ACCESS_USER_FULL_DISK`：reason 改为"仅 PC/2in1 本地工作区"，`usedScene.when=inuse`；**权限条数不变**（entry 18 / phone 9） | 已完成 |
| 4 | guest VM：2 vCPU、内存 512/1024 MiB、TCG 128/512 MiB | 已完成 |
| 5 | 平板系统标题栏：三键缩小（保留缩放/分屏） | 已完成 |
| 6 | 平板竖屏 `<1024` 交官方抽屉（既有修复） | 已在源码 |
| 7 | 插件安装器测试夹具修复（仅测试脚本，不影响产物） | 已完成 |
| 8 | 隐私协议内容更新（AGC 平台限制，控制台处理） | **不在编译范围** |
| 9 | dsh-pet 桌宠方案 | **暂缓，不在本包** |

## 3. 编译步骤

```sh
# 0) 校验核心容器（应为 rc.5 / 单容器）
node tools/check-resfile-core-zip.mjs
node tools/assert-resfile-sync.mjs

# 1) 编译（双 product）
devecocli build --product default
devecocli build --product phone

# 2) 出 AGC 包
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-agc.mjs

# 3) 可选：出 Beta
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-beta.mjs --combined-app
```

> 若 `check-resfile-core-zip` 报容器非 rc.5，先跑
> `CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/pack-core.mjs --skip-install --place-in-app`。

## 4. 必跑门禁

```sh
node tools/check-permission-surface.mjs          # entry 18 / phone 9，reason 无孤儿
node tools/check-vm-bash.mjs                     # 376/376
node tools/check-vm-memory-tier.mjs              # 512/1024/128/512
node tools/check-sidebar-shim-css.mjs            # 32/0
node tools/check-window-mode.mjs                 # 27/0
node tools/check-decor-button-mode.mjs           # 130/0
node tools/check-foldable-sidebar.mjs
node tools/check-dshm-installer.cjs              # 54/0
node tools/check-core-openharmony-patches.mjs    # 255/0
node tools/check-brand-surface.mjs               # 110/0
node tools/check-store-readiness.mjs
node tools/check-doc-index.mjs && node tools/check-doc-refs.mjs
# 全量
python3 dist/acceptance/gen-full-yml-gates.py dist/acceptance/$(date +%Y%m%d)-full-gates.txt
```

## 5. 产物核验（任一项不符即失败）

- `pack.info`：`bundleName=com.dshm.dshclient`、`versionName=1.1.8`、`versionCode=1010018`；
- entry `deviceTypes=[tablet,2in1]`、phone `[phone]`、hostruntime 三端；
- 权限：entry 18 / phone 9；
- HSP 内核心容器**恰好 1 份**且为 `dsh-core-0.2.2-rc.5+dshm.1-*.zip`；
- `hap-sign-tool verify-app` 通过。

## 6. 真机验证（重点）

1. **2in1**：覆盖安装、启动，确认 `dsh/cores/0.2.2-rc.5+dshm.1` 落盘。
2. **平板竖屏**（MatePad Pro 11 / API 24）：左侧功能区文字完整、不挤压主区。
3. **自由窗口**：三键变小；四边缩放、分屏入口仍在。
4. **插件**：安装 / 更新 / 更新检测各走一遍。
5. 首次启动因核心换代需解包，属预期（数十秒）。

## 7. 已知项（非阻塞）

- `check-core-openharmony-patches.mjs --self-test` 有 **1 例**（koffi 平台别名 junction）不合格；本体 255/0 绿，请编译时确认 koffi 原生加载正常。
- AGC 上有版本仍为 `1.1.8 / 1010017`（`releaseState=1` 驳回），新包需上传重提。

## 8. 完成后

- 结论写入 `JD/from-deveco/20261119-rc5-1010018-build-result.md`；
- 更新 `JD/STATUS.md`（JD-011 → 完成/阻塞）；
- 回复格式：`JD-011 结论：PASS/FAIL + 产物路径 + 门禁结果`。
