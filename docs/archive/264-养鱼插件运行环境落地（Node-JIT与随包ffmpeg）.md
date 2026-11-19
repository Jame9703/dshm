# 264 · 养鱼插件运行环境落地（Node JIT 与随包 ffmpeg）

> 日期：2026-10-25
>
> 输入：`~/test/dsh-bili-whale-养鱼-缺口盘点与落地方案.md`
>
> 范围：只补 DSHM 公共运行环境，不内置 `dsh-bili-whale`，不修改插件源码。

## 1. 结论

养鱼插件缺的不是单个 `node` 路径，而是两类可由 DSHM 统一提供的能力：

| 能力 | 修复 |
|---|---|
| 插件及 Agent bash 调用的独立 `node` | 随包 `node-cli`，复用 `libnode.so.137`；子进程使用 JIT，Host 主进程仍保持 `--jitless` |
| 抽帧所需 `ffmpeg/ffprobe` | 构建期从 Harmonybrew ffmpeg 9.0.1 采集动态库闭包并自签名，放入 PC `entry` HAP；运行期仅在 2in1 落到 APP 沙箱 PATH |
| Host `fetch` 的多 Set-Cookie 标准面 | 为 `DshmHeaders` 补 `getSetCookie()`，修复养鱼扫码确认后的登录保存 |

插件仍由用户从“设置 → 插件”自行安装。APP 只提供环境。

## 1.1 Host Fetch：getSetCookie

养鱼扫码登录在手机确认后调用：

```js
response.headers.getSetCookie()
```

Host 的 jitless fetch 垫片原先把多个 `Set-Cookie` 合并进 `get()`，却没有
`getSetCookie()`，导致真实响应进入 `TypeError` 并被插件显示为“登录未保存”。

现已补齐：

- `getSetCookie()` 返回逐条字符串数组；
- `get('set-cookie')` 保持旧的逗号合并兼容行为；
- `new DshmHeaders(existing)` 复制时保留逐条 cookie；
- 从原生 Headers / undici 形状输入时会优先使用其 `getSetCookie()`；
- `check-fetch-shim.cjs` 增加本地双 Set-Cookie 回环测试。

不能用 `get('set-cookie').split(',')` 替代：真实 `Expires=Wed, 21 Oct ...`
自身含逗号，会切坏 cookie。

## 2. Node 环境

### 2.1 布置位置

```text
<filesDir>/bin/node
<filesDir>/bin/node-cli
```

- `node-cli` 是约 51 KB 的 ELF，由 `hostruntime/src/main/cpp/nodecli.c` 编译并自签名。
- 它不复制第二份完整 Node，而是加载 HAP 已有的 `libnode.so.137`。
- `bin/node` wrapper 注入：
  - `DSHM_NODE_LIBNODE`
  - `LD_LIBRARY_PATH`
  - `UV_USE_IO_URING=0`
- Host 启动时设置 `DSH_NODE` 与 `DSH_DESKTOP_NODE_EXECUTABLE`。

### 2.2 为什么子进程不再强制 `--jitless`

Host 主进程仍以 `--jitless` 运行；插件 spawn 的独立 Node 进程使用 JIT：

```text
Host:      libnode + --jitless
Plugin:    node-cli（JIT）→ 独立进程
```

原因：Node 24 的原生 `fetch`/undici 初始化依赖 WebAssembly。强制子进程
`--jitless` 会让所有 `node bili.mjs ...` 网络命令在模块初始化阶段抛
`WebAssembly is not defined`。

实测：

```text
wasm=object
fetch=-101
```

`-101` 是 B 站“账号未登录”的正常业务码，证明 HTTPS 与 fetch 已工作。

## 3. ffmpeg / ffprobe 环境（PC entry HAP）

### 3.1 构建期采集

入口：`node tools/place-ffmpeg.mjs`

产物：

```text
entry/src/main/resources/resfile/toolchain/ffmpeg/
  bin/ffmpeg
  bin/ffprobe
  lib/*.so*
  dshm-ffmpeg.json
  NOTICE.md
  LICENSE.md
  COPYING.{GPLv2,GPLv3,LGPLv2.1,LGPLv3}
```

