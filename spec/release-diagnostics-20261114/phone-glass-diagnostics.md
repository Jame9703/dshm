# Phone 玻璃诊断边界

phone WebApp 没有 GLASS_SKIN_JS。diag-glass 缺记录只能说明诊断通道缺失，不能据此承诺玻璃渲染已修复。

WebApp 在 aboutToAppear 经现有 writeDiagMarkerPublic 写入一次原生能力声明，不新增脚本或桥，不探测 CSS。组件实例通过 glassCapabilityDeclared 防止重复调用追加记录；诊断写入仍沿用已有失败处理，不将声明调用冒称文件写入成功。

记录固定包含 module:'phone'、implemented:false、effective:false、reason:'phone-shell-no-glass-skin'、cssSupport:null。null 表示 CSS 未探测，不代表支持或不支持。

phone 改动仅涉及原生能力声明，不引入 PC CSS，不修改 AI 标识、主题或其它 window 脚本，不读取正文、URL、账号，不新增技术信息 UI。验收工具按可靠模块能力区分 notapplicable、fail 和 unknown，当前验收口径见 docs/359 的玻璃验收小节。

离线验证入口为 tools/check-phone-glass-diagnostics.mjs 及其 --self-test，执行生产声明及验收函数，验证幂等性和模块能力分类。构建、出包、设备验证及统一 memory 由父任务处理；此改动不构成玻璃渲染修复或真机效果承诺。
