# 迁移到 DevEco Studio 与鸿蒙 PC

## 目标

把当前 beta 工作区整理为可由 DevEco Studio 直接打开、同步、签名、编译和调试的
可移植工程。迁移不依赖当前 Windows 机器的 IDE 缓存，也不复制本机签名物料。

## 迁移边界

迁移包必须包含：

- `AppScope/`、`entry/`、`connection/`、`appstate/`、`dshcompat/`、`platform/`、
  `hostruntime/` 的完整源码和资源。
- `entry/libs/arm64-v8a/` 下的运行期原生库。
- `entry/src/main/cpp/node-headers/`。
- `entry/src/main/resources/resfile/` 下的核心包、工具链和 VM 资产。
- `third_party/`、`hostcore/`、`hostkit/`、`tools/`、`docs/`。
- 当前 `.git` 与全部未提交、未跟踪文件。

迁移包不包含：

- `dist/`（当前约 10 GB，属于构建、截图、证据和临时交付物）。
- 各级 `build/`、`entry/.cxx/`、`.hvigor/`、`.idea/`、`oh_modules/`。
- `tmp-gp/` 和本机临时文件。
- 根目录 `build-profile.json5`、`build-profile.local.json5`，因为其中含
  当前 Windows 机器绑定的签名路径和明文口令。

## 生成迁移包

在仓库根目录执行：

```powershell
.\tools\export-deveco-workspace.ps1
```

脚本会在 `dist/migration/` 下生成：

- `DSHM-deveco-workspace-<timestamp>/`：可检查的展开工作区。
- `DSHM-deveco-workspace-<timestamp>.zip`：复制到目标机器的交付件。
- `DSHM-deveco-workspace-<timestamp>.sha256`：压缩包校验值。
- `robocopy-<timestamp>.log`：复制范围与错误码。

## 在目标机器恢复

1. 解压到短路径，路径中避免空格、中文和同步盘目录。
2. 在工程根目录把 `build-profile.portable.json5` 复制为 `build-profile.json5`。
3. 用 DevEco Studio 打开工程根目录，不打开其父目录。
4. 等待 Sync 完成；若依赖缺失，在工程根目录执行 `ohpm install --all`。
5. 进入 `File > Project Structure > Signing Configs`，勾选自动签名：
   - Product：`default`
   - Bundle：`com.dshm.dshmbeta`
6. 先用 `entry:default` 构建 HAP，再运行门禁与真机验证。

不要从旧机器复制 `C:\Users\Sol\.ohos` 或任何 `.p12`、`.cer`、`.p7b` 私钥物料。
新机器必须由 DevEco 生成自己的调试签名 profile。

## HarmonyOS PC 注意事项

- DevEco Studio 的“鸿蒙电脑版”有独立文档入口，工程结构仍按 Stage 模型打开。
- 模拟器是否可用取决于目标宿主和镜像架构。官方文档明确：Windows on Arm
  不支持当前模拟器（错误码 `00801020`），不能用 ARM Windows 规避 x86 模拟器
  ABI 问题。
- 首选验证顺序是：目标机器本地 HAP 构建 -> 真机覆盖安装 -> 平板横竖屏与
  手机/折叠屏回归 -> VM 分档回归。

## 首次编译后检查

```powershell
node tools/check-arkts-entry.mjs
node tools/check-permission-surface.mjs
node tools/check-no-apk-surface.mjs
node tools/check-vm-memory-tier.mjs
```

需要核心树时，先确认 `entry/src/main/resources/resfile/*.zip` 已随迁移包到位。
需要设备时，只允许覆盖安装，禁止卸载或删除应用数据。

## 安全提醒

- 迁移包包含当前未提交改动与 `.git`，不要在目标机器执行 `git clean` 或
  `git reset --hard`。
- `entry/libs`、`resfile`、`node-headers` 和 `third_party` 是编译输入，不是缓存。
- `dist` 未迁移是有意为之；历史截图、日志和侧载包需要时从旧机器按需单独复制。
