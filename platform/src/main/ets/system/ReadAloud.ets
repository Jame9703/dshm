/**
 * 原生朗读（2026-11-15）。
 *
 * 【为什么单独一层】朗读是**系统能力**，不是页面状态：Speech Kit 的 `TextReader`
 * 自带播放面板 / Minibar / 通知 / AVSession / 后台播放；Core Speech Kit 的
 * `textToSpeech` 是无面板的兜底。两套都要求「同一进程只初始化一次」的引擎语义，
 * 放在页面里会被重建/重复 init 打穿，因此收成平台层单例，两个壳共用。
 *
 * 【首选 TextReader，失败降级 textToSpeech】
 *   · TextReader 需要 `SystemCapability.AI.Component.TextReader`（phone/tablet 5.0.0、
 *     2in1 5.0.1 起），且 `init` 要求已声明的 `KEEP_BACKGROUND_RUNNING`；
 *   · 能力不存在 / init 失败 / start 失败 ⇒ 退回 textToSpeech（无面板、仅播报）。
 *   · 两套都只在本机离线合成（`online: 1`），回复文本不出设备。
 *
 * 【为什么不用 chat-demo 的流式 PCM】那是浏览器 WebAudio 路径；鸿蒙侧 TextReader
 * 已经负责合成、播放、暂停/继续、后台与播控，照搬只会多一层不可控状态。
 *
 * 【边界】文本由调用方负责（Web 侧已剥掉 Markdown 标记）；本模块只做长度保护：
 * textToSpeech 单次上限 10,000 字符，超长截断；TextReader 走单篇正文。
 */

import { ReadStateCode, TextReader, WindowManager } from '@kit.SpeechKit';
import { window } from '@kit.ArkUI';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xD5A1;
const TAG: string = 'platform/readaloud';
/** textToSpeech.speak 的硬上限（文档：不超过 10,000 字符） */
const TTS_MAX_CHARS: number = 9800;

/**
 * 中文兜底音色（SDK 明示：13 = 凌晓珊女声，推荐值；0 也可用）。
 *
 * 【为什么不是"小艺"字面量】Core Speech Kit 的 `VoiceInfo.person` 没有名为"小艺"的
 * 枚举值（zh-CN 只有 13 女声 / 21 男声，男声需下载）。但系统朗读的默认音色就是
 * 小艺同款中文女声，13 是 SDK 的推荐值，因此把它作为"小艺音色"的等价默认。
 */
const XIAOYI_FALLBACK_PERSON: number = 13;

/** 音色探测结果缓存：一次启动只查一次，避免每次朗读都走一次 listVoices */
let xiaoyiPersonPromise: Promise<number> | null = null;

/**
 * 解析本机已安装的"小艺"音色编号。
 *
 * 策略（按优先级）：
 *   1. `listVoices` 返回的音色里 description 含「小艺」/「Xiaoyi」且 `status === 'INSTALLED'`
 *      ⇒ 用它的 `person`（设备真有这个音色时尊重设备）；
 *   2. 没有明确命名的小艺音色 ⇒ 用 13（SDK 推荐的中文女声，等价于系统默认朗读音色）。
 *
 * 【为什么不下载 21 男声】`downloadVoice` 会有网络与存储成本，朗读是系统能力，
 * 不该为了一个音色让首次朗读变慢或依赖网络。
 * 【失败安全】任何异常都回落到 13 —— 音色选择绝不能阻断朗读。
 */
function resolveXiaoyiPerson(): Promise<number> {
  if (xiaoyiPersonPromise !== null) {
    return xiaoyiPersonPromise;
  }
  xiaoyiPersonPromise = textToSpeech.listVoices({
    requestId: 'dshmvoices' + Date.now().toString(),
    online: 1
  }).then((voices: Array<textToSpeech.VoiceInfo>): number => {
    for (const voice of voices) {
      const desc: string = voice.description === undefined ? '' : voice.description;
      const installed: boolean = voice.status === 'INSTALLED';
      if (installed && (desc.indexOf('小艺') >= 0 || desc.toLowerCase().indexOf('xiaoyi') >= 0)) {
        hilog.info(DOMAIN, TAG, '已选用小艺音色 person=%{public}d（%{public}s）', voice.person, desc);
        return voice.person;
      }
    }
    hilog.info(DOMAIN, TAG, '本机无显式「小艺」音色，使用 SDK 推荐中文女声 person=%{public}d',
      XIAOYI_FALLBACK_PERSON);
    return XIAOYI_FALLBACK_PERSON;
  }).catch((e: BusinessError): number => {
    hilog.warn(DOMAIN, TAG, '音色探测失败（回退推荐音色）：%{public}s', e.message);
    return XIAOYI_FALLBACK_PERSON;
  });
  return xiaoyiPersonPromise;
}

