# Codex 子智能体安装修复

> 日期：2026-10-22
>
> 结论：`@deepseek-ai/dsh-subagent-codex@0.2.1-rc.2` 已能在鸿蒙 PC 完成安装、
> 激活和真实委派。安装器复用本机 brew Codex，并同步应用私有 `CODEX_HOME` 与 CA；
> 父 Agent 实测调用返回 `CODEX_CA_OK pong`。

## 1. 表面错误

用户请求：

```text
@deepseek-ai/dsh-subagent-codex@0.2.1-rc.2
```

实际第一次安装成：

```text
@deepseek-ai/dsh-subagent-codex@0.0.1-rc.1
```

随后 DSH 以 0.0.1 的 peer requirements 对 0.2.1-rc.2 runtime 做兼容性检查，
报 `installation rejected`。

这不是版本不存在，也不是需要直接豁免。registry 明确存在 `0.2.1-rc.2`。

## 2. 第一层根因：安装器丢了显式 prerelease

`@deepseek-ai/dsh-subagent-codex` 的 dist-tags：

```text
latest = 0.0.1-rc.1
next   = 0.2.1-rc.2
```

旧 `pickVersion()` 只处理稳定 semver 范围。显式值 `0.2.1-rc.2` 解析失败后
错误回退 `dist-tags.latest`，于是显式请求被安装成了旧版。

修复后的顺序：

1. 精确命中 `versions` ⇒ 直接使用，包括 prerelease；
2. 命中 dist-tag（`next` / `alpha` / `latest`）⇒ 使用 tag 目标；
3. 其它 semver 范围才进入稳定版本选择。

## 3. 第二层根因：npm alias 与平台载荷

0.2.1-rc.2 依赖：

```text
@openai/codex@0.153.4
```

该包是 only-bin wrapper，真正平台载荷是 optional alias：

```text
@openai/codex-linux-arm64@npm:@openai/codex@0.153.4-linux-arm64
```

旧安装器不认识 `npm:` alias，且会尝试下载所有平台的 optional 包。

修复：

- 识别 `aliasName@npm:realName@version`；
- 落位使用 alias 目录，manifest 内真名不覆盖 alias；
- optionalDependencies 只保留 `linux-arm64` / `openharmony-arm64`；
- bin-only 包和 os/cpu 平台资产包不再被误判“入口文件缺失”；
- 顶层包已存在但依赖缺失时，从已装 manifest 继续补齐依赖。

## 4. 鸿蒙 PC 原生 Codex 适配

鸿蒙 PC 已有 brew Codex：

```text
~/.harmonybrew/bin/codex
codex-cli 0.163.0
```

但应用域不能直接 execve 该路径，实测返回：

```text
/bin/sh: .../.harmonybrew/bin/codex: Operation not permitted
```

应用可执行的是 DSHM 用户可见目录中的副本：

```text
~/Download/com.dshm.dshclient/codex-brew
```

一次性同步：

```bash
node tools/setup-codex-for-dshm.mjs
```

该脚本：

- 找到 brew 当前 `codex`；
- 复制到 DSHM 目录；
- 校验 `codex --version`；
- 输出大小与 SHA-256；
- 版本和大小一致时跳过重复复制。

## 5. 第三方插件 boot 适配

`dsh-subagent-codex` 上游默认执行：

```text
[process.execPath, @openai/codex/bin/codex.js, app-server, --stdio]
```

DSHM 使用嵌入式 libnode，`process.execPath` 是 `/system/bin/appspawn`，不是
Node CLI。因此安装器在插件落位后只做一处最小 patch：

```text
[codex-brew, app-server, --stdio]
```

同时安装一个 npm 形状的 `@openai/codex` 本地 shim，兼容上游
`require.resolve('@openai/codex/package.json')` 的检查。

补丁不修改第三方源码包本身；每次安装由 `dshm-installer.js` 在 profile 副本上
应用，可用 `DSHM_CODEX_BIN` 覆盖实际二进制路径。

## 6. 真机验证

安装结果：

```text
@openai/codex@0.153.4+dshm-brew
@deepseek-ai/dsh-tool-subagent@0.2.1-rc.2
zod@4.4.3
```

日志确认：

```text
复用 brew codex：.../Download/com.dshm.dshclient/codex-brew → @openai/codex shim
subagent-codex 已切换到原生 Codex：.../codex-brew
```

重启后不再出现：

```text
Cannot find module '@openai/codex/package.json'
entry did not activate subagent-codex
```

应用执行域直接运行：

```text
codex-cli 0.163.0
CODEX_EXIT=0
```

Codex app-server 初始化成功：

```json
{
  "id": 1,
  "result": {
    "userAgent": "deepseek-harness/0.163.0 (Linux Unknown; aarch64) xterm-256color (deepseek-harness; 0.0.1)",
    "platformFamily": "unix",
    "platformOs": "linux"
  }
}
```

## 7. 门禁

- `check-dshm-installer.cjs`：**70 passed / 0 failed**；本轮新增的 npm alias、
  精确 prerelease、brew shim、`CODEX_HOME`/CA 注入与旧补丁刷新断言全部通过；
