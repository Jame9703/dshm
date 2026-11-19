# 浏览器主动拉起与 newtab 陷阱修复

> 日期：2026-10-22
>
> 来源：`~/harness/DSHM-浏览器桥-全链路检测报告-2026-10-22.md`
>
> 结论：`+dshm.84` 已修复“只有 browser_navigate 会拉起浏览器”和
> “拉起后停在 chrome://newtab，后续工具全部失败”两段问题。

## 1. 根因

检测报告确认：

1. 旧插件只在 `browser_navigate` 内调用 `ensureClient(url)`；
   `browser_status` 以及其他浏览器工具遇到 `clients=[]` 时直接报错。
2. 第一版无 URL 唤醒只启动浏览器主 Ability，浏览器落在 `chrome://newtab`。
   扩展虽然回连成功，但海泰不允许 CDP/脚本操作 `chrome://`；
   `navigate` 又因 `clients=1` 跳过拉起，随后报“没有可驱动的网页标签页 / 无候选 tab”。
3. `browser_navigate` 的恢复条件只匹配“没有已连接的浏览器扩展”，
   不匹配“无候选 tab”，所以上述状态不会自愈。

## 2. 修复

### 2.1 可驱动启动页

Host 新增普通 http 页面：

```text
GET /dshm-browser/start
```

所有浏览器工具在 `clients=[]` 时：

```text
工具调用
  -> /dshm-open-link?url=<baseUrl>/dshm-browser/start
  -> 显式 startAbility(com.haitai.htbrowser)
  -> 打开普通 http 启动页
  -> 扩展回连
  -> 执行原工具
```

启动页包含标题、按钮和输入框，但不会自动访问外部业务网站。

### 2.2 newtab 自愈

`browser_navigate` 遇到以下任一错误时不再直接失败：

```text
没有可驱动的网页标签页
无候选 tab
```

插件会强制绕过“已有扩展连接”的早退，带上**目标 URL** 再执行一次
`/dshm-open-link`，让海泰激活目标页，然后重试 CDP 导航。

## 3. 真机验收

设备：`MNTXM-24B / 2in1 / API 26`。

测试前强制停止海泰浏览器，桥为 `clients=[]`。

真实 `browser_status({})`：

```json
{
  "statusMs": 3627,
  "status": {
    "ok": true,
    "connected": 1,
    "screenshot": "unsupported(haitai-kernel)",
    "detail": "connected=1; screenshot=unsupported(haitai-kernel); launch=launched-and-connected; ws_1: DSHM Browser Bridge v0.11.2"
  }
}
```

紧接着 `browser_tabs`：

```text
31 ms
活动页 = http://127.0.0.1:<host-port>/dshm-browser/start
```

不再出现只有 `chrome://newtab` 的重启陷阱。

随后 `browser_navigate(https://example.com)`：

```text
1656 ms
load=complete
via=cdp-pagenavigate
tabId 与启动页相同
```

即导航复用启动页标签，而不是另开一个无法驱动的页面。

## 4. 构建与门禁

| 项 | 值 |
|---|---|
| 核心 | `0.2.1-rc.2+dshm.84` |
| 核心 zip 大小 | `99,245,855 B` |
| 核心 zip SHA-256 | `547cc3b65fe47d7006a30394bac68e3fa94e4e294c262964e526bce5d1f44931` |
| HAP | `322.9 MiB` |
| 安装 | `hdc install -r` 成功 |
| 用户数据 | `links=12 → 12` |
| 原生 exec | 10/10 |

通过：

- `check-open-link-bridge`：主体 28/0，8 个对照臂；
- `check-browser-autoclose`：主体 26/0，10 个对照臂；
- `check-browser-screenshot`：主体通过，3 个变异体；
- resfile 核心容器一致性；
- PC 权限仍恒 11 条；
- 文档引用门禁。

## 5. 工具面

真实注册工具：

```text
browser_status
browser_navigate
browser_tree
browser_click
browser_text
browser_type
browser_tabs
browser_tab_select
browser_network
```

`browser_screenshot` 保持不注册，截图兼容调用继续 fail-fast。