/** One playback request per owner. TextReader itself is process-wide. */
export class ReadAloud {
  private static nextRequest: number = 0;
  private static textReaderOwner?: ReadAloud;
  private static textReaderQueue: Promise<void> = Promise.resolve();

  private requestId: string = '';
  private notifyEnded?: (failed: boolean) => void;
  private nativeRequest: string = '';
  private nativeStarted: boolean = false;
  private engine?: textToSpeech.TextToSpeechEngine;
  private engineInit?: Promise<textToSpeech.TextToSpeechEngine | undefined>;
  private engineGeneration: number = 0;

  private readonly onReaderState = (state: TextReader.ReadState): void => {
    if (state.id !== this.requestId || state.id !== this.nativeRequest) { return; }
    if (state.state === ReadStateCode.PLAYING || state.state === ReadStateCode.PAUSED) {
      if (!this.nativeStarted) {
        hilog.info(DOMAIN, TAG, 'TextReader 已开始播放');
        this.nativeStarted = true;
      }
    } else if (state.state === ReadStateCode.COMPLETED || (this.nativeStarted &&
      (state.state === ReadStateCode.WAITING || state.state === ReadStateCode.NOT_IN_READ_LIST))) {
      this.finish(state.id);
    }
  };

  static attachWindow(stage: window.WindowStage): void {
    if (!ReadAloud.hasTextReader()) { return; }
    try {
      WindowManager.setWindowStage(stage);
    } catch (_) {
      hilog.warn(DOMAIN, TAG, 'TextReader 窗口注册失败');
    }
  }

  start(context: common.UIAbilityContext, text: string, onEnded?: (failed: boolean) => void,
    title?: string): string {
    const clean = text.trim();
    if (clean.length === 0) { return 'empty'; }
    this.stop();
    const id = 'dshmread' + Date.now().toString() + 'n' + (++ReadAloud.nextRequest).toString();
    this.requestId = id;
    this.notifyEnded = onEnded;
    if (ReadAloud.hasTextReader()) {
      ReadAloud.queueTextReader((): Promise<void> => this.startTextReader(context, clean, id, title));
      return 'started';
    }
    this.startFallback(clean, id);
    return 'fallback';
  }

  stop(): void {
    this.finish(this.requestId);
    if (ReadAloud.textReaderOwner === this && this.nativeRequest.length > 0) {
      ReadAloud.queueTextReader(async (): Promise<void> => {
        if (ReadAloud.textReaderOwner !== this) { return; }
        this.nativeRequest = '';
        this.nativeStarted = false;
        try {
          await TextReader.stop();
        } catch (_) {
          hilog.debug(DOMAIN, TAG, 'TextReader.stop 调用失败');
        }
      });
    }
    try {
      this.engine?.stop();
    } catch (_) {
      hilog.debug(DOMAIN, TAG, 'TTS.stop 调用失败');
    }
  }

  release(): void {
    this.stop();
    ReadAloud.queueTextReader((): Promise<void> => this.releaseTextReader());
    this.engineGeneration++;
    const engine = this.engine;
    this.engine = undefined;
    this.engineInit = undefined;
    if (engine !== undefined) { this.shutdown(engine); }
  }

  private finish(id: string, failed: boolean = false): void {
    if (id.length === 0 || id !== this.requestId) { return; }
    this.requestId = '';
    const notify = this.notifyEnded;
    this.notifyEnded = undefined;
    notify?.(failed);
  }

  private static hasTextReader(): boolean {
    try {
      return canIUse('SystemCapability.AI.Component.TextReader');
    } catch (_) {
      return false;
    }
  }

  private static queueTextReader(run: () => Promise<void>): void {
    ReadAloud.textReaderQueue = ReadAloud.textReaderQueue.then(run).catch((): void => {
      hilog.warn(DOMAIN, TAG, 'TextReader 操作失败');
    });
  }

  private async openTextReader(context: common.UIAbilityContext, id: string): Promise<boolean> {
    if (ReadAloud.textReaderOwner === this) { return true; }
    const previous = ReadAloud.textReaderOwner;
    if (previous !== undefined) {
      previous.finish(previous.nativeRequest);
      await previous.releaseTextReader();
    }
    if (id !== this.requestId) { return false; }
    const settings: TextReader.ReaderParam = {
      isVoiceBrandVisible: false,
      online: 1,
      keepBackgroundRunning: true,
      isMinibarNeeded: true
    };
    try {
      await TextReader.init(context, settings);
      ReadAloud.textReaderOwner = this;
      TextReader.on('stateChange', this.onReaderState);
      hilog.info(DOMAIN, TAG, 'TextReader 已初始化');
      return true;
    } catch (_) {
      hilog.warn(DOMAIN, TAG, 'TextReader.init 失败，使用 TTS');
      await this.releaseTextReader();
      return false;
    }
  }