- 精确 prerelease 不被 stale latest 覆盖；
- npm alias 解析；
- linux-arm64 平台依赖筛选；
- bin-only / 平台资产包可加载；
- brew Codex shim 与插件 argv patch；
- 用户数据覆盖安装后 `links=12 → 12`；
- PC 权限仍恒 11 条。

## 8. 端到端复测（23:50–23:58）

上一轮报告（`harness/DSHM-codex子智能体-测试报告-2026-10-22.md`）已经把断点
定位到“app-server 可以拉起，但模型出口、登录态和看门狗仍不完整”。本轮按下述顺序收口。

### 8.1 TLS 不是断网

应用执行域访问 `https://api.deepseek.com/` 时：

```text
CERTIFICATE_VERIFY_FAILED: self-signed certificate in certificate chain
```

但同一时刻桌面 curl 可达，Host Python 指定
`capath=/etc/security/certificates` 或 brew CA file 后也返回 HTTP 401（可达）。

因此 `Reconnecting... waiting for network` 的真实根因是 **Rust TLS 没拿到应用域
应使用的 CA**，不是 OpenAI/DeepSeek 全站不通。安装器现在会给子进程显式注入：

```text
CODEX_HOME=<app files>/.codex
SSL_CERT_FILE=<app files>/.codex/codex-ca.pem
SSL_CERT_DIR=/etc/security/certificates
```

### 8.2 登录态与模型目录

宿主 `~/.codex` 与应用私有 `.codex` 不是同一安全域，应用不能直接读宿主目录。
`tools/setup-codex-for-dshm.mjs` 现在会幂等同步：

- `codex-brew`；
- `codex-ca.pem`；
- `auth.json` / `config.toml` / `models.json`；
- 应用私有 `.codex` 目录权限收紧为 `0700`，文件为 `0600`。

暂存目录使用 `Download/<bundle>/.codex-seed-*`，由 app 端点复制后立即删除；
凭据内容不进入 URL、源码或终端输出。

应用域最小 CLI 验证：

```text
codex-cli 0.163.0
BREW_CODEX_OK
```

使用的是 `config.toml` 中的 `provider=deepseek / model=deepseek-flash`，不再依赖
不可达的 OpenAI 默认出口。

### 8.3 插件环境注入

`patchCodexSubagentForExternalCodex()` 现在除 argv 外还生成
`dshmCodexSpawnEnv(spec)`。上游 `spec.env` 仍拥有最终覆盖权，但默认会得到
`CODEX_HOME` 与 TLS CA。旧版只换二进制、不注入 CA 的 profile 副本会在重装时整块刷新。

设备实读：

```json
{
  "marker": true,
  "home_helper": true,
  "env_call": true,
  "ca_const": true,
  "ca_exists": true,
  "ca_size": 228372,
  "auth_exists": true,
  "config_exists": true,
  "models_exists": true
}
```

### 8.4 真实父 Agent 委派

通过真实 `session/create → session/follow → session/prompt` 让父 Agent 实际调用
`subagent_codex`：

```text
description = "CA smoke"
prompt      = "Reply with exactly CODEX_CA_OK. Do nothing else."
```

结果：

```text
subagent id: 01faf1c8-fa26-4eec-80a3-a00d781d045f
mode:        external
label:       CA smoke
final:       CODEX_CA_OK pong
running:     false
```

父会话统计为 1 turn / 3 steps，模型耗时约 12.2 s，工具耗时约 0.68 s。
这不是只验证 `app-server initialize`，而是完整走过了插件、thread、turn、
Codex 子进程与父会话结果回收。

最终 HAP 再次覆盖安装后，又以不直接回显目标 token 的提示词复验一次：

```text
label:    Final smoke
response: CODEX__FINAL_OK pong
running:  false
```

第二个下划线来自测试提示词“把 `CODEX_` 与 `FINAL_OK` 用下划线连接”的字面语义；
关键判据是父会话确实完成了 external 子代理，并持久回收了 Codex 返回值。

随后又验证了子代理内部的命令执行通道：

```text
label:    Exec smoke
subagent: 261087b6-8f1f-40f1-a41e-3a6ccd85e012
result:   CODEX_EXEC_OK / pong
running:  false
```

这说明 app-server 不仅能返回纯文本；它确实创建 thread/turn，调用了只读 shell，
并把命令 stdout 经 external subagent 回传给父会话。日志中的
`bubblewrap not found ... use bundled bubblewrap` 是 PATH 提示，内置后备实际可用。

### 8.5 构建与覆盖安装

- `hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon`
  BUILD SUCCESSFUL；
- `hdc install -r entry/build/default/outputs/default/entry-default-signed.hap` 成功；
- 未执行 uninstall，未删除 el2 用户数据；
- 最终 debug HAP：338,656,159 B；
- SHA-256：`06bf6945a51e2df29135ee198df143008a0b54f878c44a01f8bc99830ee09f48`；
- `assert-resfile-sync`：19 件快照全部同步；
- PC 权限仍恒 11 条。

