/**
 * 碰一碰·演示视图模型（US3 模拟链路 + US4 真实接收，State Management V2：
 * @ObservedV2 + @Trace）。
 *
 * 【管线（FR-009 同一出口）】三路来源 → 16MiB 校验 → KnockFile → KnockShim.injectFile
 * （唯一出口）→ 垫片合成 paste → demo 网页 file-intake → 附件 chip（不自动发送）。
 *   · 来源一「内置样例」：resourceManager 读 rawfile 'demo-sample.txt' → base64；
 *   · 来源二「选文件」：DocumentViewPicker 单选 → uri → fileIo 读 → base64；
 *   · 来源三「真实接收」：DemoKnockShareReceiver.onFiles → 本类 onReceiverDelivered
 *     → takePending → submitFromReceiver → deliverOrQueue（与模拟同一条）。
 * 三条来源收敛到 deliverOrQueue → KnockShim.injectFile，不形成第二管线（plan R6）。
 *
 * 【真实接收生命周期（US4，2026-11-17 对照官方样本修订）】注册由 **Index.aboutToAppear**
 * 立即触发（官方 KnockFileShare 在首页 aboutToAppear 即注册 knockShare + dataReceive），
 * 不再等碰一碰页签渲染 / Web onPageEnd——原时机导致「未切页签就碰 ⇒ 系统侧根本没接收方」。
 * onWebPageEnd 仍会再调一次（幂等空跑）并补发挂起队列；Web 未就绪时到达的文件进 pending，
 * 打开碰一碰页签、页面就绪即补发。页面销毁（Index.aboutToDisappear）调 stopReceiver()。
 * 注册阶段经 DemoKnockShareReceiver.onPhase 推进 @Trace receiverState（状态行展示）。
 * 门控差异：生产仅 PC 档注册（desktopForced），demo 无形态矩阵故不门控（FR-010）。
 *
 * 【挂起队列（逐位对齐生产 KnockShareReceiver 队列语义）】Web 未就绪（onPageEnd 之前）
 * 的文件进 pending；页面就绪 takePending() 取走补发；注入未完成（controller 未挂载 /
 * runJavaScript err）走 requeue() 回队；容量 cap 10，超限丢弃并留痕（spec Edge Cases）。
 *
 * 【16MiB 校验】base64 通道脚本体积上限纪律（生产 MAX_FILE_BYTES 同值）：超限跳过、
 * diag-knock 留痕、不注入（US3 场景 3）。
 *
 * 【控制器来源】视图在 Web.onControllerAttached 时调 attachController 注入
 * （与 ImmersiveDemoView 同一装配风格：controller 归 VM 所有，视图负责生命周期接线）；
 * 页面就绪以 onPageEnd 为准（生产 webReady 同一判据），此前一律排挂起队列。
 *
 * @module KnockDemoViewModel
 */
import { webview } from '@kit.ArkWeb';
import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { KnockFile } from '../model/DemoTypes';
import { injectFile, KnockInjectResult, mimeTypeForName } from '../service/KnockShim';
import { Diag } from '../service/Diag';
import { DemoKnockShareReceiver, KnockReceiverPhase } from '../service/DemoKnockShareReceiver';

/** base64 通道单文件上限（字节）——生产 KnockShareReceiver.MAX_FILE_BYTES 同值。 */
const MAX_FILE_BYTES: number = 16 * 1024 * 1024;
/** Web 未就绪时的挂起队列上限——生产 MAX_PENDING_FILES 同值（防重载窗口连点堆积）。 */
const MAX_PENDING_FILES: number = 10;
/** 内置样例 rawfile 名与展示名（同名，T014 资产）。 */
const SAMPLE_RAW_NAME: string = 'demo-sample.txt';
/** 用户取消文件选择器的错误码（13900020 / 0；与生产 isFolderPickerCancelCode 同判据）。 */
const PICKER_CANCEL_CODES: Array<number> = [13900020, 0];

/**
 * 真实接收注册状态（US4：页面就绪后由 startKnockReceiver 推进，onPhase 回调驱动）。
 *   not-wired   = 页面尚未就绪（onPageEnd 之前）/ 已注销；
 *   unsupported = canIUse=false（设备永久缺能力，不重试）；
 *   registering = 本轮注册尝试中（退避重试期间保持 failed）；
 *   registered  = 已挂上 dataReceive 监听；
 *   failed      = 本轮失败（瞬时失败自动按 1/2/4/8s 退避重试，最多 5 次尝试）。
 */
