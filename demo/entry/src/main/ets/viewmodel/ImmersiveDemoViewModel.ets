/**
 * 沉浸光感·弹窗演示视图模型（US1，State Management V2：@ObservedV2 + @Trace）。
 *
 * 【移植锚点】生产 4 处 AlertDialog 形态逐位对齐（entry/src/main/ets/pages/WebApp.ets）：
 *   · 形态一（确认类双按钮）：:4658-4683 confirmCloudLogin——title / 长文案 /
 *     autoCancel / systemMaterial / primaryButton(取消) + secondaryButton(继续)；
 *   · 形态二（确认类双按钮）：:5013-5032 confirmOpenExternal——外开前二次确认，
 *     确认后 launchExternal 拉系统浏览器；
 *   · 形态三（失败提示类单按钮）：:5045-5055 launchExternal 失败提示——
 *     systemMaterial + confirm(知道了)；
 *   · 形态四（失败提示类单按钮）：:5124-5134 launchSystemPreview 失败提示——
 *     systemMaterial + confirm(知道了)。
 *
 * 【文案改 demo 演示语境】（FR-002）：按钮形态与材质逐位复刻，文案替换为
 * demo 演示描述；形态二确认后真开 https://example.com（IANA 保留示例域），
 * 拉起失败自然过渡到形态三（与生产 launchExternal 失败同口径）。
 *
 * 【材质纪律】（FR-003）材质一律经 DemoMaterialKit.dialogMaterial()——
 * THICK 非交互；API<26 判定与构造异常兜底（undefined = 不挂材质）在实参
 * 求值前完成，任何设备不因材质缺席而崩；每次弹出把「材质是否挂上」落
 * diag-material 一行（真机核对 FR-003 的判据）。
 *
 * @module ImmersiveDemoViewModel
 */
import { UIContext, uiMaterial } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { dialogMaterial } from '../service/DemoMaterialKit';
import { WebMenuHost } from '../service/WebMenuHost';
import { DemoThemeState, themeDark } from '../common/DemoTheme';
import { Diag } from '../service/Diag';

/** 演示链接（IANA 保留示例域，与 rawfile/immersive-demo.html 同源口径）。 */
const DEMO_LINK: string = 'https://example.com';

@ObservedV2
export class ImmersiveDemoViewModel {
  /** 最近一次弹出的形态（状态行展示；空串 = 尚未弹出）。 */
  @Trace lastForm: string = '';

  /**
   * Web 演示区控制器（US2）：加载 $rawfile('immersive-demo.html')，
   * 网页右键/长按经 handleContextMenuShow 接管。
   */
  readonly webController: webview.WebviewController = new webview.WebviewController();

  /** 菜单接管宿主（US2，一个 Web 一个；面板/收尾/动作映射全在其中）。 */
  private readonly menuHost: WebMenuHost = new WebMenuHost();

  /** 主题状态单例（菜单明暗显式求值依据）。 */
  private readonly theme: DemoThemeState = DemoThemeState.shared();

  /** UI 上下文（视图 aboutToAppear 注入；弹窗经它调 showAlertDialog）。 */
  private ui: UIContext | undefined = undefined;

  /** 注入 UI 上下文（视图侧 aboutToAppear 调用；重复注入后者胜出）。 */
  attach(ui: UIContext): void {
    this.ui = ui;
  }

  /**
   * 网页右键/长按菜单接管入口（US2，视图 onContextMenuShow 接线；
   * 生产 :7763-7765 的 demo 等价）。明暗先经 themeDark(mode, systemDark)
   * 显式求值（生产纪律：材质/面板明暗不用 SYSTEM 档），再交 WebMenuHost。
   */
  handleContextMenuShow(event?: OnContextMenuShowEvent): boolean {
    const ui: UIContext | undefined = this.ui;
    if (ui === undefined) {
      return false;
    }
    const dark: boolean = themeDark(this.theme.themeMode, this.theme.systemDark);
    return this.menuHost.handleContextMenuShow(ui, dark, event);
  }

  /**
   * 形态一：确认类双按钮——登录确认语境（生产锚 :4658-4683 confirmCloudLogin）。
   * 生产语境是华为账号静默登录前的二次确认；demo 改为演示语境，
   * 点「继续」只更新状态行，不触碰任何真实账号。
   */
  showConfirmLoginDialog(): void {
    const ui: UIContext | undefined = this.ui;
    if (ui === undefined) {
      return;
    }
    const mat: uiMaterial.ImmersiveMaterial | undefined = dialogMaterial();
    try {
      ui.showAlertDialog({
        title: '登录演示账号',
        message: '这是「确认类双按钮」弹窗的演示形态（生产锚点：confirmCloudLogin）。'
          + '点「继续」仅更新演示状态行，不会读取任何真实账号信息。',
        autoCancel: true,
        systemMaterial: mat,
        primaryButton: {
          value: '取消',
          action: (): void => {
            this.note('形态一·已取消');
          }
        },
        secondaryButton: {
          value: '继续',
          action: (): void => {
            this.note('形态一·已确认（模拟登录）');
          }
        }
      });
      this.note(`形态一弹出 mat=${mat !== undefined ? 1 : 0}`);
    } catch (e) {
      // 弹窗构造异常（极端设备）：留痕不崩（FR-003 异常兜底纪律）
      Diag.material(`dialog form1 error ${(e as BusinessError).message}`);
    }
  }

