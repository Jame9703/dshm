# 238 · Codex 子进程环境与文件管理直达（core+dshm.90 · 1.1.6 r6）

> 日期：2026-10-24
>
> 版本：`1.1.6 / 1010006`，不升应用版本号。
>
> 核心：`0.2.1-rc.2+dshm.90`。

## 1. Codex 子智能体环境

### 1.1 根因

`dsh-subagent-codex` 启动 brew 的原生 Codex 时，旧 DSHM 补丁只把 `spec.env`
传给子进程，丢掉了 Host 的完整环境。结果是 Codex 本身能启动，但它内部执行
`python`、`pip`、`git`、`rg` 时看不到 DSHM 的沙箱工具包装器。

### 1.2 修法

`hostcore/app/dshm-installer.js` 的 Codex 启动环境改为：

1. 先继承 `process.env`；
2. 再用插件 `spec.env` 覆盖；
3. 明确 `CODEX_HOME`；
4. 把 `DSHM_SANDBOX_HOME/bin` 固定放到 `PATH` 最前；
5. 保留 CA 环境。

边界：

- PC / 2in1 上，原生 Codex 内部按命令名调用
  `python/python3/pip3/git/rg` 时能命中 DSHM 包装器；
- 手机上的 Codex 仍是 PC 能力，不承诺原生 Codex 直接复用手机宿主 Python；
- DSHM 自己的 `python` 工具在三端走内嵌 CPython worker，与 Codex PATH 是两条链。

`tools/check-dshm-installer.cjs` 增加继承 Host 环境与 PATH 最前置的断言。

## 2. 文件管理直达

### 2.1 官方 API 结论

HarmonyOS 没有公开的“让文件管理器定位任意路径”Want 契约：

- `viewData` 的语义是打开文件；
- PreviewKit 是预览窗；
- File Manager Service Kit 没有公开任意路径定位接口。

可用的公开接口是：

```ts
options.defaultFilePathUri = uri;
options.maxSelectNumber = 1;
options.selectMode = picker.DocumentSelectMode.FILE;
new picker.DocumentViewPicker(context).select(options);
```

SDK 事实：

- `DocumentSelectOptions.defaultFilePathUri` 自 API 10 起；
- `DocumentSelectMode.FILE` 自 API 11 起；
- 空 `defaultFilePathUri` 才回到“最近打开”；
- 当前工程最低 API 23，三端都能编译。

因此按钮文案表达为“文件管理”，实际行为是“调起系统文件选择/文件管理界面，并从
当前文件 URI 的位置打开”。不伪装成私有文件管理器深链。

### 2.2 接线

- `platform/FilePreview.ets` 新增 `openFileLocation()`；
- `platform/Index.ets` 导出；
- `entry/phone/tablet WebApp.ets` 把桥加入同一个
  `__DSHM_BRIDGES__` 对象和 `methodList`；
- `dshm-office-system-preview` 在文档预览动作区增加“文件管理”；
- 只对 `~/` 下的用户可见路径显示；
- 含 `.` / `..` 点段的路径不显示；
- 应用沙箱私有路径不伪装成文件管理可浏览位置；
- 调用结果写 `diag-file-location`。

### 2.3 门禁

新增 `tools/check-file-location.mjs`：

- 主体检查 `defaultFilePathUri`、三端桥、`methodList` 和用户目录限制；
- 变异 1：删 `defaultFilePathUri` 必须判红；
- 变异 2：放宽用户可见路径必须判红；
- 变异 3：`methodList` 漏掉新桥必须判红。

## 3. 核心与构建

核心树内的 Office 预览插件的属于随包内容，因此核心从 `.89` 升到 `.90`。
因 `npm install` 再次被宿主以 `exit=null` 中断，而 `.89/.90` 锁文件逐字一致，
本轮复用 `.89/node_modules`，随后由打包器重新裁剪、注入补丁并签名。

读数：

