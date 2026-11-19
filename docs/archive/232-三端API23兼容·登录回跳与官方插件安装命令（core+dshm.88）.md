# 232 · 三端 API 23 兼容、登录回跳与官方插件安装命令（core+dshm.88）

> 日期：2026-10-24
>
> 范围：`com.dshm.dshclient` 的 PC/2in1、手机、平板三个 entry HAP，
> 共享 `hostruntime` HSP，以及插件安装与账号登录的端侧接线。
>
> 结果：`1.1.7 / 1010007 / +dshm.88` 的 release/debug 三端包已构建、
> 验签并覆盖安装到 PC 与手机；平板 release 包待 AGC 云调试。

## 1. API 兼容结论

`compatibleSdkVersion` 是 project `products[]` 的字段，不是单模块字段。
官方 project build-profile schema 原文说明它决定 HAP 的
`apiCompatibleVersion`。因此同一个 `.app` 里的三个 entry HAP 和一个共享
HSP 只能共享一个最低兼容值。

本轮校正为用户确认的移动端基线：

| 字段 | 值 | 产物读数 |
|---|---|---|
| `compatibleSdkVersion` | `6.1.0(23)` | `minAPIVersion=60100023` |
| `targetSdkVersion` | `26.0.0` | `targetAPIVersion=260000026` |
| `entry` / `phone` / `tablet` | 各自单一 deviceType | `2in1` / `phone` / `tablet` |
| `hostruntime` | 三端共享 | `phone/tablet/2in1` |

PC 仍是 API 26 设备，且 PC HAP 的 `deviceTypes` 仍只有 `2in1`；统一包的
最低兼容值为 23 不改变 PC 可安装设备面。若未来要求 PC 与移动端拥有不同的
最低 API，只能拆成不同 product / `.app`，不能在一个 product 内伪造模块级覆盖。

平板旋转回执已改为：

- API 26：`setPreferredOrientationWithResult()`，记录 APPLIED / IGNORED / PENDING；
- API 23–25：旧 `setPreferredOrientation()`，只如实记录“平台已受理”；
- 两条路径失败都退回系统默认朝向。

材质、系统右键菜单和 Agent Extension 属于可选增强；低版本不提供对应能力时
不得阻断主界面。最终代码在 API 23 兼容值下通过 ArkTS 编译；
本次没有 API 23 实体设备，因此实际 API 23 安装仍是后续设备验证项。

## 2. 账号登录完成页回跳

官方平台页面 `/dsh/authorized` 的当前源码行为已实读：

```js
const web = params.get('login_source') === 'web';
const open = () => window.location.assign('dsh://open');
if (web) window.close(); else if (!navigated) { navigated = true; open(); }
// “返回 DeepSeek Harness”按钮的 onClick 同样是 open()
```

DSHM 以 `login_source=desktop` 启动登录，但三个原生 HAP 此前都没有声明
`dsh://open`，所以浏览器跳转没有接收方。修复为同一套三端接线：

1. `EntryAbility.skills` 增加
   `viewData + entity.system.browsable + scheme=dsh, host=open`；
2. `onNewWant()` 识别 `dsh://open`；
3. 对复用主实例显式 `ensureWindowShown()`，恢复最小化/后台窗口。

设备验证使用不带 Ability 名的 Want，让系统按 manifest skill 解析：

```bash
hdc -t <target> shell aa start \
  -b com.dshm.dshclient \
  -A ohos.want.action.viewData \
  -e entity.system.browsable \
  -U dsh://open
```

PC `127.0.0.1:45595` 与手机 `62T0225B18039433` 都返回
`start ability successfully`，并在同一进程的 `onNewWant` 中记录：

```text
账号授权完成：收到 dsh://open，唤回主窗
```

## 3. 官方插件安装命令

设置页安装框历史上把输入原样写入 `.req`，Host 的安装器只认识裸 spec，
所以只有 npm 名或单个 GitHub 地址能工作。本轮新增
`hostcore/app/dshm-install-command.js`，它是**词法解析器，不调用 shell**。

支持：

```text
dsh plugin --profile <p> add <spec>
dsh plugin --profile <p> install <spec>
dsh plugin --profile <p> i <spec>
dsh --profile <p> plugin add|install|i <spec>
pnpm add|install|i <spec>
npm add|install|i <spec>
<spec>
```

同时支持：

- `--profile <name>` / `--profile=<name>`；
- `--dir <path>` / `--dir=<path>`，且目标必须位于
  `$DSH_HOME/profiles/` 内；
- `--registry <https-url>` / `--registry=<https-url>`；
- `--save-exact`；
- 常见无值安装 flag（`--no-audit`、`--no-fund`、`--ignore-scripts` 等）。

安全与语义边界：

- 一次只接受一个顶层安装目标；多个包名直接拒绝，不静默只装第一个；
- 拒绝 `;`、`|`、`&`、重定向、反引号和 `$()`，不把面板变成命令执行器；
- 拒绝相对 `--dir`、profile 路径穿越、HTTP registry、带凭据/query/hash
  的 registry、`--global` 与 `--save-dev`；