当前采集版本：

```text
ffmpeg version 9.0.1
28 个动态库
约 43 MiB
```

Brew ffmpeg 是动态链接程序，不能只复制 398 KB 主二进制。脚本按 ELF
`NEEDED` + `RUNPATH` 递归收集闭包，并对主程序和全部库执行 OHOS 自签名。

### 3.2 运行期落位

入口：`hostcore/app/ffmpeg-runtime-provision.cjs`

```text
<filesDir>/toolchain/ffmpeg/
<filesDir>/bin/ffmpeg     # wrapper
<filesDir>/bin/ffprobe    # wrapper
```

wrapper 设置：

```text
LD_LIBRARY_PATH=<ffmpeg/lib>:<NATIVE_LIBS>:/system/lib64
```

Host 启动后注入：

```text
FFMPEG=<filesDir>/bin/ffmpeg
FFPROBE=<filesDir>/bin/ffprobe
```

插件 `tools/lib/ffmpeg.mjs` 的候选顺序是 `$FFMPEG` → `PATH`，因此无需改插件。

### 3.3 平台边界

- PC / 2in1：自动落位。
- 平板与 phone：不加载、不复制、不生成 wrapper，也不注入 `FFMPEG` / `FFPROBE`；
  升级前若已有历史落位，会在 Host 启动时清理这些生成物。
- Host 主进程仍运行 `libnode.so.137`，该 ffmpeg 只供独立子进程使用。
- 资产只进入 PC `entry` HAP 的 `resfile`，不进入共享 `hostruntime` HSP。entry 把
  自身 resourceDir 经 `DSHM_PC_RESFILE_DIR` 交给共享 Host 完成落位。
- 当前 `1.1.6 / 1010007` PC-only beta APP 只声明 `2in1`，不包含 `phone` HAP；
  手机和平板安装失败是预期结果，应继续使用各自工程或正式三端包。

### 3.4 许可证

本机 Brew 构建启用了 `--enable-gpl`，包含 x264/x265 等 GPL 组件。
APP 内随目录携带 `NOTICE.md` 与对应 GPL/LGPL 文本。后续若用于 AGC 正式发布，
需在发布合规审查中复核 GPL 义务或改用 LGPL 构建。

## 4. 实测结果

使用真实 Brew 闭包落位到可执行目录后：

```text
$ ffmpeg -version
ffmpeg version 9.0.1

$ ffprobe -version
ffprobe version 9.0.1

$ node -e 'console.log(typeof WebAssembly)'
object

$ node -e 'fetch("https://api.bilibili.com/x/web-interface/nav")...'
fetch=-101
```

ffmpeg 还完成了端到端媒体冒烟：

```text
testsrc 64x64 1s → MJPEG AVI → ffprobe duration=1.000000 → JPEG 抽取成功
```

养鱼插件自己的依赖体检：

```json
{
  "Node.js": true,
  "node 运行时": true,
  "ffmpeg（抽帧看画面）": true,
  "数据目录可写": true
}
```

未填 cookie、未保存配置时，`B站 cookie` 与 `生物钟` 仍会提示未配置；
这是插件配置状态，不是 DSHM 环境缺失。

## 5. 门禁

`node tools/check-node-cli.mjs` 覆盖：

- `DSH_NODE` 注入；
- 子进程不强制 `--jitless`；
- Node wrapper 的 libnode / io_uring 接线；
- ffmpeg 目录替换、wrapper、`FFMPEG/FFPROBE` 注入；
- `ffmpeg/ffprobe` 与动态库闭包存在、主程序带 `.codesign`；
- build-beta 构建前自动运行 ffmpeg 采集。

`node tools/place-ffmpeg.mjs --check` 独立校验生成物完整性。

## 6. 剩余插件侧问题

以下不属于 DSHM 环境，需插件上游修复：

1. 评论/私信监听默认值三处漂移。
2. 新会话首次唤醒权限仍可能需要用户手动设为完全访问。
3. 无 ffmpeg 时可增加 B 站 videoshot + sharp 的备用抽帧路线。
4. 非 Windows 桌面通知目前只打印日志。
5. 插件依赖未 pin commit。