export type KnockReceiverState = 'not-wired' | 'unsupported' | 'registering' | 'registered' | 'failed';

/** 从 uri 末段取展示名并解码百分号转义（对齐生产 FilePicker.nameOfUri）。 */
function nameOfUri(uri: string): string {
  let end: number = uri.length;
  const query: number = uri.indexOf('?');
  if (query >= 0) {
    end = query;
  }
  const slash: number = uri.lastIndexOf('/', end - 1);
  const raw: string = uri.substring(slash + 1, end);
  try {
    return decodeURIComponent(raw);
  } catch (e) {
    // 非法转义序列（少见）：原样使用比抛错好，名字只是展示
    return raw;
  }
}

/** 后缀表推 MIME；推不出用 fallback（不猜成 text/plain，生产口径）。 */
function mimeOf(name: string, fallback: string): string {
  const mime: string = mimeTypeForName(name);
  return mime.length > 0 ? mime : fallback;
}

/** 注入路由结果 → 中文标签（页面侧返回值语义见 KnockShim 头注）。 */
function routeLabel(result: string): string {
  if (result === 'paste') {
    return '已注入（合成 paste）';
  }
  if (result === 'drop') {
    return '已注入（退 drop）';
  }
  if (result === 'unrouted') {
    return '注入失败：paste/drop 两路皆不通（unrouted，已留痕）';
  }
  if (result === 'no-shim') {
    return '注入失败：垫片未注入（no-shim，已留痕）';
  }
  if (result === 'bad-payload') {
    return '注入失败：载荷损坏（bad-payload，已留痕）';
  }
  if (result === 'error') {
    return '注入失败：页面侧异常（error，已留痕）';
  }
  return `已注入（route=${result}）`;
}

@ObservedV2
export class KnockDemoViewModel {
  /** 状态行文本（最近一次操作/排队/失败的可见结论）。 */
  @Trace status: string = '待机：点任一「模拟碰一碰」按钮';
  /** 最近一次注入结果文本（状态行展示；空串初始 = 尚未注入）。 */
  @Trace lastInject: string = '（尚未注入）';
  /** 挂起队列长度（@Trace：入队/出队/回队即时驱动状态行刷新）。 */
  @Trace pendingCount: number = 0;
  /** 真实接收注册状态（US4：页面就绪后注册，onPhase 推进；状态行展示）。 */
  @Trace receiverState: KnockReceiverState = 'not-wired';
  /** 最近 diag-knock 行（界面直读，无 hdc 也能现场自证注册/接收链路）。 */
  @Trace diagFeed: string = '（diag 暂无）';

  /** Web 控制器（视图在 onControllerAttached 注入；本类自持以满足 Web 构造需要）。 */
  readonly webController: webview.WebviewController = new webview.WebviewController();

  /** 宿主上下文（视图 aboutToAppear 注入：rawfile 读与 DocumentViewPicker 都要它）。 */
  private ctx: common.Context | undefined = undefined;
  /** 实际注入的控制器引用（attachController 成功后非 undefined）。 */
  private controller: webview.WebviewController | undefined = undefined;
  /** 页面就绪（onPageEnd 置真）：未就绪一律排挂起队列，就绪后补发。 */
  private webReady: boolean = false;
  /** 挂起队列（元素 = KnockFile；真实接收与模拟同形状）。 */
  private pending: Array<KnockFile> = [];
  /** 串行链：选文件/注入/补发按点击顺序推进，避免并发注入乱序。 */
  private chain: Promise<void> = Promise.resolve();
  /** 真实接收器（页面就绪后创建；stopReceiver 注销并置回 undefined）。 */
  private receiver: DemoKnockShareReceiver | undefined = undefined;

  /** 注入宿主上下文（视图 aboutToAppear 调用；重复注入后者胜出）。 */
  attachContext(ctx: common.Context): void {
    this.ctx = ctx;
  }

  /**
   * 注入 Web 控制器（视图 onControllerAttached 调用）。
   * 只登记引用，不置 webReady——页面脚本未加载完时 runJavaScript 仍会失败，
   * 就绪判据统一交给 onWebPageEnd（生产 webReady 同口径）。
   */
  attachController(controller: webview.WebviewController): void {
    this.controller = controller;
    Diag.knock('controller attached');
  }