  private async releaseTextReader(): Promise<void> {
    if (ReadAloud.textReaderOwner !== this) { return; }
    ReadAloud.textReaderOwner = undefined;
    this.nativeRequest = '';
    this.nativeStarted = false;
    try {
      TextReader.off('stateChange', this.onReaderState);
    } catch (_) {
      hilog.debug(DOMAIN, TAG, 'TextReader.off 调用失败');
    }
    try {
      await TextReader.release();
    } catch (_) {
      hilog.debug(DOMAIN, TAG, 'TextReader.release 调用失败');
    }
  }

  private async startTextReader(context: common.UIAbilityContext, text: string, id: string,
    title?: string): Promise<void> {
    if (id !== this.requestId) { return; }
    const ready = await this.openTextReader(context, id);
    if (id !== this.requestId) { return; }
    if (!ready) {
      this.startFallback(text, id);
      return;
    }
    this.nativeRequest = id;
    this.nativeStarted = false;
    const heading: TextReader.TextInfo = { text: title || 'DSHM 回答', isClickable: false };
    const article: TextReader.ReadInfo = { id: id, title: heading, bodyInfo: text };
    const params: TextReader.StartParams = { startPercent: 0 };
    try {
      await TextReader.start([article], id, params);
      if (id === this.requestId) { hilog.info(DOMAIN, TAG, 'TextReader.start 完成'); }
    } catch (_) {
      this.nativeRequest = '';
      if (id !== this.requestId) { return; }
      hilog.warn(DOMAIN, TAG, 'TextReader.start 失败，使用 TTS');
      await this.releaseTextReader();
      this.startFallback(text, id);
    }
  }

  private async startFallback(text: string, id: string): Promise<void> {
    if (id !== this.requestId) { return; }
    const engine = await this.getEngine();
    if (id !== this.requestId) { return; }
    if (engine === undefined) {
      this.finish(id, true);
      return;
    }
    const params: textToSpeech.SpeakParams = { requestId: id };
    try {
      engine.speak(text.substring(0, TTS_MAX_CHARS), params);
    } catch (_) {
      hilog.warn(DOMAIN, TAG, 'TTS.speak 调用失败');
      this.finish(id, true);
    }
  }

  private getEngine(): Promise<textToSpeech.TextToSpeechEngine | undefined> {
    if (this.engine !== undefined) { return Promise.resolve(this.engine); }
    if (this.engineInit !== undefined) { return this.engineInit; }
    const generation = this.engineGeneration;
    this.engineInit = this.createEngine(generation).finally((): void => {
      if (this.engineGeneration === generation) { this.engineInit = undefined; }
    });
    return this.engineInit;
  }

  private async createEngine(generation: number): Promise<textToSpeech.TextToSpeechEngine | undefined> {
    let engine: textToSpeech.TextToSpeechEngine | undefined;
    try {
      const person = await resolveXiaoyiPerson();
      if (this.engineGeneration !== generation) { return undefined; }
      const params: textToSpeech.CreateEngineParams = { language: 'zh-CN', person: person, online: 1 };
      engine = await textToSpeech.createEngine(params);
      if (this.engineGeneration !== generation) {
        this.shutdown(engine);
        return undefined;
      }
      const listener: textToSpeech.SpeakListener = {
        onStart: (id: string, _response: textToSpeech.StartResponse): void => {
          if (id === this.requestId) { hilog.info(DOMAIN, TAG, 'TTS 已开始'); }
        },
        onComplete: (id: string, response: textToSpeech.CompleteResponse): void => {
          if (response.type === 1) { this.finish(id); }
        },
        onStop: (id: string, _response: textToSpeech.StopResponse): void => { this.finish(id); },
        onError: (id: string, code: number, _message: string): void => {
          hilog.warn(DOMAIN, TAG, 'TTS 错误 %{public}d', code);
          this.finish(id, true);
        }
      };
      engine.setListener(listener);
      this.engine = engine;
      return engine;
    } catch (_) {
      if (engine !== undefined) { this.shutdown(engine); }
      hilog.warn(DOMAIN, TAG, 'TTS 引擎创建失败');
      return undefined;
    }
  }

  private shutdown(engine: textToSpeech.TextToSpeechEngine): void {
    try {
      engine.shutdown();
    } catch (_) {
      hilog.debug(DOMAIN, TAG, 'TTS.shutdown 调用失败');
    }
  }
}
