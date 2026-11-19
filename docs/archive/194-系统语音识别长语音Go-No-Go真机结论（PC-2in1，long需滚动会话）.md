# 194 · 系统语音识别「长语音 Go/No-Go」真机结论（PC/2in1，2026-10-18）

> 对应施工方案 `docs/HarmonyOS生态能力接入/2026-10-18-系统语音识别与会议模式施工方案.md` 的 **Task 1**。
> 判据全部来自真机读数（PC `86E0226429000417`，HarmonyOS 2in1，API 26 目标/兼容 23），
> 原始证据在 `dist/probe/2026-10-18/`。

## 1. 结论：**GO（但必须滚动会话）**

| 判据（方案 §Task1） | 实测 | 判定 |
|---|---|---|
| 10s 有非空文本 | `long` 10s → 38 字，`onComplete` 正常 | ✅ |
| 30s 有非空文本，且不是只识别开头 | 未轮换时到 **653,440 B（≈20.4s）报 `onError 1002200003 Exceeded the maximum audio length supported`**，后 10 秒全丢（75 字） | ⚠️ 单会话有硬上限 |
| **轮换后** 30s | 600,320 B 主动收尾 → `rotate` → 新会话继续 → **118 字、0 onError** | ✅ |
| 5 分钟连续识别 | 300s → **30 次轮换、0 次 onError、1,135 字**，`written=595,840 B`（末段未满 600KB 故不再轮换） | ✅ |
| 自然停顿后不永久结束 | 探针每合成一轮插 1.2s 静音；轮换与停顿后仍继续出字 | ✅ |
| 单会话 `onComplete` < 12s | 每个 long 会话收尾都是 `onComplete recognize complete`（≈0.1~0.4s） | ✅ |
| 单进程只有一个引擎 | `SystemSpeechRecognizer` 的模块级 lease（`speechEngineBusy`） | ✅ |

**⇒ 会议模式可用**：`recognizerMode: 'long'` + **每 ≈18.75s 滚动一次会话**。

## 2. 三个必须记住的真机事实

### 2.1 long 的单会话硬上限 = 约 20.4 秒（653,440 B）

```
31371ms onState complete len=75 written=653440 err=onError code=1002200003
        Exceeded the maximum audio length supported.
```

- 该上限**与文字内容无关**（我们喂的是循环语音样本），是引擎的音频长度约束。
- 到达上限后**整段作废**：30s 探针里错误之后的 10 秒一个字都没出。
- 因此阈值取 **`ROTATE_AT_BYTES = 600000`（≈18.75s）**，主动收尾永远早于引擎报错。

### 2.2 long 与 short 的行为差异（都真机验过）

| 模式 | `onEvent`（VAD） | 结果形态 | 适用 |
|---|---|---|---|
| `short`（默认，不传 recognizerMode） | **有**（`code=1 speech started` / `code=3 stopped`） | **一句话一个会话**：VAD 判停即 `onComplete`，后续音频被忽略（10s 只出 11 字） | 普通听写（单句） |
| `long` | **无**（本次 30s/300s 一条 onEvent 都没有） | 持续累计出字，按停顿切分（`liveLen` 归零 = 一句定稿） | 会议模式（+滚动） |

⇒ 历史上"`long` 让 VAD 失效 ⇒ 整段无结果"那条结论，**只在"回放一段已录好的短音频"场景成立**；
真实流式说话时 `long` 完全可用，只是靠**句子级累计**而不是 VAD 事件。

### 2.3 系统 TTS 的 `onData` 在 PC/2in1 上不回调

```
394ms tts onStart audioType=pcm rate=16000 bit=16 ch=3
1742ms tts onComplete type=0 msg=synthesis complete
1742ms tts done calls=0 bytes=0
```

- 合成"完成"了，但 **0 次 `onData`、0 字节 PCM** ⇒ 该实现只负责「合成并直接播放」，不提供音频流。
- 后果：第一版探针喂的全是静音，"文本为空"会被误读成"引擎不行"。
- 修法（已落地）：随包放一段**离线语音样本** `rawfile/probe-speech-16k.wav`
  （58.176s / 16k / mono / s16，由桌面 SAPI `Microsoft Huihui` 合成，文本即项目进展口述），
  探针优先读 rawfile，TTS 仅作兜底；两者都无声源时 JSON 落 `stage:"no-audio"` 判死，
  绝不再把"没声音"混进"识别失败"。

## 3. 已落地的代码（本期）

| 文件 | 作用 |
|---|---|
| `entry/src/main/ets/speech/SystemSpeechRecognizer.ets` | 单引擎 lease；`short`/`long`；`appendPcm()` 到 600,000 B 自动 `rotate()`；跨会话累积文本（`updateMeetingTranscript`） |
| `entry/src/main/ets/speech/HmsSpeechBridge.ets` | Task 1 探针（`dshProbe` 启动参数触发）：rawfile 声源 → 实时 20ms/640B 喂入 → 写 `diag-meeting-probe/*.log/.json` |
| `entry/src/main/ets/entryability/EntryAbility.ets` | `--ps dshProbe long --ps dshProbeSec 300` 参数转发（onCreate / onNewWant） |
| `entry/src/main/resources/rawfile/probe-speech-16k.wav` | 探针声源（1.86 MB）；**Task 1 收尾后可删**（方案里探针页也是临时物） |

复现命令（PC 或手机都行，不需要人说话）：