  /**
   * 整页导航开始（视图 onPageBegin 调用）：回到未就绪。
   * 重载窗口里点模拟按钮必然注入失败 ⇒ 先排队，等 onPageEnd 补发（生产同一纪律）。
   */
  onWebPageBegin(): void {
    this.webReady = false;
    Diag.knock('page begin webReady=false');
  }

  /** 页面加载完成（视图 onPageEnd 调用）：置就绪并补发挂起队列（重载窗口不丢）。 */
  onWebPageEnd(): void {
    this.webReady = true;
    Diag.knock(`page end webReady=true 挂起=${this.pending.length}`);
    if (this.pending.length > 0) {
      this.serial(async (): Promise<void> => {
        await this.flushPending();
      });
    }
    // 接收器里若还压着文件（VM 队列满时 requeue 回去的那批），页面就绪一并补发
    // （生产 onPageEnd 里 deliverKnockFiles → startKnockReceiver 同序，WebApp.ets :7915/:7921）
    this.onReceiverDelivered();
    this.startKnockReceiver();
  }

  /** 来源一：模拟碰一碰（内置样例 rawfile）。 */
  simulateFromSample(): void {
    this.serial(async (): Promise<void> => {
      this.setStatus('读取内置样例…');
      const file: KnockFile | undefined = this.readSampleFile();
      if (file === undefined) {
        return;
      }
      await this.deliverOrQueue(file, 'sample');
    });
  }

  /** 来源二：模拟碰一碰（系统文件选择器选真实文件）。 */
  simulateFromPicker(): void {
    this.serial(async (): Promise<void> => {
      this.setStatus('等待选择文件…');
      const file: KnockFile | undefined = await this.pickFile();
      if (file === undefined) {
        return;
      }
      await this.deliverOrQueue(file, 'picker');
    });
  }

  /**
   * 真实接收入口（DemoKnockShareReceiver.onFiles → onReceiverDelivered → 本方法→
   * deliverOrQueue → KnockShim.injectFile）：与模拟链路共用同一出口（FR-009）。
   */
  submitFromReceiver(file: KnockFile): void {
    this.serial(async (): Promise<void> => {
      await this.deliverOrQueue(file, 'receiver');
    });
  }

  // ── 真实接收生命周期（US4）────────────────────────────────────────────────

  /**
   * 注册真实接收（幂等）。由 **Index.aboutToAppear 立即调用**（对齐官方示例时机），
   * onWebPageEnd 亦会再调（已注册则空跑；此前瞬时失败由接收器内部退避重试）。
   * 接收器首次用到时创建（onFiles → onReceiverDelivered，writeDiag → Diag.knock）；
   * 之后每次调用重新 start()（已注册则空跑，此前失败则由接收器内部退避重试）。
   * 门控差异：生产 `if (!this.desktopForced) return`，demo 无形态矩阵故不门控（FR-010）。
   */
  startKnockReceiver(): void {
    // 单例优先：EntryAbility 建窗时已 bootstrap 并注册（真实主窗 id），此处只接管
    let receiver: DemoKnockShareReceiver | undefined = DemoKnockShareReceiver.current();
    const ctx: common.Context | undefined = this.ctx;
    if (receiver === undefined) {
      // 兜底路径（Ability 引导异常）：页面创建；主窗 id 交给接收器 getLastWindow
      if (ctx === undefined) {
        Diag.knock('receiver skip ctx=undefined');
        this.receiverState = 'failed';
        return;
      }
      receiver = DemoKnockShareReceiver.bootstrap(ctx as common.UIAbilityContext, -1,
        (detail: string): void => {
          Diag.knock(detail);
          this.refreshDiag();
        });
    }
    this.receiver = receiver;
    receiver.setOnFiles((): void => {
      this.onReceiverDelivered();
      this.refreshDiag();
    });
    receiver.setWriteDiag((detail: string): void => {
      // 注册/接收/投递全链落 filesDir/diag-knock + 同步界面 diag 视图
      Diag.knock(detail);
      this.refreshDiag();
    });
    receiver.onPhase = (phase: KnockReceiverPhase): void => {
      this.applyReceiverPhase(phase);
    };
    const known: KnockReceiverPhase | undefined = receiver.phase();
    if (known !== undefined) {
      // 回填真状态：退避重试可能已在两次调用之间成功（状态行不落后）
      this.applyReceiverPhase(known);
    }
    receiver.start(-1).then((ok: boolean): void => {
      Diag.knock(`receiver start ok=${ok}`);
      this.refreshDiag();
    }).catch((): void => {
      // start() 内部已逐项留痕并排重试；这里只消化拒绝，不打断页面
      Diag.knock('receiver start rejected');
      this.refreshDiag();
    });
  }

