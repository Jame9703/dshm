/**
 * 碰一碰真实接收（demo 版，US4）：手机轻触本机屏幕 → Share Kit 沙箱接收 →
 * 系统把文件落进本类给的目录 → 读出 + base64 → 通知壳页（KnockDemoViewModel）
 * 走与「模拟碰一碰」完全相同的注入出口（FR-009）。
 *
 * 【移植锚点】逐位移植 entry/src/main/ets/system/KnockShareReceiver.ets 全机制：
 * canIUse 守卫 / 主窗注册 / 1-2-4-8s 指数退避至多 5 次（首次 + 4 重试）/
 * 幂等 start-stop / receiveUri = demo 自身 filesDir / 落盘记账与 onResult 后按
 * uri 清理（只删文件不删目录）/ 单文件 16MiB 上限 / 挂起队列 cap 10 /
 * takePending-requeue / diag-knock 全链标记。唯一机制差异见下条。
 *
 * 【门控差异（FR-010，唯一差异项）】生产仅 PC 档注册（desktopForced：PC / 2in1 /
 * MatePad Edge / Pro Max；普通平板不注册）。**demo 无形态矩阵故不门控**：能力守卫
 * 交给 canIUse，设备不支持就只留痕不重试（spec US4 场景 3）。生产那条
 * `if (!this.desktopForced) { 留痕 skip; return; }` 在 demo 中刻意不移植。
 *
 * 【零新增权限】harmonyShare/systemShare 全程无 @permission 声明要求；demo 权限面
 * 保持 0 条（module.json5 requestPermissions 为空），与生产 18/9 铁律无关。
 *
 * 【receiveUri = filesDir 根（与生产逐位一致）】生产三轮实测后裁定与 WorkBuddy 对齐：
 * `receive(fileUri.getUriFromPath(ctx.filesDir))`；官方只硬性要求「已存在目录」。
 * 代价：传输期间整个 filesDir 短暂授权给传输方（传完自动回收）；落盘文件按 uri
 * 记账，onResult 后逐个清理，不删目录。
 *
 * 【注册重试】1/2/4/8s 指数退避、至多 5 次尝试（首次 + 4 重试），防首帧竞态一次性
 * 失败；canIUse=false 属设备永久缺能力，不重试；stop() 取消挂起的重试定时器。
 *
 * 【注册时机（2026-11-17 二次对照官方样本 KnockFileShare 修订）】
 *   ① **EntryAbility.onWindowStageCreate → bootstrap()**：建窗即创建单例并注册，
 *      用 windowStage.getMainWindowSync() 的真实主窗 id（不依赖页面、不依赖 getLastWindow）；
 *   ② 页面接管（Index.aboutToAppear → VM.startKnockReceiver）只补钩子与状态展示，
 *      并再 start() 一次（幂等空跑）。
 * 原实现挂在「碰一碰页签渲染 + Web onPageEnd」之后——未切页签/页面就绪前碰，系统侧
 * 根本没有接收方，实测表现为「文件落到系统『华为分享』文件夹」。官方样本在首页
 * aboutToAppear 即注册；本实现再提前到建窗，等价且更稳。
 *
 * 【页面未就绪的挂起】碰一碰可能发生在 Web 页重载窗口：文件先进本类挂起队列
 * （cap 10），壳页 onPageEnd（webReady）时 takePending() 补发；队列超限丢弃留痕；
 * 投递中 controller 未挂载的残余文件走 requeue() 回队（不丢）。
 *
 * 【base64 通道的上限】单文件 16 MiB：再大 runJavaScript 的脚本体积会到几十 MB，
 * 大视频本就超出「附件进输入框」的合理范围——跳过并留痕。
 *
 * 【诊断（diag-knock）】注册/接收/投递全程落 filesDir/diag-knock（Diag.knock 由壳页
 * 注入，与生产 writeDiagMarkerPublic 同一套）：start 入口 / canIUse / 窗口身份三件套
 * （type/showing/主窗对比）/ on 结果与重试 / target / result code / 队列与清理，
 * 注册失败与「注册成功但系统不投递（签名资格等）」可分开读。
 *
 * @module DemoKnockShareReceiver
 */
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { KnockFile } from '../model/DemoTypes';
import { mimeTypeForName } from './KnockShim';

const DOMAIN: number = 0xD5A1;
const TAG: string = 'DSHM-DEMO-KNOCK';

