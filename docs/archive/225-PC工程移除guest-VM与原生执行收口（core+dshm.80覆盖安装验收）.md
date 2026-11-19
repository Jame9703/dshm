# PC 工程移除 guest VM 与原生执行收口

> **历史批次说明**：本文的 `.80` 是 VM 移除批次验收基线；后续浏览器扩展能力协商
> 已把核心继续升至 `.84`，当前交接口径见 `docs/226` 与 `docs/HANDOFF.md`。

> 日期：2026-10-22
>
> 范围：PC 工程 `com.dshm.dshclient`
>
> 结论：PC 工程已彻底移除移动端 guest VM；shell、PTY、Python、Git、rg
> 全部走宿主原生命令链；核心升级为 `0.2.1-rc.2+dshm.80`，已完成 debug HAP
> 构建、`hdc install -r` 覆盖安装和真机验收。

## 1. 决策

- PC 工程继续支持 `tablet` / `2in1` 形态，但平板形态也只走宿主原生执行。
- 手机端能力由独立 `DSHM-mobile` 工程维护，不再在 PC 工程保留兼容分支。
- `CUSTOM_SANDBOX` 是 PC 原生 shell / PTY / ELF 执行的基础权限。
- `rg` 等需要 `execve` 的随包 ELF 必须在构建期写入 `.codesign`。
- 真机升级只允许 `hdc install -r`；不卸载、不删除 el2 用户数据。

## 2. 已删除

| 类别 | 路径 / 内容 |
|---|---|
| VM 插件 | `hostcore/plugins/dshm-vm-bash/` |
| VM 资源 | `entry/src/main/resources/resfile/vm/` |
| QEMU 库 | `entry/libs/arm64-v8a/libqemu-system-aarch64.so` |
| slirp 库 | `entry/libs/arm64-v8a/libslirp.so.0` |
| VM 第三方素材 | `third_party/vmhish/` |
| VM 专属工具 | `check-qemu-isa.mjs`、`check-vm-bash.mjs`、`check-vm-memory-tier.mjs`、`fetch-vm-guest-pkgs.mjs`、`place-vm-assets.mjs` |
| 已完成迁移工具 | `tools/export-deveco-workspace.ps1` 与根目录 `MIGRATION-MANIFEST.txt` |
| 旧核心产物 | `+dshm.78` / `+dshm.79` 的可再生工作树和 zip |

工作区中直接移除的 VM 源码、资源和库约 245 MB。旧核心工作树与容器也已清理，
当前只保留 `+dshm.80`。

## 3. 原生替代

| 能力 | 当前实现 |
|---|---|
| shell / 终端 | 宿主原生 PTY，兜底 `/bin/sh -i` |
| Python | Agent `python` 工具走进程内 CPython；PC shell 也可用 `python3` / `pip3` |
| Git | 宿主沙箱原生 `git` 与 `git-remote-http` |
| 搜索 | 随包 ripgrep ELF，构建期自签名后由宿主原生 `execve` |
| 系统命令 | 宿主 `ash` / `bash` / `system-sh` / `toybox` |
| 手机 / 平板移动 VM | 独立 `DSHM-mobile` 工程 |

## 4. 构建期回归修复

第一次干净重建发现 `rg=denied`。根因是 `pack-core` 只识别 JDK +
`binary-sign-tool.jar`，而鸿蒙 PC CLT 提供的是原生 `binary-sign-tool`，
因此自签名被静默跳过。

已修复：

- `pack-core` 优先识别 CLT 原生 `binary-sign-tool`，同时保留 jar 兼容分支。
- 原生工具调用不再传 jar 专有的 `-mode localSign`。
- 找不到签名工具或签名失败时直接终止出包，禁止再产出 `rg` 必然被拒的核心包。
- `assert-exec-fix` 增加静态回归断言，防止“静默跳过自签名”复活。

核心因此从 `.79` 升至 `.80`，确保设备会真正替换已安装的旧核心。

## 5. 产物

| 项 | 值 |
|---|---|
| 核心 | `0.2.1-rc.2+dshm.80` |
| 核心 zip | `entry/src/main/resources/resfile/dsh-core-0.2.1-rc.2+dshm.80-openharmony-arm64.zip` |
| 核心 zip 大小 | `99,244,863 B` |
| 核心 zip SHA-256 | `7164fdd6e436c4cf634a87a4da6f530775c503d2c38ee932ba622105cd94d2e3` |
| debug HAP | `entry/build/default/outputs/default/entry-default-signed.hap` |
| HAP 大小 | `322.9 MiB` |
| HAP 内 VM / QEMU 条目 | 0 |

核心树与 zip 的 VM/QEMU 路径扫描均为 0 命中。`rg` 已确认带 4096 字节
`.codesign` 段，`display-sign` 返回 `code signature is self-sign`。

## 6. 门禁

本轮通过：

- ArkTS 编译 0 error；
- 核心入口 3,698/3,698 可解析；
- 核心端侧补丁 244/244；
- 权限面、PC-only、无 APK、resfile 同步、文档引用、死代码；
- Python 工具、技能同步、APM 查询；
- 内存守卫、VM 缺失守卫与原生终端策略。

## 7. 真机验收

设备：`MNTXM-24B`，2in1，API 26，连接 `127.0.0.1:45595`。

覆盖安装前后 `files/dsh/home` 指纹均为 `links=12 size=3440`，用户数据未减少；
设备核心树已出现 `0.2.1-rc.2+dshm.80`。

原生 exec：

```text
python3.12=ok，git=ok，git-core/git=ok，git-remote-http=ok，rg=ok，
ash=ok，bash=ok，system-sh=ok，toybox=ok，git-ls-remote=ok
```

结果：10/10 全通。

终端 RPC 实测：

- `terminal/create` 返回 HTTP 200；
- shell 为 `/bin/sh -i`；
- `state=running`；
- 测试结束后 `terminal/close` 返回 HTTP 200。

权限：11 条中 10 条已授予；`MICROPHONE` 仍为首次运行时待授权。

## 8. 保留边界

设备 el2 下仍存在旧版运行时留下的
`haps/entry/files/vm/` 数据目录（约 54 MB）。它不再被当前 HAP 引用，
但属于真机用户数据区；按数据保全红线，本轮**没有删除**。

`ACCESS_USER_FULL_DISK` 仍未获批，不能把全盘访问视为当前能力。