  /** 刷新界面 diag 视图（最近 8 行）。 */
  private refreshDiag(): void {
    this.diagFeed = Diag.recent(8).join('\n');
  }

  /** 注销真实接收（视图 aboutToDisappear 调用；队列与挂起重试由接收器一并清空）。 */
  stopReceiver(): void {
    const receiver: DemoKnockShareReceiver | undefined = this.receiver;
    if (receiver === undefined) {
      return;
    }
    receiver.stop();
    this.receiver = undefined;
    this.receiverState = 'not-wired';
    Diag.knock('receiver stop（页面销毁）');
  }

  /**
   * 接收器「有新文件入队」通知（生产 onFiles 回调同义）：取走挂起文件 →
   * 逐个交给同一出口 submitFromReceiver（不旁路、不另起管线）。
   *
   * 【不丢】VM 挂起队列已满时整批回队接收器侧（requeue），等下次页面就绪/通知再投；
   * 接收器队列也满才丢弃并留痕（spec Edge Case：队列封顶丢弃留痕）。
   */
  private onReceiverDelivered(): void {
    const receiver: DemoKnockShareReceiver | undefined = this.receiver;
    if (receiver === undefined) {
      return;
    }
    const files: Array<KnockFile> = receiver.takePending();
    if (files.length === 0) {
      return;
    }
    Diag.knock(`receiver 接收 n=${files.length}`);
    if (this.pending.length >= MAX_PENDING_FILES) {
      const back: number = receiver.requeue(files);
      Diag.knock(`receiver 投递延后（VM 队列已满）回队=${back} 丢弃=${files.length - back}`);
      this.setStatus(`真实接收 ${files.length} 个文件已回队（VM 队列 ${this.pendingCount}/${MAX_PENDING_FILES}）`);
      return;
    }
    for (const file of files) {
      this.submitFromReceiver(file);
    }
    this.setStatus(`真实接收 ${files.length} 个文件 → 同一注入出口`);
  }

  /** 注册阶段 → @Trace receiverState（状态行随 onPhase 即时刷新）。 */
  private applyReceiverPhase(phase: KnockReceiverPhase): void {
    if (phase === 'unsupported') {
      this.receiverState = 'unsupported';
    } else if (phase === 'registering') {
      this.receiverState = 'registering';
    } else if (phase === 'registered') {
      this.receiverState = 'registered';
    } else {
      this.receiverState = 'failed';
    }
    this.refreshDiag();
  }

  /** 取走挂起文件（消费即清空；生产 takePending 同语义）。 */
  takePending(): Array<KnockFile> {
    if (this.pending.length === 0) {
      return [];
    }
    const out: Array<KnockFile> = this.pending;
    this.pending = [];
    this.syncPendingCount();
    return out;
  }

  /** 未投递文件回队（封顶防爆）；返回实际回队数（生产 requeue 同语义）。 */
  requeue(files: Array<KnockFile>): number {
    if (files.length === 0) {
      return 0;
    }
    const room: number = MAX_PENDING_FILES - this.pending.length;
    if (room <= 0) {
      Diag.knock(`requeue 丢弃=${files.length}（队列已满 ${MAX_PENDING_FILES}）`);
      return 0;
    }
    const back: Array<KnockFile> = files.length <= room ? files : files.slice(0, room);
    this.pending = this.pending.concat(back);
    this.syncPendingCount();
    Diag.knock(`requeue n=${back.length} 丢弃=${files.length - back.length} 挂起=${this.pending.length}`);
    return back.length;
  }

  /** 注册状态中文标签（视图状态行；receiverState 由页面就绪后的注册推进）。 */
  receiverStateLabel(): string {
    if (this.receiverState === 'unsupported') {
      return '不支持（canIUse=false，不重试）';
    }
    if (this.receiverState === 'registering') {
      return '注册中…（失败按 1/2/4/8s 退避重试）';
    }
    if (this.receiverState === 'registered') {
      return '已注册（可接收真实碰一碰）';
    }
    if (this.receiverState === 'failed') {
      return '注册失败（已留痕 diag-knock，自动退避重试中）';
    }
    return '未注册（页面加载完成后自动注册）';
  }

  // ── 内部：投递编排 ────────────────────────────────────────────────────────