| 项 | 值 |
|---|---|
| core zip | `dist/core/dsh-core-0.2.1-rc.2+dshm.90-openharmony-arm64.zip` |
| core size | `99,343,872 B` |
| core SHA-256 | `e95b85a0f1520ce4e3d6a8bb653e3fe11dd035111519ddcb1639a0807fbf628b` |
| release APP | `dist/release-test/DSHM-1.1.6-multihap-3platforms-20261024-r6.app` |
| release size | `482,617,365 B` |
| release SHA-256 | `ad38f29909643b095251a747450a21e281fa14831ff0cf22c0533d9ce396c9ac` |
| debug APP | `dist/sideload/DSHM-1.1.6-multihap-3platforms-debug-20261024-r6.app` |
| debug size | `489,464,660 B` |
| debug SHA-256 | `86004fabeed9688832a1cae8fa829951e7ece00c04d5880f0ee50af241e8f6ef` |

release/debug `.app` 均通过 `hap-sign-tool verify-app`。三端 HAP 实读：

- `versionName=1.1.6`、`versionCode=1010006`；
- compatible API 23、target API 26；
- release 为 `buildMode=release / debug=false`；
- deviceTypes 分别为 `2in1 / phone / tablet`；
- HSP 内只有一份 `.90` 核心容器。

### 3.1 MatePad Edge 安装包

MatePad Edge 的系统原始类型是 `tablet`，desktop 只是应用内形态策略。本地调试
必须使用单个 tablet entry：

```text
dist/sideload/DSHM-1.1.6-multihap-3platforms-debug-20261024-r6/edge/
```

该目录只有 `tablet-default-signed.hap` 与
`hostruntime-default-signed.hsp`。也可使用压缩包：

```text
dist/sideload/DSHM-1.1.6-MatePad-Edge-tablet-debug-r6.zip
SHA-256 7693fd90189353a62dd8809b498c0d84163a7032a45307134be2207deeee7f52
```

`all/` 或三端 `.app` 一次给设备安装器三个 entry HAP，会返回
`9568287 install invalid number of entry hap`。这不是应用崩溃，也不是 Edge
不兼容。

**但这不是 Edge PC 应用的正式修复**：官方要求 Edge PC 兼容 HAP 同时声明
`tablet + 2in1`。只安装 tablet HAP 会缺少 PC 权限面，也不能满足 AGC PC 应用
分发。正确的包结构调整见
[`239-MatePad-Edge-PC应用识别与多HAP结构结论（1.1.6-r6）.md`](239-MatePad-Edge-PC应用识别与多HAP结构结论（1.1.6-r6）.md)。

## 4. 门禁

本轮已通过：

- `check-dshm-installer.cjs`：88/88；
- `check-plugin-render-arity.mjs`：11 个插件、2 组对照臂；
- `check-feature-wiring.mjs`；
- `check-file-location.mjs`：主体与 3 个变异；
- `check-core-openharmony-patches.mjs`：244/244；
- `check-resfile-core-zip.mjs`；
- `assert-resfile-sync.mjs`；
- `check-permission-surface.mjs` 与 self-test；
- `check-pc-api26.mjs` 与 self-test；
- `check-no-apk-surface.mjs` 与 self-test；
- `check-parity.mjs`；
- `check-sidebar-shim-css.mjs --self-test`；
- `check-handheld-sidebar-recover.mjs`。

## 5. 手机覆盖安装

设备 `62T0225B18039433` 用普通 `hdc install -r -p .../phone` 覆盖安装，
未卸载、未删除 el2 数据。

安装前后 `dsh/home` 均为 `368 KB / 16 files`。启动日志确认：

```text
BOOT_10_ENV_READY core=.../dsh/cores/0.2.1-rc.2+dshm.90
SERVER-LISTENING 127.0.0.1:3120
python 桥自检通过：print(1+1)=2
```

人工点击系统文件管理界面的最终交互仍需在预览一个用户目录文件后复验；本轮没有
把静态门禁替代成“已真机点过”。

## 6. 参考

- File Picker：
  <https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-file-picker>
- 远程控制原生化评审见
  [`237-手机遥控平板与PC实施方案（鸿蒙原生优先·评审稿）.md`](237-手机遥控平板与PC实施方案（鸿蒙原生优先·评审稿）.md)