/**
 * 注册阶段（demo 追加：驱动壳页状态行；生产用 hilog + diag 即可，无此需要）。
 * unsupported = canIUse=false（永久缺能力，不重试）；registering = 本轮在试；
 * registered = 已挂上监听；failed = 本轮失败（瞬时失败会自动退避重试）。
 */
export type KnockReceiverPhase = 'registering' | 'registered' | 'unsupported' | 'failed';

export class DemoKnockShareReceiver {
  /** 进程内单例（EntryAbility 在建窗后 bootstrap，页面后接管；两处不会各注册一份）。 */
  private static instance: DemoKnockShareReceiver | undefined = undefined;
  /** 单类能力声明数（FILE/IMAGE/VIDEO/AUDIO/MEDIA 各一条，maxCount 同 WorkBuddy=5）。 */
  private static readonly MAX_PER_CAPABILITY: number = 5;
  /** base64 通道单文件上限（字节）。 */
  private static readonly MAX_FILE_BYTES: number = 16 * 1024 * 1024;
  /** 页面未就绪时的挂起队列上限（防重载窗口连碰堆积）。 */
  private static readonly MAX_PENDING_FILES: number = 10;
  /** 注册失败重试间隔（ms，同 WorkBuddy 1/2/4/8s；首次之外至多 4 次重试）。 */
  private static readonly RETRY_DELAYS_MS: number[] = [1000, 2000, 4000, 8000];

  private readonly ctx: common.UIAbilityContext;
  /** 「有新文件入队」通知（页面接管时注入；EntryAbility 先注册时为 undefined）。 */
  private filesHook: (() => void) | undefined = undefined;
  /** 诊断落盘（页面接管后替换为带界面刷新的版本）。 */
  private writeDiag: (detail: string) => void;
  /** dataReceive 回调的稳定引用（off 时按引用注销）。 */
  private readonly targetCb: (target: harmonyShare.ReceivableTarget) => void;
  /** knockShare 回调的稳定引用（官方示例同注册；demo 只留痕，不实现发送侧）。 */
  private readonly knockCb: (target: harmonyShare.SharableTarget) => void;
  /** knockShare 注销用的 windowId（off 时按 {windowId} 选项注销）。 */
  private knockWindowId: number = -1;
  /**
   * 注册阶段观察者（demo 追加，可选）：壳页据此刷新状态行。
   * 生产无此需要（hilog + diag 足够），属 demo 展示层增量，不改变注册机制。
   */
  onPhase: ((phase: KnockReceiverPhase) => void) | undefined = undefined;
  private registry: harmonyShare.RecvCapabilityRegistry | undefined = undefined;
  private pending: Array<KnockFile> = [];
  /** 本传输已落盘的文件路径（filesDir 根接收的记账：onResult 后逐个清理）。 */
  private receivedPaths: string[] = [];
  private started: boolean = false;
  private retryCount: number = 0;
  private retryTimer: number = -1;
  /** 最近一次注册阶段（phase() 读取；未尝试过为 undefined）。 */
  private currentPhase: KnockReceiverPhase | undefined = undefined;

  constructor(ctx: common.UIAbilityContext, writeDiag: (detail: string) => void) {
    this.ctx = ctx;
    this.writeDiag = writeDiag;
    this.targetCb = (target: harmonyShare.ReceivableTarget): void => {
      this.handleTarget(target);
    };
    this.knockCb = (target: harmonyShare.SharableTarget): void => {
      // 【官方示例对照】2in1 同时注册 knockShare（本机被碰时的发送侧）与 dataReceive（接收侧）：
      // 官方在 knockShare 回调里 target.share(选中文件)——demo 无 ArkTS 侧文件列表，故只留痕
      // （区分「碰一碰事件已到达本机」与「系统根本没投递」，是排查的关键断点）。
      let coord: string = '';
      try {
        // 类型推断自 getInfo()（官方示例同写法：const info = target.getInfo()）
        const info = target.getInfo();
        if (info.coordinate !== undefined) {
          coord = ` x=${info.coordinate.screenX} y=${info.coordinate.screenY}`;
        }
      } catch (e) {
        coord = ' coord-err';
      }
      this.writeDiag(`knockShare 触发${coord}（demo 无发送侧，仅留痕）`);
      hilog.info(DOMAIN, TAG, '碰一碰：knockShare 事件到达%s', coord);
    };
  }