  /**
   * 单文件投递（队列为唯一等待结构，生产 onFiles → deliverKnockFiles 同编排）：
   * 先入队（cap 10，超限丢弃留痕）→ Web 未就绪就等 onPageEnd 补发 →
   * 已就绪立即 flushPending（takePending 出队 → 注入 → 失败回队）。
   */
  private async deliverOrQueue(file: KnockFile, source: string): Promise<void> {
    // 三路来源同一留痕口径：source = sample / picker / receiver
    Diag.knock(`deliver source=${source} name=${file.name} size=${file.size}`);
    const accepted: number = this.enqueue(file);
    if (accepted === 0) {
      this.setStatus(`挂起队列已满（${MAX_PENDING_FILES}），已丢弃 ${file.name}`);
      return;
    }
    if (!this.webReady || this.controller === undefined) {
      this.setStatus(`页面未就绪，已排队（${this.pendingCount}/${MAX_PENDING_FILES}）——页面就绪后补发`);
      return;
    }
    await this.flushPending();
    if (this.pending.length > 0) {
      // flushPending 断点后的残余已回队：给出可见结论（不丢，等下次补发）
      this.setStatus(`注入未完成，已回队（${this.pendingCount}/${MAX_PENDING_FILES}）`);
    }
  }

  /** 补发挂起队列：逐个注入，断点后的残余回队（生产 deliverKnockFiles 同编排）。 */
  private async flushPending(): Promise<void> {
    if (!this.webReady || this.controller === undefined || this.pending.length === 0) {
      return;
    }
    const files: Array<KnockFile> = this.takePending();
    Diag.knock(`补发 待投=${files.length}`);
    let delivered: number = 0;
    for (const file of files) {
      const ok: boolean = await this.injectOne(file);
      if (!ok) {
        break; // controller 未挂载：剩下回队等下次页面就绪补发，不丢
      }
      delivered += 1;
    }
    if (delivered < files.length) {
      const rest: Array<KnockFile> = files.slice(delivered);
      const back: number = this.requeue(rest);
      Diag.knock(`deliver中断 已投=${delivered} 回队=${back} 丢失=${rest.length - back}`);
    }
  }

  /**
   * 单文件注入（唯一出口 KnockShim.injectFile）。
   * 返回 false = 注入未完成（controller 未挂载 / runJavaScript err），调用方回队；
   * 返回 true = 脚本已执行（含 unrouted/no-shim 等页面侧失败，与生产同为已消费）。
   */
  private async injectOne(file: KnockFile): Promise<boolean> {
    const ctrl: webview.WebviewController | undefined = this.controller;
    if (ctrl === undefined) {
      this.lastInject = `注入未完成（controller 未挂载）：${file.name}`;
      Diag.knock(`inject skip controller=undefined name=${file.name}`);
      return false;
    }
    const r: KnockInjectResult = await injectFile(ctrl, file);
    if (!r.ok) {
      this.lastInject = `注入未完成（${r.result}）：${file.name}`;
      return false;
    }
    const label: string = routeLabel(r.result);
    this.lastInject = `${label}：${file.name}（${file.size} 字节）`;
    Diag.knock(`inject ok name=${file.name} size=${file.size} route=${r.result}`);
    if (r.result === 'unrouted') {
      Diag.knock(`unrouted name=${file.name}（paste/drop 两路皆不通）`);
    }
    this.setStatus(label);
    return true;
  }

  // ── 内部：两路来源 ────────────────────────────────────────────────────────

  /** 来源一：rawfile → 字节 → base64（超限/读失败返回 undefined 并留痕）。 */
  private readSampleFile(): KnockFile | undefined {
    const ctx: common.Context | undefined = this.ctx;
    if (ctx === undefined) {
      this.setStatus('上下文缺失，无法读取内置样例');
      Diag.knock('sample skip ctx=undefined');
      return undefined;
    }
    try {
      const bytes: Uint8Array = ctx.resourceManager.getRawFileContentSync(SAMPLE_RAW_NAME);
      if (bytes.length > MAX_FILE_BYTES) {
        this.setStatus(`内置样例超 16MiB 上限（${bytes.length} 字节），已跳过`);
        Diag.knock(`skip 超限 name=${SAMPLE_RAW_NAME} size=${bytes.length} source=sample`);
        return undefined;
      }
      const base64: string = new util.Base64Helper().encodeToStringSync(bytes);
      Diag.knock(`sample read name=${SAMPLE_RAW_NAME} size=${bytes.length}`);
      const out: KnockFile = {
        name: SAMPLE_RAW_NAME,
        mime: mimeOf(SAMPLE_RAW_NAME, 'text/plain'),
        size: bytes.length,
        base64: base64
      };
      return out;
    } catch (e) {
      this.setStatus(`内置样例读取失败：${(e as BusinessError).message}`);
      Diag.knock(`sample err ${(e as BusinessError).message}`);
      return undefined;
    }
  }

