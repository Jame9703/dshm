# JD-005 / JD-006 编译结论 + AGC 重建（供 JD-003/004 平板云测）

- **执行方**：DevEco
- **时间**：2026-11-19 00:45
- **对应**：JD-003（云测包）、JD-004（云调试复测）、JD-005（VM 资源）、JD-006（平板标题栏）
- **结论**：**编译 PASS**；功能/视觉待用户在平板云调试复测

---

## 1. 新 AGC 包

```text
dist/release-test/dshm-1.1.8-1010017-dshm.1-AGC-invite-20261118T164204.app
size   663,657,474 B
sha256 825657543217f52609de41bb8a567af18711f5ec42580bfd871fca73b033fb90
```

- 身份：`com.dshm.dshclient` / 1.1.8 / 1010017 / release
- `profile_acls=8`；entry 受控声明 8 条全部在 Profile 内
- `.app.sha256` 与实测 `sha256sum` 一致
- 包内 HSP 核心容器：`dsh-core-0.2.2-rc.4+dshm.1-openharmony-arm64.zip`，sha256 `5b07f484…`
- **release 包不可本地侧载**；平板云调试请用本包（替换 `…T155513`）

## 2. 本轮包含的改动

| ID | 改动 | 验证 |
|---|---|---|
| JD-005 | guest VM：2 vCPU；RAM 512/1024 MiB；TCG buffer 128/512 MiB | `check-vm-memory-tier` PASS；`check-vm-bash` PASS 376/376；容器内 `vm.js` 与源码 sha 一致 |
| JD-006 | 平板自由窗口三键缩小（仅样式，不改可见性/缩放） | `check-decor-button-mode` / `check-window-mode` 由 WorkBuddy 跑绿；本机编译通过 |
| JD-002 | 无产品代码改动（门禁修复） | 门禁仍为已知争议项，见 STATUS |

## 3. 执行命令与关键输出

```sh
node tools/check-resfile-core-zip.mjs
# dist/core 203,019,827 B sha256 5b07f48421443bc3…；resfile 恰好 1 份

node tools/check-vm-memory-tier.mjs   # PASS
node tools/check-vm-bash.mjs          # PASS 376/376

python3 -c "import hashlib;print(hashlib.sha256(open('build-profile.json5','rb').read()).hexdigest()[:16])"
# 11887088799e03cc（出包前正式身份，未被临时改动污染）

CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-agc.mjs
# rc=0；ACL：Profile 8 条，entry 受控声明 8 条全部在 Profile 内
# 内建校验：设备面 / 权限 18·9 / HSP 单容器 / ffmpeg / 无 dsh-bili-whale / hap-sign-tool verify-app

sha256sum dist/release-test/…-20261118T164204.app
# 82565754…（与 .app.sha256 一致）
```

## 4. 请求用户复测（平板云调试）

1. 用新包 `…T164204.app`（不要再用 `…T155513`）。
2. 登录 / 外跳浏览器：点登录后看是否拉起浏览器；失败请记录**点击瞬间**日志（AbilityManager/Want/AccountKit）。
3. 插件安装：失败时记录点击瞬间的 installer / 网络 / 文件权限日志。
4. VM 资源：终端里跑 `pnpm -v` 与一次安装，记录耗时与宿主 CPU/内存；观察是否 OOM/过热。
5. 平板标题栏：三键是否明显变小、四边缩放/分屏/拖动是否仍在；竖屏侧栏是否走抽屉。
6. 手机仍装不上时，请提供云调试侧**安装失败错误码原文**（9568287 / 9568286 / 9568322 等）。

## 5. 边界

- 只证明「编译 + 包结构 + 签名 + 核心容器一致」；**未做平板云调试、未做真机视觉/性能验收**。
- 未上传 AGC、未提审；未改版本/权限；`build-profile.json5` 已由脚本 `finally` 复原。

## 6. STATUS 同步

已更新 `JD/STATUS.md`：JD-003 云测包替换为新 sha；JD-004 / JD-005 / JD-006 → `待测试`。
