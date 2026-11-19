# DSHM 1.1.6 AGC 第 4 项
# DeepSeek 开源许可与商标合规调研

> 调研日期：2026-10-28
>
> 关联版本：DSHM `1.1.6 / 1010007`
>
> 关联审核意见：AGC 上架审核报告第 4 项
>
> 调研范围：DeepSeek 代码、模型、Harness 品牌规范、DeepSeek 服务条款、华为应用市场审核规则

---

## 1. 结论摘要

AGC 第 4 项不能靠一句“DeepSeek 是开源的”解决。

核心事实是：

1. **DeepSeek Harness 的代码许可确实宽松。**
   - 官方仓库使用 MIT License。
   - 允许商业使用、修改、合并、发布、再许可和销售。
   - 分发代码或代码的重要部分时，必须保留 DeepSeek 的版权声明与 MIT 许可文本。

2. **MIT 只解决代码版权，不授予商标、Logo 或官方背书。**
   - DeepSeek 官方品牌规范明确说：项目名称应避免直接使用完整的 `DeepSeek Harness`。
   - `DeepSeek Harness` 是深度求索的注册商标。
   - 官方允许在描述性文字中使用“基于 DeepSeek Harness 构建”或“兼容 DeepSeek Harness”，但不允许用作品牌名称或制造官方合作、授权、背书印象。

3. **当前 1.1.6 确实存在明显的名称、图标和内容相似。**
   - 商店截图显示 `deepseek HARNESS` 字标。
   - 商店截图显示 DeepSeek 鲸鱼图形。
   - 应用桌面图标、启动页图标和 Agent 图标继续使用鲸鱼视觉。
   - 权限说明和 Agent 描述继续出现 `DeepSeek Harness`。
   - 因此只修改商店标题或只提交 MIT LICENSE，不能解决审核员看到的混淆。

4. **推荐的整改路线是“独立品牌 + 保留开源合规”。**
   - 商店名称保持 `DSHM`。
   - 将所有鲸鱼图形替换为不属于 DeepSeek 品牌体系的原创标识。
   - 将用户可见产品名统一为 `DSHM`。
   - 移除首页、欢迎页、侧栏、截图中的 `deepseek HARNESS`。
   - 在“关于 / 开源许可”中保留事实性归属、MIT 文本和第三方许可。

5. **如果必须继续使用 DeepSeek 品牌，应取得书面商标授权。**
   - 开源许可证不能替代商标授权。
   - 授权范围应覆盖应用名 `DSHM`、包名、具体商标/Logo、华为应用市场分发、地域、期限和商业使用。

> 本文是产品与上架合规调研，不替代正式法律意见。若准备继续使用 DeepSeek 名称、鲸鱼图形或官方视觉，应另行进行法律确认。

---

## 2. DeepSeek 各类对象的许可边界

截至调研日期，DeepSeek 官方仓库和相关文件的实际口径如下。

| 对象 | 官方许可 | 是否允许商业使用 | 主要合规义务 |
|---|---|---:|---|
| DeepSeek Harness 代码 | MIT | 是 | 分发时保留版权声明和 MIT 许可文本 |
| DeepSeek-R1 代码与模型权重 | MIT | 是 | 保留 MIT 声明；蒸馏模型还受 Qwen、Llama 等上游许可约束 |
| DeepSeek-V3 代码 | MIT | 是 | 保留 MIT 声明 |
| DeepSeek-V3 模型权重 | DeepSeek License Agreement | 是，但带使用限制 | 附带许可全文、保留声明；衍生分发继续遵守使用限制 |
| DeepSeek 网站、App、API | 服务协议，不属于开源许可范围 | 取决于服务条款 | 不得未经许可使用商标、Logo、显著品牌特征 |
| DeepSeek 商标、商号、Logo | 不在 MIT/模型许可授权范围内 | 需单独授权 | 不得用作品牌名称或暗示官方关系 |

### 2.1 DeepSeek Harness

官方仓库：

- <https://github.com/deepseek-ai/deepseek-harness>

官方 README 的许可证章节写的是：