  /**
   * 进程级引导（EntryAbility.onWindowStageCreate 调用）：创建单例并**立即注册**。
   * 用 windowStage 的主窗 id（真实主窗，比 getLastWindow 更确定），先于任何页面，
   * 对齐官方样本「一进应用就注册」的时机；页面稍后接管（setOnFiles/setWriteDiag）。
   */
  static bootstrap(ctx: common.UIAbilityContext, mainWindowId: number,
    writeDiag: (detail: string) => void): DemoKnockShareReceiver {
    const existing: DemoKnockShareReceiver | undefined = DemoKnockShareReceiver.instance;
    if (existing !== undefined) {
      return existing;
    }
    const r: DemoKnockShareReceiver = new DemoKnockShareReceiver(ctx, writeDiag);
    DemoKnockShareReceiver.instance = r;
    r.start(mainWindowId).then((ok: boolean): void => {
      r.writeDiag(`bootstrap 完成 ok=${ok} mainWindowId=${mainWindowId}`);
    }).catch((): void => {
      // start() 内部已逐项留痕并排退避重试
    });
    return r;
  }

  /** 当前单例（页面接管用；未引导时为 undefined）。 */
  static current(): DemoKnockShareReceiver | undefined {
    return DemoKnockShareReceiver.instance;
  }

  /** 页面接管：有新文件入队时通知（替代构造期绑定的回调）。 */
  setOnFiles(cb: () => void): void {
    this.filesHook = cb;
  }

  /** 页面接管：诊断落盘替换为带界面刷新的版本。 */
  setWriteDiag(cb: (detail: string) => void): void {
    this.writeDiag = cb;
  }

  /** 设备能力（canIUse 守卫的对外读数；壳页用它区分 unsupported 与瞬态失败）。 */
  capabilityAvailable(): boolean {
    return canIUse('SystemCapability.Collaboration.HarmonyShare');
  }

  /** 当前注册阶段（未尝试过返回 undefined；供壳页在页面就绪时复用真状态）。 */
  phase(): KnockReceiverPhase | undefined {
    return this.currentPhase;
  }