```powershell
hdc shell "aa start -b com.dshm.dshmbeta -a EntryAbility --ps dshProbe long --ps dshProbeSec 300"
# 之后取 files/diag-meeting-probe/probe-long-300s-*.json
```

## 4. 对后续任务的影响

- **Task 3（普通听写切系统识别）**：用 `short`，保持"用户点停止 → 送整段 → 拿文本"的现有协议；
  `short` 单句语义与现有按钮行为一致（`docs/104` 的音频质量诊断链路不变）。
- **Task 5（会议采集）**：已按"可轮换引擎"分层 —— `MeetingSession` 用队列 + `drainPcm()` 串行
  `await appendPcm()`，轮换期间音频进队列（≤2s），轮换完立刻冲刷；WAV 落盘与识别完全解耦。
- **Task 10（门禁）**：把"单会话 600,000 B 轮换 + `1002200003` 不得出现在实现路径"写进
  `tools/check-meeting-mode.mjs`（下一轮落地）。

## 5. 本轮未验 / 风险

- **手机档未复测**：探针只在 PC/2in1 跑过；手机 `62T0225B18039433` 当时未连接。
  手机 TTS/识别实现可能不同（尤其 `onData`），但探针已走 rawfile，不依赖 TTS。
- 轮换间隙实测 **330~460 ms**（finish→新引擎 onStart），期间音频由调用方队列兜住；
  会议真机上若出现丢字，优先查队列上限（当前 100 块 ≈2s）。
- 5 分钟文本 1,135 字来自"循环同一段 58s 样本"，**不代表识别准确率**，只证明"持续出字 + 不中断"。

## 6. 关于「说话人角色区分」与所用 Kit（2026-10-18 补充）

### 6.1 当前接入的 HarmonyOS Kit（都是公开 API）

| Kit | 用途 | 代码位置 |
|---|---|---|
| Core Speech Kit · speechRecognizer | 离线中文识别（short/long + 轮换） | SystemSpeechRecognizer.ets |
| Core Speech Kit · 	extToSpeech | 探针合成语音（仅兜底，PC 上 onData 不可用） | HmsSpeechBridge.ets 探针段 |
| Audio Kit · AudioCapturer | 16k/单声道/S16LE 采集，流式落盘 | MeetingSession.ets |
| Background Tasks Kit · ContinuousTaskRequest | 会议期间后台录音长时任务（MODE_AUDIO_RECORDING） | MeetingKeepAlive.ets |
| Core File Kit · ileIo | WAV 头/正文流式写、Markdown 落盘 | MeetingSession.ets |
| Ability Kit | 麦克风权限、UIAbilityContext | MeetingSession.ets |

### 6.2 长录音：已真机验过，不是"做不到"

- 5 分钟连续识别：**30 次轮换、0 次报错、1,135 字**（§1 表）；
- 听写链路端到端：探针模拟 provider 写 <id>.req → 真实 handleRequest →
  {"text":"今天我们讨论三个问题。\n第1是项目进度。第。"}（6 秒样本）；
- 音频**流式写盘**、识别与会话轮换解耦，内存不随会议时长增长。

### 6.3 说话人分离（diarization）：公开 Kit 不提供

- @hms.ai.speechRecognizer.d.ts 的 AudioInfo.soundChannel 注释明确
  **"Currently, only channel 1 is supported"** ⇒ 无法靠多声道采集做"每人一轨"；
- 全量检索 HMS / OpenHarmony ets/api 的 .d.ts：**没有任何** speakerDiar* /
  speakerSeparation / separateSpeaker 之类的公开能力；
- 小艺慧记有角色区分，但**没有公开启动/读取 API**（施工方案 §1.3 明确不调私有入口）。

**结论**：在本方案约束（8 条权限、公开 API、离线、本机存储）下，**不能自动区分说话人**。
可选的落地形态（需用户拍板）：

1. **v1 不做角色区分**：会议纪要 = 时间轴 + 全文（当前实现），标题里注明"未区分说话人"；
2. **半自动**：转写按句切分后给每句加 A/B 标记按钮（纯 UI，零模型、零权限）；
3. **本地声纹/分离模型**（第三方 onnx）：体积、算力、准确率都要重新评估，且与"撤掉 SenseVoice 模型"的取舍冲突；
4. **云端 ASR**（带说话人分离）：需联网与隐私说明，超出当前"离线优先"口径。

## 7. 追加：`dshProbe=speak` 模式已下线（2026-10-19）

`speak` 是"设备外放 TTS 读 PROBE_TEXT"的自测模式（为了在无真人时可复现会议输入）。
用户反馈"每次启动就开始播报『今天我们讨论…』，先去掉这个怪吓人的"——一旦某个启动参数/
最近任务里带着 `dshProbe=speak`，应用每次起来都会突然出声。

处理：

- 删除 `runSpeakProbe()` 与 TTS 合成兜底函数（`synthSpeechPcm`）、`PROBE_TEXT`、`TtsChunk`；
- `requestSpeechProbe()` 白名单只认 `long` / `short` / `dictation`，**未知模式（含 speak）一律忽略**；
- `textToSpeech` 常量整条移除 ⇒ 语音桥里没有任何播报路径；
- 门禁 `check-meeting-mode` 增加判据 + 对照臂 **M12**（把 `engine.speak(` 塞回去必须判红）。

自测改用 rawfile 离线样本（`loadProbePcmFromRawfile`，静音）：10s/30s/5min 与 dictation 全程不发声。