  /**
   * 形态二：确认类双按钮——外开确认语境（生产锚 :5013-5032 confirmOpenExternal）。
   * 确认后经 openLink（appLinkingOnly: false，无应用接管时浏览器兜底）拉系统
   * 浏览器打开 IANA 保留示例域；打不开时过渡到形态三失败提示（生产同口径）。
   */
  showOpenExternalConfirmDialog(): void {
    const ui: UIContext | undefined = this.ui;
    if (ui === undefined) {
      return;
    }
    const mat: uiMaterial.ImmersiveMaterial | undefined = dialogMaterial();
    try {
      ui.showAlertDialog({
        title: '打开外部浏览器？',
        message: DEMO_LINK,
        autoCancel: true,
        systemMaterial: mat,
        primaryButton: {
          value: '取消',
          action: (): void => {
            this.note('形态二·已取消');
          }
        },
        secondaryButton: {
          value: '打开',
          action: (): void => {
            this.note('形态二·已确认，正在外开');
            this.openDemoLink();
          }
        }
      });
      this.note(`形态二弹出 mat=${mat !== undefined ? 1 : 0}`);
    } catch (e) {
      Diag.material(`dialog form2 error ${(e as BusinessError).message}`);
    }
  }

  /**
   * 形态三：失败提示类单按钮——外开失败语境（生产锚 :5045-5055）。
   * 生产语境是 openLink 未被系统受理时的用户可见提示；demo 点按钮直接演示该形态。
   */
  showOpenFailedDialog(): void {
    const ui: UIContext | undefined = this.ui;
    if (ui === undefined) {
      return;
    }
    const mat: uiMaterial.ImmersiveMaterial | undefined = dialogMaterial();
    try {
      ui.showAlertDialog({
        title: '无法打开外部浏览器',
        message: `系统未受理该链接，请确认已安装浏览器。\n\n${DEMO_LINK}`,
        systemMaterial: mat,
        confirm: {
          value: '知道了',
          action: (): void => {
            // 空实现即全部行为：确认后自动关闭弹窗（生产同款）
          }
        }
      });
      this.note(`形态三弹出 mat=${mat !== undefined ? 1 : 0}`);
    } catch (e) {
      Diag.material(`dialog form3 error ${(e as BusinessError).message}`);
    }
  }

  /**
   * 形态四：失败提示类单按钮——系统预览未受语境（生产锚 :5124-5134）。
   * 生产语境是 PreviewKit openPreview 未受理时的用户可见提示；demo 以
   * demo-sample.txt 作演示文件名。
   */
  showPreviewFailedDialog(): void {
    const ui: UIContext | undefined = this.ui;
    if (ui === undefined) {
      return;
    }
    const mat: uiMaterial.ImmersiveMaterial | undefined = dialogMaterial();
    try {
      ui.showAlertDialog({
        title: '系统预览未受理',
        message: '系统未能打开这个文件的预览窗。\n\ndemo-sample.txt',
        systemMaterial: mat,
        confirm: {
          value: '知道了',
          action: (): void => {
            // 空实现即全部行为：确认后自动关闭弹窗（生产同款）
          }
        }
      });
      this.note(`形态四弹出 mat=${mat !== undefined ? 1 : 0}`);
    } catch (e) {
      Diag.material(`dialog form4 error ${(e as BusinessError).message}`);
    }
  }

  /**
   * 经系统默认方式打开示例链接（生产 launchExternal → platform/OpenLink.ets
   * openExternalUrl 的 demo 等价）：只放行 http/https；appLinkingOnly: false
   * 让无应用接管时走浏览器。失败弹形态三（与生产「失败必须让用户看见」同口径）。
   */
  private openDemoLink(): void {
    const ui: UIContext | undefined = this.ui;
    if (ui === undefined) {
      return;
    }
    try {
      const ctx: common.UIAbilityContext = ui.getHostContext() as common.UIAbilityContext;
      ctx.openLink(DEMO_LINK, { appLinkingOnly: false }).then((): void => {
        this.note('外开成功（系统已受理）');
      }, (e: BusinessError): void => {
        Diag.material(`openlink fail ${e.message}`);
        this.showOpenFailedDialog();
      });
    } catch (e) {
      Diag.material(`openlink throw ${(e as BusinessError).message}`);
      this.showOpenFailedDialog();
    }
  }

  /** 记录弹窗动作：状态行 + diag-material 留痕（ISO 时间戳由 Diag 统一加）。 */
  private note(form: string): void {
    this.lastForm = form;
    Diag.material(`dialog ${form}`);
  }
}
