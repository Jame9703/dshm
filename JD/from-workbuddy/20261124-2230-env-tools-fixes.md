# JD-041 PC / 手机端环境与工具复测问题修复

- 提交方：WorkBuddy
- 接收方：DevEco（重编 beta 验证）
- 时间：2026-11-24 22:30
- 依据：`DSHM-环境与工具复测-2026-11-24.md`（PC）与 `DSHM环境与工具复测报告-20261124.md`（guest）
- 关联：JD-039 / JD-040（Node 26 替换）

---

## 1. 结论

Node 26 本体无回归：PC 侧执行、文件、网络、图像、插件、任务全过；guest 侧文件/Python/网络/发布全过。
本次修两类**代码可修**的问题，其余为环境/上游限制，逐条给结论。

---

## 2. 已修

### 2.1 Office 渲染/转换缺字体（PC P1）

**根因**：`libreoffice-kit` 的 `systemFontDirectories()` 只认 win32 / darwin / Linux 常规路径
（`/usr/share/fonts`、`~/.fonts` 等），openharmony 上一个都不存在；本机字体在 `/system/fonts`。
wasm 后端拿不到字体面 ⇒ `office_render` / `office_convert` 直接报 `No usable fonts`。

**修复**：`hostcore/profile/ondevice/cordis.patch.yml` 末尾新增：

```yaml
- id: office-kit
  config:
    fontDirectories:
      - /system/fonts
```

- 只覆盖 `config`，不动其它字段；
- `patchReload: startup` ⇒ **必须重启 Host** 才生效；
- 三端共用同一 profile 种子，PC / 平板 / 手机一并生效。

### 2.2 手机端 guest vCPU 过少（执行慢）

**现状**：guest 固定 `-smp cpus=2`；复测中 guest 内 `node` 退出 20–29 s、`npm/pnpm` 15–30 s 不返回，
TCI 解释器下单核算力是主瓶颈。

**修复**（`hostcore/plugins/dshm-vm-bash/lib/vm.js`）：

- 新增 `VM_CPUS_DEFAULT = 4`（经济档）、`VM_CPUS_PERFORMANCE = 6`（16G+ 性能档）；
- 新增 `vmCpus(env, totalMib)` 纯函数，支持 `DSHM_VM_CPUS` 覆盖，夹在 `[1, 8]`；
- `-smp` 改为 `cpus=${cpus},sockets=1,cores=${cpus},threads=1`；
- `vmTierProfile()` 增加 `defaultCpus` 字段。

**取舍**：没有直接给满核。TCG 线程数与宿主负载线性相关，复测机已 20 核 / Load 25+ / PSI full 75%，
4/6 是"明显加速但不把宿主拖死"的折中；内存闸门 `memBudget` 仍在 VM 启动前拦住低内存设备。
需要回退时设 `DSHM_VM_CPUS=2`，不必重打包。

### 2.3 门禁

- `tools/check-vm-bash.mjs` 的断言从 `cpus=2` 改为跟随 `vmCpus()`；
- 结果：**376/376 PASS**。

---

## 3. 未修项与结论（不做代码改动）

| 项 | 结论 |
|---|---|
| 系统内存压力（PC P0，PSI full 75%、Swap 11.7G） | 系统级：DSHM RSS 约 979MB、VM 约 1.2GB。建议关掉不用的 ArkWeb 标签/后台应用后重启；不建议再抬 guest 内存。vCPU 4/6 为轻量增量，若现场仍吃紧用 `DSHM_VM_CPUS=2` 回退 |
| 浏览器桥未连接（PC P1） | 依赖外部浏览器扩展，非应用内可修；验收改用接口断言 |
| Python 第三方库全缺（两端 P3） | 端侧 CPython 只带标准库，属既定形态；Office/图片走 `office_*`、sharp、Node 侧实现 |
| guest 缺 `curl/jq/zip/file`（guest P3） | 可用 `wget` / Python 替代；要补需扩 `tools/fetch-vm-guest-pkgs.mjs` 的 WANT 并重取包（HAP 体积 +2~3MB），本次未做 |
| guest HTTPS 偶发 `unexpected eof` | QEMU slirp/MTU 链路问题，非应用代码；建议失败重试/HTTP 回退，后续单独定位 |
| guest 内 Office 转换失败 | 字体修好后应改善；wasm LibreOffice 在 TCI + 小内存下仍可能慢或失败，属能力上限，不承诺与桌面端一致 |
| dsh-pet `display` 回 `desktop`、余额 provider 不匹配 | 插件侧配置；需要页面内显示就切 `display: web`，余额切回 `deepseek-account` |

---

## 4. 重编与验证

```bash
node tools/pack-core.mjs            # 把 hostcore/profile 的新 patch 打进 core stage
node tools/place-host-app.mjs
node tools/assert-resfile-sync.mjs
node tools/check-vm-bash.mjs        # 期望 376/376
node tools/check-node-cli.mjs       # 期望 43/0
node tools/build-beta.mjs
```

真机：
1. 重启 Host 后 `office_render` / `office_convert` 对一份 docx 成功（或给出非字体类错误）；
2. guest 内 `node --version` 退出时间、`npm --version` 是否能在 30s 内返回；
3. 观察宿主 `free -h`、`/proc/pressure/memory`、Load，确认 4/6 vCPU 未把系统拖垮；
4. 若变慢/吃紧：`DSHM_VM_CPUS=2` 对照一轮，再决定默认值。

---

## 5. 风险

- vCPU 提高会增加 QEMU TCG 线程与宿主 CPU 占用；在 20 核但内存紧张的环境里需实测确认。
- Office 字体配置只解决"拿不到字体"；复杂排版与转换速度仍受 wasm 引擎限制。
