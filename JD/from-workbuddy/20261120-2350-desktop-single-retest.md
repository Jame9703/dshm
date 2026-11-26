# desktop 单端最小复测单（门控 / 黑框 / 拖动）

> 用户决策 2026-11-20 23:47：**先按 `desktop` 单端复测，确认门控 / 黑框 / 拖动都过再动**。
> 本轮**不改 ArkTS、不重出包、不改 `both` 语义**；包仍是 `dist/beta/DSHM-beta-1.1.8-1010019-20261120T150928/`（app sha `7b45f911…`）。
> `both`、DSHM 联动、10 分钟稳定性、触摸/置顶/菜单等全量项本轮**不测**。
> 背景见 `20261120-2340-dsh-pet-beta-feedback-triage.md`；全量用例见 `20261120-2320-pet-beta-test-prompt.md`。

---

## 0. 复测前置（不做这步，后面三项全是假失败）

设备当前 `display=web`（诊断手册 §1/§6 改的），**Beta 门控只认 `desktop|both`**，沿用 `web` 时桌宠不启动、无黑框是预期行为。先改回 `desktop`：

```bash
TOKEN=$(python3 -c "import json;print(json.load(open('/data/storage/el2/base/haps/entry/files/dsh/home/host-ready.json'))['token'])")
curl -s -H 'Content-Type: application/json' -d '{"id":"main","display":"desktop"}' \
  "http://127.0.0.1:3121/dsh-pet-7340/pet-display?token=$TOKEN"

# 必须看到输出里第二项是 desktop
curl -s "http://127.0.0.1:3121/dsh-pet-7340/config?token=$TOKEN" \
  | python3 -c "import sys,json;p=json.load(sys.stdin)['main']['pets'][0];print(p['id'],p['display'],p['size'])"
```

再排掉两个干扰源（否则「只有气泡」会被误判成黑框/门控问题）：

```bash
python3 ~/Download/dsh-pet-fix-assets.py --check   # 应为 0 个待修复
curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:3121/dsh-pet-7340/thumb/main/待机呼吸休闲.webm?token=$TOKEN"   # 应为 200
```

**完全退出 DSHM 再启动**（不是切后台）。确认是覆盖安装、未卸载、未重装插件。

---

## 1. 三项判据（只测这三项）

| # | 项 | 操作 | PASS 判据 | FAIL 特征 |
|---|---|---|---|---|
| 1 | **门控** | ① 启动后等 2s；② 改 `display=web` 等 2s；③ 改回 `desktop` 等 2s | ① 桌面出现**插件自己的小人**（不是 DSHM 画的圆）且无黑框；② 小人 + 子窗**一起消失、无残留**；③ 重新出现 | 该出现时不出现，或该消失时不消失，或 `web` 下仍在（门控没生效） |
| 2 | **黑框** | 全程观察：启动瞬间 / 宠物漫游到屏幕右缘 / 切到浏览器微信再切回 / 空闲 10s / 步骤 1 的 ②③ 切换后 | 任何时刻都**没有** `dsh-pet-host` 黑框、没有 320×100 白色/黑色残条、没有第二个空窗 | 出现独立空窗、宿主主窗露边、切换后残留窗口 |
| 3 | **拖动** | 鼠标按住小人拖 300–500px，**做 3 次**（水平 / 垂直 / 斜向），记录指针位移与窗口位移 | 3 次比例都 ≈**1.0**（窗口 1:1 跟手） | 比例 ≈**0.36**（即 JD-019 的 ÷1.75² 未修复）或完全不动 |

三项都要带证据：门控/黑框录屏（含切换时机），拖动记 3 个实测比例数字。

---

## 2. 日志（一条命令，全程开着）

```sh
hilog | grep -E "dsh-pet-host|entry/pet"
```

| 期望行 | 含义 |
|---|---|
| `[dsh-pet-host] /dsh-pet-native 已注册，pluginRoot=...profiles/ondevice/node_modules/dsh-pet` | 插件路径 + 静态路由 OK |
| `entry/pet: pet subwindow ready: ...probe.html?...` | 子窗建起来了 |
| `无 desktop/both 宠物，PetAbility 退出` | 只在 `display=web` 那一步该出现 |
| `desktop 宠物已关闭，PetAbility 退出` | 运行期自检收起 |
| `/dsh-pet-native 不可用（插件路径未找到/路由未注册）` | **不该出现**；出现即 FAIL，把 `pluginRoot` 一起带回 |

---

## 3. 判定分流

- **三项全 PASS** → 才进入下一步：定 `both` 双份宠物语义（网页 overlay + 子窗二选一），再决定是否重出包。
- **门控 FAIL** → 先核对 §0 的 `display` 实际值与 `config` 返回；若确为 `desktop` 仍不启动，带回 `hilog` 三段（启动 / 改 web / 改回 desktop）。**先判配置，不改代码**。
- **黑框 FAIL** → 带回出现时机 + 截屏 + `host move rejected` / `setBounds` 相关日志；区分是宿主主窗露边还是独立空窗。
- **拖动 FAIL（0.36 复现）** → 说明 shim 的 `screenX/Y` 还原没生效；带回 `window.devicePixelRatio` 与页面里 `MouseEvent.prototype.screenX` 是否被改写（F12），定位「shim 未注入」还是「dpr≠1.75」。
- **只有气泡 / 空白小人** → 不属这三项，单独标注：素材 404（跑 `--fix`）或 VP9 `MEDIA_ERR_SRC_NOT_SUPPORTED`（手册 §5），别混进门控/黑框判定。

---

## 4. 回填模板（直接填）

```
设备/系统/API：
包：150928 覆盖安装（未卸载/未重装插件）：是 / 否
§0 前置：display 实际值 __ → 改回 desktop 后 config 输出 __
        素材 --check 待修复 __ 个；待机呼吸休闲.webm HTTP __

① 门控：desktop出现__s / web消失且无残留__s / 改回再出现__s  → PASS / FAIL
② 黑框：启动 / 右缘 / 切应用 / 空闲10s / 切换后 分别有无 → PASS / FAIL
③ 拖动：3 次比例 __ / __ / __  → 1:1 PASS / 0.36 FAIL / 其它 __

日志关键行（或说明缺哪行）：
录屏/截图：
其它异常（只有气泡/VP9/首次安装报错等，单列）：
```

**结论行**：三项全过 → 待你决定是否动 `both`；任一不过 → 按 §3 带证据回来，本轮仍不改代码、不重出包。