  /**
   * 注册沙箱接收能力（幂等）。返回 false = 本轮未注册成功（canIUse 判否 / 窗口
   * 不可得 / on() 抛），调用方只留痕，不影响壳页任何既有功能；瞬时失败由本类按
   * 1/2/4/8s 退避自动重试。每一步都落 diag-knock：真机上把「注册失败」与
   * 「注册成功但系统不投递（签名资格等）」分开。
   *
   * @param mainWindowIdHint 主窗 id。demo 为单窗应用，未发布主窗 id 故恒传 -1
   *   （诊断行记「主窗未知」，getLastWindow 失败时无可回退 → 走退避重试）。
   *   生产语义：仅用于①诊断对比（多窗时 getLastWindow 可能拿到别的窗口）
   *   ②getLastWindow 失败时的注册回退；**不作为首选注册源**。
   */
  async start(mainWindowIdHint: number = -1): Promise<boolean> {
    if (this.started) {
      return true;
    }
    if (this.retryTimer >= 0) {
      // 直接调用优先于挂起的重试：清掉定时器，本轮马上试
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
    if (this.retryCount === 0) {
      // 只在首轮置「注册中」：退避重试期间状态行保持 failed，不每秒闪回
      this.emitPhase('registering');
    }
    this.writeDiag('start enter');
    if (!this.capabilityAvailable()) {
      // 设备永久缺该能力：重试无意义
      this.writeDiag('canIUse=false 未注册');
      hilog.warn(DOMAIN, TAG, '设备无 Collaboration.HarmonyShare 能力，不注册');
      this.emitPhase('unsupported');
      return false;
    }
    this.writeDiag('canIUse=true');
    let windowId: number = -1;
    try {
      const win: window.Window = await window.getLastWindow(this.ctx);
      const props: window.WindowProperties = win.getWindowProperties();
      windowId = props.id;
      // windowType 自 API 26（旧设备 undefined → 退路取已弃用的 type，只为诊断读数完整）
      const wType: number = props.windowType !== undefined ? props.windowType : props.type;
      let showing: string = '?';
      try {
        showing = win.isWindowShowing() ? 'true' : 'false';
      } catch (e2) {
        showing = 'err';
      }
      // 窗口身份三件套 + 主窗对比：type=0(TYPE_APP)/showing=true 且与主窗一致 ⇒ 排除拿错窗口
      const mainCmp: string = mainWindowIdHint < 0 ? '主窗未知'
        : (mainWindowIdHint === windowId ? `主窗=${mainWindowIdHint} 一致` : `主窗=${mainWindowIdHint} 不一致`);
      this.writeDiag(`windowId=${windowId} type=${wType} showing=${showing} ${mainCmp}`);
    } catch (e) {
      const err = e as BusinessError;
      if (mainWindowIdHint >= 0) {
        windowId = mainWindowIdHint;
        this.writeDiag(`getLastWindow err code=${err.code} msg=${err.message} 改用主窗id=${windowId}`);
      } else {
        this.writeDiag(`getLastWindow err code=${err.code} msg=${err.message} 无主窗id可回退`);
        hilog.warn(DOMAIN, TAG, '窗口获取失败 code=%{public}d msg=%{public}s', err.code, err.message);
        this.emitPhase('failed');
        this.scheduleRetry(mainWindowIdHint);
        return false;
      }
    }
    try {
      // 【官方示例对照（KnockFileShare）】2in1 端注册两类监听，顺序同官方：
      //   ① knockShare：本机被碰时的发送侧（官方在回调里 target.share(选中文件)；demo 只留痕）
      //   ② dataReceive：本机作为接收方，对方传来的文件落 receiveUri
      harmonyShare.on('knockShare', { windowId: windowId }, this.knockCb);
      this.knockWindowId = windowId;
      this.writeDiag(`knockShare on ok windowId=${windowId}`);
      const registry: harmonyShare.RecvCapabilityRegistry = {
        windowId: windowId,
        // 【能力面 = WorkBuddy 逆向文档实测组合（2026-11-17）】FILE + IMAGE + MEDIA，各 maxSupportedCount=5。
        // 依据：《WorkBuddy鸿蒙版碰一碰完整实现-逆向开发文档》§3.3 字节码还原——
        //   { FILE, maxCount } / { IMAGE, maxCount } / { MEDIA, maxCount }；
        //   其 §3.4 明确 IMAGE 对应 .jpg/.png/.gif/.webp/.bmp 等图片扩展名。
        // 缺 IMAGE 时手机选图片（IMAGE utd）不会被本应用匹配 ⇒ 系统退默认接收路径（华为分享文件夹）。
        capabilities: [
          { utd: uniformTypeDescriptor.UniformDataType.FILE,
            maxSupportedCount: DemoKnockShareReceiver.MAX_PER_CAPABILITY },
          { utd: uniformTypeDescriptor.UniformDataType.IMAGE,
            maxSupportedCount: DemoKnockShareReceiver.MAX_PER_CAPABILITY },
          { utd: uniformTypeDescriptor.UniformDataType.MEDIA,
            maxSupportedCount: DemoKnockShareReceiver.MAX_PER_CAPABILITY },
        ],
      };
      harmonyShare.on('dataReceive', registry, this.targetCb);
      this.registry = registry;
      this.started = true;
      this.retryCount = 0;
      this.writeDiag(`on ok windowId=${windowId} caps=FILE,IMAGE,MEDIA max=${DemoKnockShareReceiver.MAX_PER_CAPABILITY}`);
      hilog.info(DOMAIN, TAG, '碰一碰接收已注册 windowId=%{public}d', registry.windowId);
      this.emitPhase('registered');
      return true;
    } catch (e) {
      const err = e as BusinessError;
      this.writeDiag(`start err code=${err.code} msg=${err.message}`);
      hilog.warn(DOMAIN, TAG, '碰一碰注册失败 code=%{public}d msg=%{public}s', err.code, err.message);
      this.emitPhase('failed');
      this.scheduleRetry(mainWindowIdHint);
      return false;
    }
  }

  /** 瞬时注册失败的指数退避（1/2/4/8s，至多 4 次重试；stop() 取消）。 */
  private scheduleRetry(mainWindowIdHint: number): void {
    if (this.retryCount >= DemoKnockShareReceiver.RETRY_DELAYS_MS.length) {
      this.writeDiag(`重试上限（${DemoKnockShareReceiver.RETRY_DELAYS_MS.length} 次），放弃`);
      hilog.warn(DOMAIN, TAG, '碰一碰注册重试已达上限，放弃');
      return;
    }
    const delay: number = DemoKnockShareReceiver.RETRY_DELAYS_MS[this.retryCount];
    this.retryCount += 1;
    this.writeDiag(`${delay}ms 后第 ${this.retryCount} 次重试`);
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      this.start(mainWindowIdHint).then((): void => {});
    }, delay);
  }

  /** 注销接收（页面销毁时调用；挂起队列与挂起重试一并清空）。 */
  stop(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
    this.retryCount = 0;
    if (this.registry !== undefined) {
      try {
        harmonyShare.off('dataReceive', this.registry, this.targetCb);
        this.writeDiag('off ok');
      } catch (e) {
        // 注销失败只留痕：页面已在销毁，泄漏的监听随进程结束回收
        this.writeDiag(`off err code=${(e as BusinessError).code} msg=${(e as BusinessError).message}`);
        hilog.warn(DOMAIN, TAG, '碰一碰注销异常：%{public}s', (e as BusinessError).message);
      }
    }
    this.registry = undefined;
    if (this.knockWindowId >= 0) {
      try {
        harmonyShare.off('knockShare', { windowId: this.knockWindowId });
        this.writeDiag('knockShare off ok');
      } catch (e) {
        this.writeDiag(`knockShare off err code=${(e as BusinessError).code}`);
      }
      this.knockWindowId = -1;
    }
    this.started = false;
    this.pending = [];
    // 注意：receivedPaths 不在这里清——传输中途注销时 onResult 仍要按记账清落盘文件
    this.currentPhase = undefined;
  }

  /** 取走挂起文件（消费即清空；页面就绪时由壳页调用）。 */
  takePending(): Array<KnockFile> {
    if (this.pending.length === 0) {
      return [];
    }
    const out: Array<KnockFile> = this.pending;
    this.pending = [];
    return out;
  }

  /** 未投递文件回队（封顶防爆）；返回实际回队数。 */
  requeue(files: Array<KnockFile>): number {
    if (files.length === 0) {
      return 0;
    }
    const room: number = DemoKnockShareReceiver.MAX_PENDING_FILES - this.pending.length;
    if (room <= 0) {
      this.writeDiag(`requeue 丢弃=${files.length}（队列已满）`);
      return 0;
    }
    const back: Array<KnockFile> = files.length <= room ? files : files.slice(0, room);
    this.pending = this.pending.concat(back);
    this.writeDiag(`requeue n=${back.length} 丢弃=${files.length - back.length}`);
    return back.length;
  }

  /** 注册阶段落地 + 通知壳页（demo 展示层增量）。 */
  private emitPhase(phase: KnockReceiverPhase): void {
    this.currentPhase = phase;
    const observer: ((phase: KnockReceiverPhase) => void) | undefined = this.onPhase;
    if (observer !== undefined) {
      observer(phase);
    }
  }

  /**
   * dataReceive 主流程：receive（filesDir 根，对齐生产）→ 系统落盘 →
   * ingest 读出 → onResult 后按记账清理落盘文件。
   */
  private handleTarget(target: harmonyShare.ReceivableTarget): void {
    this.writeDiag('target filesDir根接收');
    hilog.info(DOMAIN, TAG, '碰一碰：开始接收（filesDir 根）');
    target.receive(fileUri.getUriFromPath(this.ctx.filesDir), {
      onDataReceived: (data: systemShare.SharedData): void => {
        this.ingest(data);
      },
      onResult: (code: harmonyShare.ShareResultCode): void => {
        this.writeDiag(`result code=${code}`);
        hilog.info(DOMAIN, TAG, '碰一碰：传输结束 code=%{public}d', code);
        this.cleanupReceived();
      },
    }).catch((err: BusinessError): void => {
      this.writeDiag(`receive err code=${err.code} msg=${err.message}`);
      hilog.warn(DOMAIN, TAG, 'receive 发起失败 code=%{public}d msg=%{public}s', err.code, err.message);
      this.cleanupReceived();
    });
  }

  /** 读取落盘记录 → 组装 KnockFile 入队 → 通知壳页。 */
  private ingest(data: systemShare.SharedData): void {
    const files: Array<KnockFile> = [];
    let records: number = 0;
    try {
      const recs: Array<systemShare.SharedRecord> = data.getRecords();
      records = recs.length;
      for (const rec of recs) {
        const uri: string = rec.uri ?? '';
        if (uri.length === 0) {
          continue; // 文本/链接记录走系统原路径，这里只收文件
        }
        const path: string = new fileUri.FileUri(uri).path;
        if (path.length === 0) {
          this.writeDiag(`skip uri无法换路径 ${uri}`);
          hilog.warn(DOMAIN, TAG, '记录 uri 无法换路径，跳过：%{public}s', uri);
          continue;
        }
        // filesDir 根接收的记账：无论后续读取/入队成败，落盘文件都要在传输结束后清走
        this.receivedPaths.push(path);
        const file: KnockFile | undefined = this.readFileRecord(rec, path);
        if (file !== undefined) {
          files.push(file);
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      this.writeDiag(`ingest err code=${err.code} msg=${err.message}`);
      hilog.warn(DOMAIN, TAG, '落盘记录读取异常 code=%{public}d msg=%{public}s', err.code, err.message);
    }
    if (files.length === 0) {
      this.writeDiag(`records=${records} 入队=0`);
      return;
    }
    if (this.pending.length + files.length > DemoKnockShareReceiver.MAX_PENDING_FILES) {
      const room: number = DemoKnockShareReceiver.MAX_PENDING_FILES - this.pending.length;
      const drop: number = room <= 0 ? files.length : files.length - room;
      this.writeDiag(`队列已满（${this.pending.length}），丢弃=${drop}`);
      hilog.warn(DOMAIN, TAG, '挂起队列已满（%{public}d），本次丢弃 %{public}d 个',
        this.pending.length, drop);
      if (room <= 0) {
        return;
      }
      files.splice(room, files.length - room);
    }
    this.pending = this.pending.concat(files);
    this.writeDiag(`records=${records} 入队=${files.length} 挂起=${this.pending.length}`);
    hilog.info(DOMAIN, TAG, '碰一碰：入队 %{public}d 个文件（挂起 %{public}d）',
      files.length, this.pending.length);
    const hook: (() => void) | undefined = this.filesHook;
    if (hook !== undefined) {
      hook();
    }
  }

  /** 单条文件记录 → KnockFile；读失败/超限返回 undefined（留痕）。 */
  private readFileRecord(rec: systemShare.SharedRecord, path: string): KnockFile | undefined {
    let name: string = rec.title ?? '';
    if (name.length === 0) {
      const segs: string[] = path.split('/');
      name = segs.length > 0 ? segs[segs.length - 1] : 'knock-file';
    }
    if (name.length === 0) {
      name = 'knock-file';
    }
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const stat: fileIo.Stat = fileIo.statSync(file.fd);
      if (stat.size > DemoKnockShareReceiver.MAX_FILE_BYTES) {
        this.writeDiag(`skip 超限 name=${name} size=${stat.size}`);
        hilog.warn(DOMAIN, TAG, '文件超 16MiB 上限，跳过：name=%{public}s size=%{public}d',
          name, stat.size);
        return undefined;
      }
      let b64: string = '';
      if (stat.size > 0) {
        const buf: ArrayBuffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buf);
        b64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(buf));
      }
      this.writeDiag(`读出 name=${name} size=${stat.size}`);
      hilog.info(DOMAIN, TAG, '读出文件 name=%{public}s size=%{public}d utd=%{public}s',
        name, stat.size, rec.utd);
      const out: KnockFile = {
        name: name,
        mime: mimeTypeForName(name),
        size: stat.size,
        base64: b64,
      };
      return out;
    } catch (e) {
      const err = e as BusinessError;
      this.writeDiag(`读失败 name=${name} code=${err.code} msg=${err.message}`);
      hilog.warn(DOMAIN, TAG, '文件读取失败 name=%{public}s code=%{public}d msg=%{public}s',
        name, err.code, err.message);
      return undefined;
    } finally {
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (e) {
          // 关闭失败：fd 随进程回收，不值得为一手失败掩盖读取结果
        }
      }
    }
  }

  /** 传输结束后按记账清理落盘文件（filesDir 根接收不删目录，只删本次文件）。 */
  private cleanupReceived(): void {
    if (this.receivedPaths.length === 0) {
      return;
    }
    let removed: number = 0;
    let failed: number = 0;
    for (const path of this.receivedPaths) {
      try {
        fileIo.unlinkSync(path);
        removed += 1;
      } catch (e) {
        failed += 1;
        // 单文件清理失败：留痕计数即可，残留文件不阻塞后续传输
      }
    }
    this.receivedPaths = [];
    this.writeDiag(`清理 清=${removed} 失败=${failed}`);
    hilog.info(DOMAIN, TAG, '碰一碰：清理落盘文件 %{public}d 个（失败 %{public}d）', removed, failed);
  }
}
