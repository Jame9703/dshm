# 188 · 内测双报告收口与 guest SSH 客户端

> 2026-10-18。处理内测组随包提交的两份报告，并完成 SSH 可行性验证：
> `DSHM-分屏旋转右侧空白-bug.md`、`DSHM-命令执行错误报告.md`。
> 应用版本保持 `1.1.4 / 1010004`；核心推进到 `0.2.1-rc.2+dshm.73`。

## 1. 分屏旋转右侧空白

真机报告：竖屏上下分屏 → 横屏左右分屏 → 回竖屏后，窗口已恢复 `460vp`，
但 `dshm-frame` 内容仍停在横屏窗格约 `313.5vp`，右侧 `146.5vp` 为白。

本轮做两层回正：

1. `SIDEBAR_SHIM_JS` 给 `html.dshm-handheld .dshm-frame` 增加不可回退的
   `width/max-width:100%` 与 `min-width:0`，不再只改三列轨道。
2. 新增 `VIEWPORT_RECONCILE_SCRIPT`：
   - `Web.onAreaChange` 与主窗 `windowSizeChange` / `windowRectChange` 都触发；
   - 0 / 120 / 240 ms 补发三次 `resize` 与 `visualViewport.resize`；
   - 将 html/body/frame 宽度重新锚到当前视口；
   - 仅手持档执行，PC / 2in1 返回 `off`。
   - **软键盘显示期间完全停止上述回正与 resize 注入**，键盘收起后再补一次；
     否则 xterm 会反复重测视口，输入/删除时出现乱跳。

现有竖屏真机读数：`htmlClass="dshm-handheld dshm-phone"`、
`frameClass="pI_x6G_frame dshm-frame"`、`grid=0px 366px 0px`。

## 2. QGA 请求/响应错配

报告现场：`guest-exec-status` 20 s 超时后，通道半死；后续新命令拿到上一条命令的旧输出，
并出现 `PID ld does not exist`。

根因：超时后连接被保留，但 QGA 普通响应不带请求 id；迟到响应会被下一条命令顺序取走。

修法：

- 任何 `call()` 超时都**无条件丢弃连接**，错误报文带 request id、等待时长、收发字节与“连接已复位”。
- 重连后的第一条命令先执行 `guest-sync-delimited`，以魔数 id 圈出协议边界。
- `guest-exec` 必须返回数字 pid；`guest-exec-status` 必须返回布尔 `exited`，形状不符即断链报错。
- guest 命令超时先断链，再在新连接上重连、sync、kill pid。

`check-vm-bash` 新增第 6 臂：旧连接超时后故意迟到一条 `STALE FROM PREVIOUS COMMAND`，
断言新命令只拿到自己的 `FRESH FROM NEW COMMAND`，并确实建立了第 2 条连接。
门禁总计 **411/411 PASS**。

## 3. Python 与 guest shim

### 3.1 `python` 工具路径

- `file` 新增 `path` 兼容别名，避免调用方猜参数名。
- 缺参数错误回显收到的参数键。
- Host 允许根从“沙箱 home”扩展到：沙箱根、`$DSH_HOME`、Host 当前会话 cwd。
- 越界错误回显 `got` 与 `allowedRoots`；不再只回一句
  `script path must be inside sandbox home`。

### 3.2 guest 内没有宿主 shim

`bash` 工具在手机 / 平板上运行 Alpine guest；guest PATH 不包含
`$DSHM_SANDBOX_HOME/bin`。因此 guest 里 `python3/pip3/git/rg` 为 `command not found`
是当前设计，不是内嵌 Python 缺失。`ohos-python` 与 `ohos-shell` 技能已改写：

- Python 统一优先使用 Agent 的 `python` 工具；
- 不再把宿主垫片示例当成 guest bash 示例；
- 明确宿主沙箱、guest VM、内嵌运行时三者边界。

## 4. SSH 接入

采用 guest 侧 Dropbear 客户端，不新增权限、不启动 SSH 服务端：

- Alpine 闭包新增：
  `dropbear`、`dropbear-dbclient`、`dropbear-ssh`、`dropbear-scp`、
  `utmps-libs`、`skalibs-libs`、`zlib`。
- guest 提供 `/usr/bin/ssh`、`/usr/bin/scp`、`/usr/bin/dropbearkey`；
  `dropbear` 主包随包但**不自动启动服务端**。
- `provision()` 的就绪判据从 `/bin/bash` 扩展为
  `/bin/bash && /usr/bin/ssh && /usr/bin/dropbearkey`。
- `stage()` 会按文件大小补拷新增 guest 包：老设备已有 `guestpkgs/` 目录也不会漏装 SSH。

端到端 POC：PC 上启动临时 SSH 服务 `192.168.2.18:2222`，手机 DSHM guest 执行：

```bash
ssh -y -p 2222 dshmtest@192.168.2.18 echo DSHM_SSH_OK
```

真机返回：

```text
Host '192.168.2.18' key accepted unconditionally.
DSHM_SSH_OK
```

完整链路还验证了：

- `dropbearkey -t ed25519 -f ~/.ssh/id_ed25519` 成功生成私钥，`-y` 输出公钥指纹；
- `ssh -i ~/.ssh/id_ed25519 ... echo KEY_AUTH_OK` 公钥认证成功；
- `scp -P 2222 /tmp/scp_ok.txt ...:/tmp/` 返回 `SCP_RC=0`，服务端实收 12 B；
- 主机指纹与 `-y` 语义生效；错误指纹会明确拒绝（实测 host key mismatch）。

证据：

- `dist/acceptance/20261018-ssh-poc/dshm-ssh-poc.jpeg`
- `dist/acceptance/20261018-ssh-poc/dshm-ssh-keygen.jpeg`
- `dist/acceptance/20261018-ssh-poc/dshm-ssh-publickey.jpeg`
- `dist/acceptance/20261018-ssh-poc/dshm-scp.jpeg`
- `dist/acceptance/20261018-ssh-poc/ssh-server.log`
- `dist/acceptance/20261018-terminal-input/dshm-backspace-ok.jpeg`
- `dist/acceptance/20261018-terminal-input/dshm-pc-final.jpeg`

说明：`10.0.2.2` 是 guest 内的 QEMU 网关，不是 PC；访问宿主机使用其局域网 IP。

## 5. 边界

- Split-screen 组合仍需用户在真实分屏里做一次竖→横→竖截图复验。
- SSH 客户端已可用；主机指纹、密钥、代理跳板等用户级配置仍需由用户按环境提供。
- 长扫描 60s 转后台仍是调度策略问题，本轮未改上游 bash 工具的超时阈值。
- 未 commit / 未 push。
