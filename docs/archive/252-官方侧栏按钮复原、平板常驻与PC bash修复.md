# 官方侧栏按钮复原、平板常驻与 PC bash 修复

> 日期：2026-10-24
>
> 版本：`1.1.6 / 1010007`
>
> 核心：`0.2.1-rc.3+dshm.95`

## 1. 侧栏修正

上一版错误地隐藏了 DeepSeek Harness 字标右侧的官方侧栏按钮，并给普通平板叠加了
页面内 FAB。本轮撤销该做法：

- 普通平板不再创建 FAB；
- 官方「收起侧边栏 / 打开侧边栏」按钮保留在原位置；
- 平板横屏、竖屏都走默认展开，不再按竖屏自动收起；
- 普通平板的收起态不再套用页面内 0 宽 frame 规则；这类规则只允许命中 PC / compact；
- 冷启动、右侧栏开关、React 重排造成的非用户收起都会恢复左栏；
- compact 手机/折叠单屏只在官方按钮被 0 宽侧栏列裁掉时使用原有 FAB；
- compact 右栏打开时隐藏左入口，避免覆盖重叠；
- PC/2in1 继续使用原生顶栏并隐藏 Web 重复入口。

门禁：

- `check-sidebar-shim-css.mjs --self-test`：23 项正例、10 个变异全红；
- `check-handheld-sidebar-recover.mjs`：16 个变异全红。

## 2. PC bash EACCES

桌面实测见 `Desktop/bash-tool-test.md`：

```text
bash 工具 echo ok ❌ spawn bash EACCES
ash / system-sh / toybox ✅
```

根因是 `@deepseek-ai/dsh-bash-local` 固定发 `["bash","-c",cmd]`，而
`<sandbox>/bin/bash` 是文本垫片；鸿蒙在 execve 阶段直接拒绝脚本本体，即使 shebang
指向可执行的 ash 也一样。

修法：

- `RuntimePort` 只在 `nativeTerminalOnly=1` 的 PC/2in1/Edge 档下发
  `DSHM_BASH_EXECUTABLE=/usr/bin/zsh`（与侧边栏终端同一系统 shell）；
- `pack-core` 给 `dsh-bash-local.execute()` 增加该显式 shell 覆盖；
- 未设置变量时仍为 `bash`，手机/平板的 guest VM 接管链完全不变；
- 开机探针的 `bash` 项也优先测实际使用的 `DSHM_BASH_EXECUTABLE`。

因此 PC 不再执行脚本垫片，而是直接执行系统原生 zsh。

## 3. 审核中顺带修正

- `place-toolchain` 支持鸿蒙 CLT 原生 `binary-sign-tool`，不再只认 Windows jar；
- `sign-tar-elf.py` 同时兼容原生 signer 与 jar；
- `check-libnode-io-uring` 跟随公共 HSP 结构，从 `hostruntime/libs` 读取 libnode；
- `check-mobile-upgrade-migration` 会检查 `build/outputs/release` 的最新 APP。

工具链实签：python `10/10`、git 闭包全部 ELF；`check-toolchain-sign` PASS。

## 4. 构建

核心升级到 `.95`，避免同版本内容漂移。

最终 AGC release：

- `dist/release-test/DSHM-1.1.6-1010007-core95-tablet-coldstart-bash-release-20261024.app`
- 大小：`481,030,983 B`
- SHA-256：`87cdd180c84388f849ae17ba0c1e7b317c6c9813280b5f2bafdc148e546f3a9a`
- `verify-app success`；
- `entry` / `phone` 均为 `buildMode=release / debug=false`；
- HSP 只携带 `.95` 核心；
- Profile 为 `release`、App ID `6917614360926110054`、7 条 ACL。

单 entry 手工侧载目录：

- `dist/sideload/DSHM-1.1.6-1010007-core95-tablet-coldstart-bash-agc-release/pc/`
- `dist/sideload/DSHM-1.1.6-1010007-core95-tablet-coldstart-bash-agc-release/tablet/`
- `dist/sideload/DSHM-1.1.6-1010007-core95-tablet-coldstart-bash-agc-release/phone/`
