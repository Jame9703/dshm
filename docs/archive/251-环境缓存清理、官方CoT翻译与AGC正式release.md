# 环境缓存清理、官方 CoT 翻译与 AGC 正式 release

> 日期：2026-10-24
>
> 版本：`1.1.6 / 1010007`
>
> 核心：`0.2.1-rc.3+dshm.94`

## 1. 环境清理

只删除可再生构建缓存和中间产物：

- 根 `build/`
- `entry|phone|platform|connection|appstate|dshcompat|hostruntime/build/`
- `hostruntime/.cxx/`
- `.hvigor/`
- `.idea/.deveco/arkts/.cache/`
- `dist/_update_build.log`

清理前约 `17.9 GiB`，清理后约 `10 GiB`，释放约 `8 GiB`。保留：

- `.certs/`、`signing/`
- `dist/core/work/`
- `dist/node/libnode.so.137.orig`
- `third_party/sherpa_onnx-1.13.3.har.bak`
- 现有交付与验收包

## 2. 侧栏最终边界

- 平板：左侧 FAB 与右侧侧栏按钮同时常驻。
- 手机/直板机/折叠单屏：右栏打开时隐藏左侧 FAB，避免覆盖式右栏重叠；右栏关闭后恢复。
- PC/2in1/Edge：继续使用原生顶栏，隐藏 Web 内重复左侧入口。

`check-sidebar-shim-css.mjs --self-test` 17 项正例、9 个变异全红；
`check-handheld-sidebar-recover.mjs` 14 个变异全红。

## 3. 官方思考过程翻译

根因不是翻译服务不可用，而是官方可选 bundle
`@deepseek-ai/dsh-experimental-cot-translation-bundle` 未进入端侧
`dsh.profile.bundles`。

现在 profile 顺序为：

1. `@deepseek-ai/dsh-base`
2. `@deepseek-ai/dsh-web-app`
3. `@deepseek-ai/dsh-experimental-cot-translation-bundle`

官方 bundle patch 插入 `translator` 与 `cot-translation`，默认使用免密 Bing、
目标语言跟随 UI；Bing 端点实测 HTTP 200。核心清单实读两条均为
`disabled=false / PURE_JS`。新增 `tools/check-cot-translation.mjs`，带
3 个变异对照臂并接入 CI。

## 4. 代码审核修复

- `place-toolchain.mjs` 原先只认 Windows `binary-sign-tool.jar`，在鸿蒙 CLT
  原生 `binary-sign-tool` 下无法给 git/python 归档签名。现统一为“原生工具优先、
  jar 回退”。
- `sign-tar-elf.py` 改为接收 signer spec，同时兼容原生工具和 jar。
- `check-libnode-io-uring.mjs` 跟随公共 HSP 结构，从 `hostruntime/libs` 读取
  `libnode`，并检查 `hostruntime/.../NodeRuntime.ets`。
- `check-mobile-upgrade-migration.mjs` 现在也会找 `build/outputs/release` 的最新 APP。

工具链实签：python `10/10`、git 闭包全部 ELF 签名成功；工具链签名门禁 PASS。

## 5. 正式 release

构建命令：

```bash
node "$DEVECO_HOME/hvigor/bin/hvigorw.js" clean --mode project --no-daemon
node "$DEVECO_HOME/hvigor/bin/hvigorw.js" assembleApp \
  --mode project -p product=release -p buildMode=release \
  --no-daemon --no-incremental
```

最终包：

- `dist/release-test/DSHM-1.1.6-1010007-core94-sidebar-cot-translation-release-20261024.app`
- 大小：`481,033,485 B`
- SHA-256：`c268c37d737bfea7fe65d1ed865b7fd659fac2cfbdc86d8cc83ee6308a8b6143`

产物实读：

- Bundle `com.dshm.dshclient`，App ID `6917614360926110054`；
- release Profile、`type=release`、7 条 allowed ACL；
- `entry`（tablet/2in1）18 条权限，`phone` 10 条权限；
- 两个 entry 均为 `buildMode=release / debug=false`；
- 公共 HSP 同时面向 phone/tablet/2in1，携带 `libsystem.so`；
- HSP 只携带 `.94` 核心容器；
- `hap-sign-tool verify-app`：`verify-app success`；
- APK 面 0 命中。
