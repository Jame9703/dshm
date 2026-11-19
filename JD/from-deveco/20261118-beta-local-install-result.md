# JD-003 结论：Beta 本机/手机侧载包 + AGC 云测包（DevEco 执行）

- **ID**：JD-003
- **执行方**：DevEco
- **时间**：2026-11-19 00:00
- **结论**：**PASS（构建 + 安装 + 启动）**；功能验收待用户在设备侧测试后回填
- **状态**：`待测试`（用户测试中）

---

## 1. 产物

### Beta 本机可侧载包（最新工作树，含 WorkBuddy 在途改动）

```text
dist/beta/DSHM-beta-1.1.8-1010017-20261118T234544-local/
  tablet/DSHM-1.1.8-beta-entry-local.hap
  tablet/DSHM-1.1.8-beta-hostruntime-local.hsp
  phone/DSHM-1.1.8-beta-phone-local.hap
  phone/DSHM-1.1.8-beta-hostruntime-local.hsp
  SHA256SUMS
  README-LOCAL.txt
```

- 身份：`com.dshm.dshmbeta` / `1.1.8` / `1010017` / **debug**
- 权限：entry **18** / phone **9**（包内 `module.json` 实读）
- 核心：`0.2.2-rc.4+dshm.1`（HSP 内恰好 1 份容器）
- 签名：`devecocli signature generate` 本机调试身份；Profile `device-ids` 实测含
  本机 PC `20DB409A…` 与手机 `CA46EC63…`

### AGC 云测包（release）

```text
dist/release-test/dshm-1.1.8-1010017-dshm.1-AGC-invite-20261118T155513.app
size   663,657,430 B
sha256 a1ea67efcc12b48a61c5b1f3647d9b668ebd69f7cbba17a3b3869ce0d5f07188
```

- `profile_acls=8`；entry 受控声明 8 条全部在 Profile 内
- 脚本内建校验通过：设备面 / 权限 18·9 / HSP 单容器 / ffmpeg / 无 `dsh-bili-whale` / `hap-sign-tool verify-app`
- `.app.sha256` 与 `SHA256SUMS.txt` 已写入；实测 `sha256sum` 与文件一致
- **release 包不可本地侧载**，只能走 AppGallery / 云测分发

## 2. 执行记录

```sh
# 1) 备份 16 个身份文件（MANIFEST + sha256）
dist/acceptance/jd003-beta-local-20261118T234544/originals/

# 2) 改 beta 身份（不注入全盘权限）→ 本机调试签名
devecocli signature generate          # rc=0
node tools/place-host-app.mjs

# 3) 构建
devecocli build --product default     # rc=0
devecocli build --product phone       # rc=0

# 4) 安装（覆盖安装，禁止 uninstall）
hdc install -r tablet/…-hostruntime-local.hsp   # success
hdc install -r tablet/…-entry-local.hap         # success
hdc -t 192.168.2.3:45595 install -r phone/…-hostruntime-local.hsp  # success
hdc -t 192.168.2.3:45595 install -r phone/…-phone-local.hap        # success

# 5) 启动
hdc shell aa start -a EntryAbility -b com.dshm.dshmbeta            # 2in1
hdc -t 192.168.2.3:45595 shell aa start -a EntryAbility -b com.dshm.dshmbeta  # Mate 80
```

启动证据：

- PC（2in1）：进程 `com.dshm.dshmbeta` / `:gpu` / `:render` 在线，窗口存在；
  截图 `dist/acceptance/jd003-beta-local-20261118T234544/launch.jpeg`
- 手机（Mate 80）：进程在线；截图里历史会话与输入框正常显示（数据保留）
  `dist/acceptance/jd003-beta-local-20261118T234544/phone-launch.jpeg`

## 3. 收尾核验

- 16 个身份文件按 MANIFEST 逐字还原，sha 全等；`build-profile.json5` 回到
  `11887088…`（与出包前一致）；已重跑 `place-host-app`。
- 全量门禁：`dist/acceptance/20261118-jd003-beta-local-full-gates.txt` = **133 / 0**。
- AGC 构建日志：`dist/acceptance/jd003-beta-local-20261118T234544/agc-build.log`。

## 4. 边界

- 本次只证明「构建 + 覆盖安装 + 启动」；**功能与 UI 验收未做**，由用户在 2in1 / 手机 / 平板云测侧回填。
- AGC 包未上传、未提审；平板云测请用上面的 `.app`。
- 手机测试完成后，若 WorkBuddy 有修复，需重新按本流程出包（每次 `signature generate` 会重新签发本机调试身份，
  设备侧按 debug→debug 覆盖安装即可，无需卸载）。

## 5. STATUS 同步

已更新 `JD/STATUS.md`：JD-003 → `待测试`，并链到本结论。
