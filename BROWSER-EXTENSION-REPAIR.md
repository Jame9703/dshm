# DSHM 鸿蒙 PC 浏览器扩展修复入口

完整说明见：

`docs/226-鸿蒙PC浏览器扩展故障复核与重适配（CUSTOM_SANDBOX后）.md`

一句话结论：

```text
CUSTOM_SANDBOX、Host、扩展、WebSocket、CDP、navigate/text/tabs 都正常；
真实失败项是海泰内核不支持扩展 screenshot。
下一步应移除 screenshot 能力声明并停止注册 browser_screenshot，
而不是继续改权限、token、端口或延长超时。

当前状态：已完成以上重适配，核心为 `0.2.1-rc.2+dshm.84`；扩展
`0.11.2 / dshm-host-bridge-13` 已从
`Download/com.dshm.dshclient/dshm-browser-ext-v012` 加载并连接。设备能力声明
已确认 `screenshot=false`，浏览器导航、正文、树、标签页、网络、CDP、点击、
输入、切页和关闭均实测通过。所有浏览器工具在扩展未连接时会主动拉起海泰并打开
`/dshm-browser/start` 普通 http 页面；导航遇到 `chrome://newtab` 会按目标 URL
重新拉起并重试。
```