> [MIT](https://github.com/deepseek-ai/deepseek-harness/blob/master/LICENSE)

官方 LICENSE 的核心内容：

- 允许使用、复制、修改、合并、发布、分发、再许可和销售。
- 允许将软件提供给他人。
- 要求在软件副本或重要部分中保留上述版权声明和许可声明。
- 软件按 `AS IS` 提供，不附带担保。

这意味着 DSHM 可以：

- 修改 DeepSeek Harness 的界面。
- 替换其中的品牌字标和图标。
- 将修改后的版本作为独立应用分发。
- 对该应用进行商业发布。

但必须：

- 保留 DeepSeek 的 MIT 版权和许可声明。
- 保留第三方依赖的许可与 NOTICE。
- 不把 MIT 误写成商标授权。

### 2.2 DeepSeek-R1

官方仓库：

- <https://github.com/deepseek-ai/DeepSeek-R1>

README 的许可证章节写明：

- 代码仓库和模型权重均使用 MIT License。
- 支持商业使用。
- 允许修改、衍生和蒸馏训练其他模型。

但蒸馏模型还需要注意：

- DeepSeek-R1-Distill-Qwen 系列基于 Qwen，受 Apache 2.0 许可影响。
- DeepSeek-R1-Distill-Llama 系列基于 Llama，受对应 Llama 许可影响。

### 2.3 DeepSeek-V3

官方仓库：

- <https://github.com/deepseek-ai/DeepSeek-V3>

DeepSeek-V3 将代码和模型权重分开许可：

- 代码：MIT。
- 模型权重：DeepSeek License Agreement。

模型许可允许商业使用，但因为包含使用场景限制，严格说不能称为完全没有限制的传统开源模型许可。

模型许可第 8 条明确规定：

> Nothing in this License permits You to make use of DeepSeek' trademarks, trade names, logos or to otherwise suggest endorsement or misrepresent the relationship between the parties.

也就是说：

- 可以使用模型。
- 可以使用代码。
- 不能使用 DeepSeek 商标或 Logo。
- 不能暗示 DeepSeek 对产品背书。

### 2.4 DeepSeek 网站、App 和 API

DeepSeek 网站与 App 不是单纯依靠 MIT 仓库分发的产品。

官方《DeepSeek 用户协议》第 6 条规定：

- 深度求索对软件、代码、模型权重、界面、文字、图表、版面设计、商标等享有权利。
- 未经许可不得使用“深度求索”“DeepSeek”、服务标记、商号、域名、Logo、URL 或其他显著品牌特征。

如果 DSHM 只是让用户自行配置 DeepSeek API：

- 代码许可不是这个场景的唯一依据。
- 还要遵守 DeepSeek 的 API 和相关服务条款。
- 可以在必要范围内事实性说明“支持 DeepSeek API”。
- 不应把 DeepSeek Logo 或官方 App 视觉作为 DSHM 的品牌中心。

---

## 3. DeepSeek Harness 官方品牌规范

官方文件：

- [DeepSeek Harness 品牌素材使用规范（中文）](https://github.com/deepseek-ai/deepseek-harness/blob/master/BRAND_GUIDELINES.zh.md)
- [DeepSeek Harness Brand Guidelines（英文）](https://github.com/deepseek-ai/deepseek-harness/blob/master/BRAND_GUIDELINES.md)

官方规范的四条核心规则：

### 3.1 可以在描述文字中说明真实关系

官方原文：

> 在项目的描述性文字中，您可以使用“DeepSeek Harness”真实、准确地说明您的项目与 DeepSeek Harness 的关系，例如“基于 DeepSeek Harness 构建”或“兼容 DeepSeek Harness”等。

因此，在“关于”和“开源许可”页面中写明事实来源，是合理的：

> DSHM 是基于 MIT 许可的开源 DSH / DeepSeek Harness 构建的独立鸿蒙客户端。

### 3.2 项目名称建议使用 DSH 缩写

官方原文：

> 如果您希望项目名称能体现与 DeepSeek Harness 生态的关联，我们建议使用缩写的 “DSH” 标识来命名。

当前商店名称 `DSHM` 已经比完整的 `DeepSeek Harness` 更独立，但仍要结合图标、首页和截图整体判断。

### 3.3 避免把完整名称用作品牌

官方原文：

> 在项目命名时，请避免直接使用完整的 “DeepSeek Harness” 商标。“DeepSeek Harness” 是深度求索公司的注册商标，未经授权用于项目名，容易引发用户的误解和混淆，从而影响整个生态的清晰度。同时，也可能涉及商标侵权行为。

因此：

- `DSHM` 可以作为独立产品名继续使用。
- 不应把 `DeepSeek Harness` 作为 DSHM 的产品主名称、副标题、图标文字或商店关键词。
- 商店截图中的 `deepseek HARNESS` 字标必须移除。

### 3.4 不得制造官方背书印象

官方原文：

> 请您避免在宣传或展示时，以容易引起误解的方式使用官方品牌素材，以免让用户产生官方背书、合作或授权等不实印象。

因此不应使用：

- DeepSeek 官方鲸鱼图标。
- DeepSeek 官方 App 的鲸鱼品牌布局。
- “官方”“授权”“合作”等容易造成关系误认的表述。
- 与 DeepSeek 官方 App 高度近似的首页、欢迎页和商店截图。

---

## 4. 华为 AGC 第 4 项的判据

AGC 原文：

> 您的应用与“deepseek”应用的名称/图标/内容相似，但未提供相关授权或商标权属证明，可能导致用户产生混淆、误认或不适宜的联想。

### 4.1 华为审核指南第 9.5 项

官方文件：

- [华为应用市场审核指南](https://developer.huawei.com/consumer/cn/doc/doccenter-submission/50104#section156551256407)

原文：

> 9.5 开发者不得实施混淆行为，误导用户认为应用及其内容来源于他人或与他人存在特定联系（如在任何语言下均不得使用与其他开发者应用相同/相似的外观、名称、主题等）。

第 9.3 项还规定：

> 在不构成法定正当使用的情况下，开发者未经授权不得使用他人相同或近似商标，否则将有可能构成商标侵权或不正当竞争。

这说明审核重点不是“源码是否开源”，而是安装后是否会让消费者误以为：

- 这是 DeepSeek 官方应用。
- 这是 DeepSeek 官方合作版本。
- 这是经过 DeepSeek 授权的鸿蒙版本。

### 4.2 MIT 许可证不能回答 AGC 的商标问题

AGC 要求的是：

- 相关授权，或
- 商标权属证明。

MIT License：

- 是软件著作权许可。
- 不是商标许可。
- 不是官方合作关系证明。
- 不是应用名称和 Logo 的授权书。

因此仅上传 DeepSeek Harness 的 LICENSE，不能证明 DSHM 有权使用 DeepSeek 的名称、鲸鱼图形或官方视觉。

---

## 5. 当前 1.1.6 的具体相似点

### 5.1 PC / 2in1 商店截图

文件：

- [dshm-2in1-01-home.jpg](./screenshots/2in1-1080p/dshm-2in1-01-home.jpg)

可见：

- 左上角 `deepseek HARNESS` 字标。
- 左侧鲸鱼图形。
- 中央欢迎区继续显示鲸鱼。
- 整体主界面与 DeepSeek Harness 官方产品视觉一致。

### 5.2 平板商店截图

文件：

- [dshm-tablet-01-home-terminal.jpg](./screenshots/tablet/agc-1920x1280/dshm-tablet-01-home-terminal.jpg)

可见：

- 左上角 `deepseek HARNESS`。
- 中央欢迎区鲸鱼图形。
- 官方产品式深浅色布局。

### 5.3 手机商店截图

文件：

- [dshm-phone-01-home.jpg](./screenshots/phone/agc-1080x1920/dshm-phone-01-home.jpg)

可见：

- 大尺寸鲸鱼图形。
- 与 DeepSeek 官方鲸鱼视觉高度相近的欢迎页。

### 5.4 应用图标

文件：

- [桌面图标前景](../entry/src/main/resources/base/media/foreground.png)
- [启动页品牌图](../entry/src/main/resources/base/media/logo_dark.png)
- [Agent 图标](../entry/src/main/resources/rawfile/common/dshm_agent_icon.png)

这些资源继续采用鲸鱼图形。即使图形经过重新绘制，只要核心轮廓、鲸鱼主体、眼睛和整体观感仍然接近 DeepSeek，审核员仍可能按“相似图标”处理。

当前仓库中已有 [图标概念目录](../docs/brand/app-icon-concepts/)，但多数概念仍使用鲸鱼母题。它们即使标注了“原创、无第三方商标”，也不等于审核员一定不会判断为近似。建议后续选择**完全脱离鲸鱼外形**的标识。

### 5.5 应用内文案

当前仍能看到：

- 权限说明中的 `DeepSeek Harness Host`。
- Agent 描述中的 `DeepSeek Harness（DSHM）`。
- 登录和浏览器回跳流程中的 DeepSeek 品牌文案。

权限说明和系统级 AgentCard 会进入安装包与系统界面，不能只处理商店描述。

---

## 6. 合规整改路线

## 路线 A：独立 DSHM 品牌，推荐

这条路线不需要 DeepSeek 商标授权，因为 DeepSeek 不再承担产品品牌角色。

### 6.1 商店元数据

- 应用名称：`DSHM`
- 副标题：不要再出现 `DeepSeek` 或 `DeepSeek Harness`
- 关键词：不要使用 DeepSeek 品牌词作为名称或流量词
- 简介：使用“本地 AI 编程工作台”“插件化开发环境”等中性描述
- 图标：原创或已取得完整权利的 DSHM 标识
- 图标背景：使用纯色、不透明背景，同时解决审核报告第 3 项

### 6.2 应用图标与启动页

需要替换：

- `AppScope/resources/base/media/foreground.png`
- `AppScope/resources/base/media/background.png`（如与新图标配套）
- `entry/src/main/resources/base/media/foreground.png`
- `entry/src/main/resources/base/media/logo_dark.png`
- `entry/src/main/resources/rawfile/common/dshm_agent_icon.png`
- 手机模块中的同名资源
- 快捷方式图标和其他 DeepSeek 鲸鱼变体

建议选择：

- 终端提示符。
- 方括号或代码块。
- `DSHM` 字母组合。
- 文件与任务轨迹的抽象图形。
- 完全原创的几何标识。

不建议：

- 继续使用鲸鱼轮廓。
- 把鲸鱼旋转、拆解、换色或加圆环。
- 使用与 DeepSeek 官方图标相似的蓝紫渐变和鲸鱼构图。

### 6.3 应用内界面

需要统一为 DSHM 品牌：

- 启动等待页。
- PC 和平板左上角。
- 手机欢迎页。
- 侧栏或抽屉顶部。
- 页面标题。
- 登录后引导。
- 浏览器返回文案。
- 系统权限说明。
- AgentCard 描述。
- 快捷方式说明。

用户可见系统文案建议：

```text
连接你指定的 DSHM Host（本机或局域网/隧道地址）以收发会话与事件
```

AgentCard 建议：

```text
DSHM 的端侧会话智能体：接收系统侧请求，在 DSHM 中执行会话相关操作（如新建会话）。
```

### 6.4 商店截图

所有截图重新制作，确保：

- 状态栏和窗口标题使用 DSHM。
- 首页不再出现 `deepseek HARNESS`。
- 不再出现鲸鱼图形。
- 设置页显示模型提供方时，可以出现必要的兼容性文字，但不得使用 DeepSeek 官方 Logo。
- 截图不能仅裁掉品牌区域，最好使用整改后的真实安装包重新截取。

### 6.5 开源许可与归属

独立品牌不等于删除开源归属。

应保留：

- DeepSeek Harness 的 MIT 许可证文本。
- DeepSeek 原始版权声明。
- `THIRD_PARTY_NOTICES.md` 或等价的第三方许可清单。
- Qwen、Llama、Node、QEMU、Alpine、ffmpeg 等实际捆绑组件的许可与 NOTICE。

可以在“关于”或“开源许可”页写：

```text
DSHM 是基于 MIT 许可的开源 DSH / DeepSeek Harness 构建的独立鸿蒙客户端。
DeepSeek、DeepSeek Harness 及相关标识归其权利人所有。
DSHM 与 DeepSeek 不存在隶属、授权、代理、背书或其他特定关系。
```

该说明应放在关于或许可页面，不应成为商店图标和首页的视觉中心。

### 6.6 功能兼容文案

如果产品确实支持 DeepSeek API 或模型，可以保留必要的事实性兼容说明，例如：

```text
支持用户自行配置 DeepSeek API
```

注意：

- 只在用户配置模型的上下文出现。
- 不使用 DeepSeek Logo。
- 不使用“官方”“认证”“推荐”“合作”等词。
- 不把兼容性描述成产品名称。
- 如果 AGC 仍从严审核，商店截图可以完全不展示该文案。

---

## 路线 B：继续使用 DeepSeek 品牌，取得书面授权

如果业务确实需要保留：

- `DeepSeek Harness` 产品名。
- DeepSeek 鲸鱼图标。
- 官方 App 风格。
- `官方`、`合作`、`授权` 等关系描述。

则必须取得权利人的书面授权。

授权文件建议至少包含：

- 授权方。
- 被授权方。
- 被授权应用名称：`DSHM`。
- 包名：`com.dshm.dshclient`。
- 具体商标、名称和 Logo。
- 华为应用市场分发权。
- 是否允许修改和再分发。
- 商业使用范围。
- 授权地域。
- 授权期限。
- 授权方公章。
- 授权日期。

华为《应用资质审核要求》：

- <https://developer.huawei.com/consumer/cn/doc/doccenter-submission/80301>

该页面也要求授权书说明授权方、被授权方、应用名称、授权细则、期限、公章和日期。

---

## 7. 不建议的三类做法

### 7.1 只提交 MIT LICENSE

问题：

- MIT 是软件著作权许可。
- AGC 第 4 项问的是名称、图标、内容和商标权属。
- MIT 文本不能证明有权使用 DeepSeek 品牌。

### 7.2 只改商店标题

问题：

- 审核员会安装应用。
- 启动页、首页、侧栏、权限说明和 AgentCard 仍会暴露 DeepSeek Harness。
- 图标仍是鲸鱼。
- 截图仍与官方产品相似。

### 7.3 把鲸鱼换色、旋转或加圆环

问题：

- 关键识别特征仍然存在。
- AGC 判据是整体混淆，不要求逐像素相同。
- “本地标注原创”不等于不会被判断为近似。

---

## 8. 推荐执行清单

### P0：影响上架

- [ ] 替换所有鲸鱼图标与启动页品牌图。
- [ ] 用纯色不透明背景重做桌面图标。
- [ ] 移除首页和侧栏的 `deepseek HARNESS`。
- [ ] 将欢迎页品牌统一为 DSHM。
- [ ] 修改权限说明里的 `DeepSeek Harness Host`。
- [ ] 修改 AgentCard 描述。
- [ ] 重新截取 PC、平板、手机全部商店截图。
- [ ] 检查安装包内不再可见 DeepSeek 官方品牌图。

### P1：许可证合规

- [ ] 保留 DeepSeek Harness MIT 许可证。
- [ ] 保留原始版权声明。
- [ ] 保留第三方 NOTICE。
- [ ] 在关于页说明项目来源与无隶属关系。
- [ ] 对实际捆绑版本逐项核验许可证，不使用“DeepSeek 全都是 MIT”的笼统表述。

### P2：后续品牌建设

- [ ] 为 DSHM 设计完全独立、可注册的图标。
- [ ] 考虑申请 DSHM 软件著作权或商标。
- [ ] 建立后续版本品牌资源检查门禁。
- [ ] 将“鲸鱼、DeepSeek Harness 字标、官方截图”列为提审前阻断项。

---

## 9. AGC 复核备注草案

整改后提交审核时，可使用以下备注：

```text
已按审核意见完成整改：

1. 已移除与 DeepSeek 应用相似的鲸鱼图标、DeepSeek Harness 字标、
   启动页品牌图及相关商店截图。
2. 应用名称、图标、启动页、首页、权限说明和 AgentCard 已统一为
   独立 DSHM 品牌。
3. DSHM 是基于 MIT 许可开源组件开发的独立客户端，与 DeepSeek
   不存在隶属、授权、代理、背书或其他特定关系。
4. DeepSeek Harness 的 MIT 许可证、版权声明及第三方 NOTICE
   已随应用保留。

请按整改后的应用包、图标和商店素材复核。
```

提交后重点检查：

- 审核员是否仍从首页看到 DeepSeek 官方视觉。
- 安装包内是否残留鲸鱼图形。
- AGC 截图是否全部使用整改后版本。
- 权限说明和 AgentCard 是否仍出现完整品牌名。

---

## 10. 官方来源

### DeepSeek 开源许可证

- [DeepSeek Harness LICENSE](https://github.com/deepseek-ai/deepseek-harness/blob/master/LICENSE)
- [DeepSeek Harness README](https://github.com/deepseek-ai/deepseek-harness/blob/master/README.zh.md)
- [DeepSeek-R1 LICENSE](https://github.com/deepseek-ai/DeepSeek-R1/blob/main/LICENSE)
- [DeepSeek-V3 LICENSE-CODE](https://github.com/deepseek-ai/DeepSeek-V3/blob/main/LICENSE-CODE)
- [DeepSeek-V3 LICENSE-MODEL](https://github.com/deepseek-ai/DeepSeek-V3/blob/main/LICENSE-MODEL)

### DeepSeek 品牌与服务条款

- [DeepSeek Harness 品牌素材使用规范](https://github.com/deepseek-ai/deepseek-harness/blob/master/BRAND_GUIDELINES.zh.md)
- [DeepSeek 用户协议](https://cdn.deepseek.com/policies/zh-CN/deepseek-terms-of-use.html)

### 华为应用市场规则

- [华为应用市场审核指南第 9.5 项](https://developer.huawei.com/consumer/cn/doc/doccenter-submission/50104#section156551256407)
- [华为应用市场应用资质审核要求](https://developer.huawei.com/consumer/cn/doc/doccenter-submission/80301)
- [华为应用市场侵权投诉处理指引](https://developer.huawei.com/consumer/cn/doc/doccenter-submission/50120)

### 本次 AGC 原始材料

- [AGC 1.1.6 上架审核报告](./AGC-1.1.6-上架审核报告-20261027.md)
- [AGC 审核意见原始 JSON](./agc-audit-info-1.1.6-20261027.json)

