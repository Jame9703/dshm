# JD-017 结论：dsh-pet 桌面宿主可行性探测（阶段 1）

- **ID**：JD-017
- **执行方**：DevEco
- **日期**：2026-11-20 18:10
- **对应交接单**：[`from-workbuddy/20261120-1715-deveco-dshpet-probe.md`](../from-workbuddy/20261120-1715-deveco-dshpet-probe.md)

## 必须回填

```
JD-017 结论：PASS
dsh-pet 版本：dsh-pet@0.4.9（npm pack，tgz 69.6MB / 1207 文件）
DSH_HOME：/tmp/dsh-pet-home
宿主端口 / 代理端口：3080 / 3090
鉴权方式（header/query/cookie）：GET 路由无需鉴权（/config 无 token 也 200，与带 x-dsh-pet-token 响应逐字节一致，7706B）；POST /pose/report 设计性 403（见下）
/config 状态码 + 前 200 字符：200；{"main":{"whisperPrompt":"你是主人桌面上的Q版蓝发小女仆，会时不时碎碎念一句。说话要自然随意、短短一句（20字以内），温柔乖巧带点俏皮，说人话不啰嗦，不要解释你自己，不要提你是AI。","sleepRefuseTexts":["我在睡觉，别烦我……"],"sleepStartTexts":["好困……我先睡一会儿
渲染页截图：evidence/01-render-page-pet.jpeg（宠物+气泡+名牌+状态行同框）
宠物是否出现（插件自己的动画）：出现——「蓝毛小女仆」Q 版角色 + 语音气泡 + 名牌；2 秒内宠物区 15% 像素变化（动画在播）；自发从出生点游走至视口中偏左（moves 行为生效）
Electron 进程：无（dsh-pet 宿主为纯 node 进程，零 electron 子进程；机上仅存用户 WorkBuddy IDE 自带 4 个 electron 进程，均早于探测启动、路径为 /data/storage/el1/bundle/electron/，与 dsh-pet 无关）
控制台错误原文：无 error / 无未捕获异常。仅 8 条 warn："[warn] [dsh-pet] 实况上报未送达 pet=main"（来源 sprite.js:157；成因为宿主 standalone 模式对 POST /dsh-pet-7340/pose/report 返回 403 {"error":"请从桌宠菜单重新打开设置"}，属宿主侧设计行为，页面记 warn 后继续运行）
缺少的 petBridge 方法：无。13 个方法全部有消费方；idle 自主流程实际调用 8 个：onDisplays、setBounds、onPointerLeft、onFlightStates、onPetHit、setInputRegions、setInputBusy、setInteractive（bridge 总调用 500 次）；其余 5 个（requestKeyboardFocus、openDshSite、focusDshHost、captureScreen、reportCollide）需用户交互（菜单/聊天/开站/截屏/碰撞）才触发，本次 idle 流程未触及，非缺失
```

## 判定依据

1. **宠物渲染**：浏览器（本机 hmos browser）打开 probe URL 后，插件自己的渲染页（`runtime/electron-helper/`）完成 boot：拉 config → 建唯一 PetSprite → 播 idle 动画 → 每秒 state 轮询。a11y 树（evidence/03-a11y-layout.json）暴露：
   - 宠物元素「蓝毛小女仆」bounds [656,925][961,1286]；
   - 语音气泡「当前服务商暂不支持余额查询」「当前服务商：standalone」（whisper 系统工作）；
   - 探测状态行 `probe: configOk=true sprites=1 bridge=500 {"onDisplays":1,"setBounds":396,"onPointerLeft":1,"onFlightStates":1,"onPetHit":1,"setInputRegions":42,"setInputBusy":42,"setInteractive":16}`。
2. **动画在播**：相邻 2 秒两帧截图（evidence/01、02）在宠物区逐像素对比，15% 像素变化（呼吸 idle + 游走），气泡区 0%（文本稳定）——是角色动画而非噪声。
3. **无 Electron**：`npm install --omit=dev` 后 node_modules 无 electron（dsh-pet 运行时依赖不含 electron，仅 @electron/get 下载器库与 @electron-internal/extract-zip，均未触发下载）；宿主进程 `node lib/standalone.js` 无子进程；host.log 无 electron/下载/spawn 行。
4. **素材全通**：13 个脚本、config、字体（上首软糖体.ttf 4MB）、cursor-grab.png、`/thumb/main/<动画名>.webm`（380-580KB/条）均 200；页面还自动拉了 whisper 动画「是啊呵，吃什么.webm」。

## 与交接单的偏差记录

- 步骤 7 要求把第一只宠物设为桌面可见：默认配置 `main.pets[0].display` 已是 `"both"`，无需改配置、无需重启宿主，跳过该步。
- stub 按交接单 13 方法 no-op 落地为 `pet-bridge-stub.js`，另附加页面内诊断（错误浮层 + 每秒状态行），便于无 devtools 的真机截图取证（evidence/10、11）。
- 宠物出生后自主游走（moves 配置生效），最终停驻视口中偏左；出生点 top-right 由 `setBounds` 序列（396 次调用）动态维护，非静态摆位。

## 宿主侧已观察到的行为（供阶段 2 参考）

- **CSP**：渲染页 `script-src 'self'`，宿主注入脚本必须以**同源外部文件**形式提供，内联 script 会被 CSP 拦截；style-src 含 'unsafe-inline'。
- **素材路由**：视频走 `/dsh-pet-7340/thumb/<assetRoot=petId>/<动画名>.webm`（非 `/webm/` 直挂）；字体 `/font/`、光标 `/pic/`、长轮询 `/state?since=…&timeout=1000`、位姿上报 `POST /pose/report`。
- **鉴权面**：standalone 宿主 GET 路由全开放；`pose/report` 返回 403「请从桌宠菜单重新打开设置」。DSHM 宿主若要吸收该上报，需自行决定实现或忽略（页面容错良好，仅 warn）。
- **桥消费节奏**：setBounds 高频（窗口跟随，idle 下累计 396 次）、setInputRegions/setInputBusy/setInteractive 每次动作切换成组调用——ArkTS 侧映射时输入区域与窗口位置要低延迟。

## 证据

- 目录：[`20261120-dsh-pet-probe-evidence/`](20261120-dsh-pet-probe-evidence/)（SHA256SUMS 全绿）
- 01/02 渲染页相邻 2s 截图；03 a11y DOM 树；04/05 代理与宿主日志；06/07 config 双份；08 standalone-runtime.json；09-11 代理脚本、桥 stub、probe 页。

## 遗留

- 阶段 2（ArkTS 透明子窗 + petBridge 映射）归 WorkBuddy，按上节「宿主侧已观察到的行为」落地。
- 探测用进程与临时目录已清理；`DSH_PET_IN_PROCESS=1` 未进任何正式包环境。