  /** 来源二：DocumentViewPicker 单选 → 读 uri → KnockFile（取消/失败/超限返回 undefined）。 */
  private async pickFile(): Promise<KnockFile | undefined> {
    const ctx: common.Context | undefined = this.ctx;
    if (ctx === undefined) {
      this.setStatus('上下文缺失，无法拉起文件选择器');
      Diag.knock('picker skip ctx=undefined');
      return undefined;
    }
    let uris: Array<string> = [];
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.selectMode = picker.DocumentSelectMode.FILE;
      const view: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      uris = await view.select(options);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      const cancelled: boolean = PICKER_CANCEL_CODES.indexOf(err.code) >= 0;
      Diag.knock(`picker rejected code=${err.code} cancelled=${cancelled}`);
      this.setStatus(cancelled ? '已取消选择' : `文件选择器不可用（code=${err.code}）`);
      return undefined;
    }
    if (uris.length === 0) {
      Diag.knock('picker 空结果（视为取消）');
      this.setStatus('已取消选择');
      return undefined;
    }
    return this.readPickedUri(uris[0]);
  }

  /** 读选中的 uri：stat 查大小 → 超限跳过 → 按实读字节编码 base64。 */
  private readPickedUri(uri: string): KnockFile | undefined {
    const name: string = nameOfUri(uri);
    let file: fileIo.File | undefined = undefined;
    try {
      const opened: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      file = opened;
      const stat: fileIo.Stat = fileIo.statSync(opened.fd);
      if (stat.size > MAX_FILE_BYTES) {
        this.setStatus(`文件超 16MiB 上限（${stat.size} 字节），已跳过：${name}`);
        Diag.knock(`skip 超限 name=${name} size=${stat.size} source=picker`);
        return undefined;
      }
      let base64: string = '';
      let size: number = 0;
      if (stat.size > 0) {
        const buf: ArrayBuffer = new ArrayBuffer(stat.size);
        const read: number = fileIo.readSync(opened.fd, buf);
        // 只编码实际读到的字节：stat 与 read 之间文件可能被改动，
        // 按 size 编码会在尾部带上未写入的 0（生产 FilePicker 同一纪律）
        base64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(buf, 0, read));
        size = read;
      }
      Diag.knock(`picker read name=${name} size=${size}`);
      const out: KnockFile = {
        name: name,
        mime: mimeOf(name, 'application/octet-stream'),
        size: size,
        base64: base64
      };
      return out;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      this.setStatus(`读取选中文件失败：${err.message}（code=${err.code}）`);
      Diag.knock(`picker read err name=${name} code=${err.code} msg=${err.message}`);
      return undefined;
    } finally {
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (e) {
          // 关闭失败：fd 随进程回收，不掩盖已读到的结果
        }
      }
    }
  }

  // ── 内部：队列与状态 ──────────────────────────────────────────────────────

  /** 单文件入队（cap 10）；返回实际入队数（0 = 队列已满，已留痕丢弃）。 */
  private enqueue(file: KnockFile): number {
    const room: number = MAX_PENDING_FILES - this.pending.length;
    if (room <= 0) {
      Diag.knock(`enqueue 丢弃 name=${file.name}（队列已满 ${MAX_PENDING_FILES}）`);
      return 0;
    }
    this.pending = this.pending.concat([file]);
    this.syncPendingCount();
    Diag.knock(`enqueue n=1 挂起=${this.pending.length}`);
    return 1;
  }

  /** 队列长度同步到 @Trace（驱动状态行刷新）。 */
  private syncPendingCount(): void {
    this.pendingCount = this.pending.length;
  }

  /** 状态行写入（诊断留痕由各调用点按语义自行落，这里只管可见文案）。 */
  private setStatus(text: string): void {
    this.status = text;
  }

  /** 串行执行（按点击/补发顺序推进；单次任务异常不中断后续）。 */
  private serial(task: () => Promise<void>): void {
    this.chain = this.chain.then((): Promise<void> => task()).catch((): void => {
      // 单次任务异常不中断串行链：失败已在任务内部落 diag 与状态行
    });
  }
}
