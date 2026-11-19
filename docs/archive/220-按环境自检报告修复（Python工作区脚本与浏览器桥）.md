# 220 · 按环境自检报告修复（Python 工作区脚本与浏览器桥）

> 日期：2026-10-21 ｜ 输入报告：`~/harness/DSHM-ENV-TOOLCHECK-2026-10-21.md`

## 1. 报告结论

设备与主体功能健康，报告登记两处受限项：

1. Python `file` 模式只接受沙箱根，切换会话到
   `~/harness` 后，工作区 `.py` 被 400 拒绝；
2. DSHM Browser Bridge 未连接。

## 2. Python 工作区脚本

### 根因

`pyBridgeAllowedRoots()` 只包含：

```text
SANDBOX_HOME
HOME_DIR（dsh/home）
process.cwd()
```

默认工作区在 `Download/<bundle>` 时可以命中，但用户切换到
`~/harness` 后不在允许面内。

### 修复

把真实用户 HOME `ORIGINAL_HOME` 加入允许根。最终范围为：

- 应用沙箱；
- DSHM home；
- 当前 Host cwd；
- `~` 及其子目录。

没有放宽到 `/system`、`/etc`、`/proc` 或其他应用的沙箱。
`assert-python-bridge` 增加了对应接线断言。

### 验证

在报告所指工作区创建并执行：

```text
~/harness/.dshm_file_mode_probe.py
```

结果：

```text
FILE_MODE_OK ~/harness/.dshm_file_mode_probe.py python3
```

探针文件随后删除。

## 3. 浏览器桥

### 现场

海泰浏览器里已安装 `DSHM Browser Bridge 0.11.0`，扩展处于启用状态，
但扩展管理页显示它的 Service Worker 没有回连；宿主状态为：

```json
{"ok":true,"port":19390,"clients":[]}
```

同时将扩展源码部署到：

```text
~/Download/com.dshm.dshclient/dshm-browser-ext-v011
```

用于后续重装或换目录升级。

### 修复与验证

在浏览器扩展管理页重载 DSHM 扩展 Service Worker 后立即回连：

```json
{
  "ok": true,
  "port": 19390,
  "clients": [{
    "id": "ws_1",
    "info": {
      "extensionVersion": "0.11.0",
      "build": "dshm-host-bridge-11"
    }
  }]
}
```

实际工具链：

- `tabs`：识别到 example.com 活动页；
- `navigate`：`ok:true`、`load:complete`；
- `get_text`：成功返回 Example Domain 正文。

随后强制重启 DSHM Host，只等扩展 alarm 周期、不人工点击；桥在无干预下
自动恢复 `clients=1`，确认不是一次性的手工连接。

## 4. 仍需保留的产品边界

这些是设计边界，不是本轮故障：

- bash 实际是 POSIX ash 垫片，不应使用 bash 专属语法；
- 沙箱内没有独立 `node` 可执行文件；
- Python 第三方 C 扩展（PIL/numpy/lxml）默认不随包；
- 海泰必须有普通 http(s) 活动标签页，扩展管理页本身不能作为自动化目标。

## 5. 产物

| 产物 | sha256 |
|---|---|
| `entry-default-signed.hap` | `3cc36549a7e543202141ca5a86cca47d1b6d0cc6306d6447153adc092abd7b76` |
| `dsh-core-0.2.1-rc.2+dshm.78-openharmony-arm64.zip` | `d765b00bd5856e33871341d1bf51e0a16949b43374592f0e8b634eb042bbba6e` |