- `--save-exact` 让 profile dependency 记录解析后的精确版本；
- `--registry` 直接传给进程内安装器，不另造下载实现。

真机回路（手机）：

```text
请求：dsh plugin --profile ondevice add is-number@7.0.0 --save-exact
结果：ok:true，is-number@7.0.0，1 个包
profile dependency：7.0.0（精确值）
清理：同通道 removeSpec 成功，node_modules 与依赖记录均删除
```

## 4. 构建与签名

核心先升到 `0.2.1-rc.2+dshm.88`。首次 `pack-core` 的 npm 子进程仍以
`exit=null` 被宿主异常终止；在 `dist/core/work/...dshm.88` 手工执行同一
`npm install --os=openharmony --cpu=arm64 --ignore-scripts ...` 后，
以 `--skip-install --place-in-app` 完成物化。

| 项 | 值 |
|---|---|
| 应用 | `1.1.7 / 1010007` |
| 核心 | `0.2.1-rc.2+dshm.88` |
| 核心 zip | `99,345,799 B` |
| 核心 SHA-256 | `0d77e95a2619549b9ae30389e9e29f638ecc074cbbcc0631bd67f31e67bbd247` |
| release `.app` | `dist/release-test/DSHM-1.1.7-multihap-3platforms-20261024.app` |
| release 大小 | `482,559,268 B` |
| release SHA-256 | `65b67ad6d3592fbb5e14f5cb381e79a94acf3ffac91737259ab7d9f482a3ad00` |
| debug `.app` | `489,323,266 B` |
| debug SHA-256 | `4ae7994afce0e936f187f5ffc849985d7db5de79fd4354fb26d5ce09e8db37c2` |

release 与 debug `.app` 都通过 `hap-sign-tool verify-app`。release
Profile type=`release`、debug Profile type=`debug`，两者 app ID 都为
`6917614360926110054`。

核心单容器门禁确认 HSP 内只有：

```text
resources/resfile/dsh-core-0.2.1-rc.2+dshm.88-openharmony-arm64.zip
```

resfile 按 pack-core 的单容器规则只放 `.88`，避免同一 HSP 携带两份核心；
`dist/core/` 下旧的 `.84`–`.87` zip 继续保留用于回滚与审计。

## 5. 覆盖安装与设备读数

debug 侧载目录新增三个每设备目录：

```text
dist/sideload/DSHM-1.1.7-multihap-3platforms-debug-20261024/pc/
dist/sideload/DSHM-1.1.7-multihap-3platforms-debug-20261024/phone/
dist/sideload/DSHM-1.1.7-multihap-3platforms-debug-20261024/tablet/
```

`install -p` 一次只接受一个 entry HAP；直接传 `all/` 会返回
`9568287 install invalid number of entry hap`。

| 设备 | 覆盖安装结果 | 安装后 `bm dump` |
|---|---|---|
| PC `127.0.0.1:45595` | `install bundle successfully` | `1.1.7 / 1010007`，`entry + hostruntime`，min 23 / target 26 |
| 手机 `62T0225B18039433` | `install bundle successfully` | `1.1.7 / 1010007`，`phone + hostruntime`，min 23 / target 26 |

安装后执行 `aa force-stop` 再启动，仅用于退出旧进程，不卸载、不清理 el2。
两侧 Host 日志实读都切到 `dsh/cores/0.2.1-rc.2+dshm.88`；手机
`host-ready.json` 的 PID、启动时间和核心路径均为本次进程。

## 6. 回归

本轮通过：

- `check-dshm-installer.cjs`：88 passed（含 GitHub `&path:`、命令拒绝面与真实安装链路）
- `check-auth-return.mjs --self-test` / `check-auth-return.mjs`
- `check-pc-api26.mjs --self-test` / `check-pc-api26.mjs`（文件名保留，语义已改为 min23/target26）
- `check-permission-surface.mjs`
- `check-pc-only-surface.mjs --self-test` / `check-pc-only-surface.mjs`
- `check-edge-desktop-policy.mjs`
- `check-no-apk-surface.mjs`
- `check-store-readiness.mjs`
- `check-feature-wiring.mjs`
- `assert-cli-shim.mjs`
- `place-host-app.mjs` + `assert-resfile-sync.mjs`
- `check-resfile-core-zip.mjs`
- `check-core-openharmony-patches.mjs`：244 passed
- `assert-core-entrypoints.mjs`：3701 条入口全部可解析
- `check-native-closure.mjs`：entry 与共享 HSP 两边 libs 合并后 61 个库闭合

README 的 `check-resfile-core-zip`、签名验证与 `SHA256SUMS` 均有产物级复核。

## 7. 尚未完成

- 平板 release `.app` 的 AGC 云调试；
- API 23 实体设备安装与运行时回归（当前设备均为 API 26）；
- 真实账号在浏览器完成授权后的手工按钮点击验收；当前已用同 URI、真实
  manifest 解析和 `onNewWant` 日志验证完整接收链；
- AGC 邀请测试上传、绑定、提交与推送。
