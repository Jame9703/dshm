# DevEco Studio 正式调试签名交接

| 项 | 内容 |
|---|---|
| 文档编号 | `docs/216` |
| 日期 | 2026-10-21 |
| 目标 | 在鸿蒙 PC 的 DevEco Studio 内直接 Run 正式 PC 工程 |
| 适用范围 | `com.dshm.dshclient` / tablet / 2in1 |

## 1. 当前结论

代码、release 构建、release 签名和 AGC `.app` 已经完成。日常开发不再使用
`hdc` 手工侧载，而是在 DevEco Studio 选择设备后直接点击 **Run**。

Run 必须使用 IDE 的 **debug 构建 + 设备绑定调试签名**。仓库里的
`.certs/release1012/*.p7b` 是 AGC release Profile，只用于发布，不用于 Run。

## 2. 固定身份

```text
Bundle                      = com.dshm.dshclient
AGC App ID / app-identifier = 6917614360926110054
本机现有 debug appId        = 6918740027110769940（仅 Run，不发布）
当前设备 UDID               = 20DB409AAB6F8C575BFACA92C23369205D01BD047447FC9A1DA36DC0631C7B7F
设备类型                    = 2in1
```

Profile 需要覆盖已批准 ACL：

```text
ohos.permission.CUSTOM_SANDBOX
ohos.permission.ALLOW_EXTERNAL_NATIVE_CODE
ohos.permission.FILE_ACCESS_PERSIST
```

`6918740027110769940` 不是 AGC 发布身份，但它是当前设备已安装 debug 包的本地身份。
为避免卸载和丢失 el2 数据，`product=default` 的 IDE Run 使用
`.certs/debug-local/` 中与已安装包同源的证书、私钥和 Profile；它只用于本机
Run / Debug，不能上传 AGC。AGC release 仍固定为 `6917614360926110054`。

## 3. 在当前鸿蒙 PC 上一次性完成

1. 用 DevEco Studio 打开当前工程根目录。
2. 等待 Sync；缺依赖时执行 `ohpm install --all`。
3. 确认 Product 为 `default`，Bundle 为 `com.dshm.dshclient`。
4. 当前 `build-profile.json5` 的 `default` product 已绑定 `debug` 签名配置：
   `.certs/debug-local/xiaobai.p12` + `DSHM-local-debug.p7b`。
5. Profile 已绑定当前 UDID，ACL 包含 `CUSTOM_SANDBOX`。
6. 选择当前鸿蒙 PC `MNTXM-24B`，直接点击 Run。

不需要再次生成调试 Profile，不需要手工 `hdc`，也不需要卸载应用。

## 4. 之后不再需要原开发端

调试身份就位后，以下操作全部在鸿蒙 PC 上完成：

- DevEco Run / Debug / 热重载；
- ArkTS 与 Native 编译；
- 使用 `.certs/debug-local/` 的既有 debug 私钥签 HAP；
- release `.app` 本地构建与签名；
- Profile 未过期且设备 UDID 不变时，跨版本复用同一调试身份。

只有以下情况需要 AGC 权限：

- 新增另一台设备 UDID；
- 上传 AGC、创建邀测版本或正式发布。

为此需要一次性把当前开发者账号或 Service Account 加入 AGC 应用
`6917614360926110054` 的团队。AGC 凭据只写本机 gitignored `.env`，不进入仓库。

## 5. 后续签名边界

当前工程已经用设备现有安装的同源调试身份完成 Run 配置。以后只有在更换设备、更换
调试证书或 AGC 要求重新绑定 Profile 时才需要更新 Profile。

release `.app` 继续使用 `.certs/release1012/` 和 AGC `6917614360926110054`
身份；本机 debug `6918740027110769940` 身份不能上传 AGC。

禁止：

- 使用 release Profile 做 Run；
- 使用 `com.dshm.dshmbeta` 或 `com.dshm.mobileclient` 的 Profile；
- 为让新签名装上而卸载应用或删除 el2 数据。

## 6. 点击 Run 后应检查

1. 应用以 `com.dshm.dshclient` 启动。
2. 无白屏，Host 在 `127.0.0.1` 就绪。
3. `CUSTOM_SANDBOX` 生效，随包 ELF 可执行。
4. 终端走原生 exec / PTY。
5. Host 报告 JIT 已启用。
6. 原会话、工作区、插件和凭据仍在。

