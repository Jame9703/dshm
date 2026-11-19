/**
 * 网页右键/长按菜单接管链（US2）——生产 WebApp.ets 的 demo 逐位移植。
 *
 * 【移植锚点】
 *   · 面板 @Builder：WebApp.ets :195-225（WebContextMenuPanel，WithTheme 包 Menu，
 *     明暗显式指定——2026-10-11 真机结论：SYSTEM 档实测仍给深色玻璃，必须显式）；
 *   · 接管链：WebApp.ets :7311-7496 handleWebContextMenuShow——语境判定
 *     （link / image / editable+位掩码 / 纯选区 / 空集回退）、坐标负值回退、
 *     动作映射（打开链接拉系统浏览器 / 复制剪切粘贴全选走 ArkWeb result /
 *     复制图片 / 保存图片按 API 存在性 typeof 守卫）、面板 ComponentContent +
 *     wrapBuilder 构造（:7447-7452）、openMenu 锚定触点（anchorPosition）；
 *   · 收尾三件套：:7240-7295 dismissWebContextMenu（幂等 closeContextMenu）/
 *     disposeWebMenuContent（幂等 dispose）/ runWebMenuItem
 *     （动作 → closeContextMenu → closeMenu → 后置动作，web.d.ts 顺序依据）。
 *
 * 【为什么 return false 是万金油】任何拿不准的情形（事件缺参、坐标异常、
 * 空菜单项、构建异常）一律 return false ⇒ ArkWeb 弹系统默认菜单，现有功能
 * 零退化；自定义路径只覆盖我们能完整负责的部分（生产同款纪律）。
 *
 * 【材质】菜单挂 THIN 非交互材质（DemoMaterialKit.menuMaterial：API≥26 才
 * 求值 ImmersiveStyle.THIN，守卫在实参求值前；<26 返回 undefined 不挂材质）。
 *
 * 【诊断（diag-webmenu）】show / fallback（no-event·coords·empty·exception）/
 * open（ok·fail）/ appear / dismiss / item / copy-link-fail / openlink 全链标记，
 * 追加式落 filesDir（ISO 时间戳由 Diag 统一加；不依赖 hilog）。
 *
 * @module WebMenuHost
 */
import { UIContext, ComponentContent } from '@kit.ArkUI';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { Diag } from './Diag';
import { menuMaterial } from './DemoMaterialKit';
import { WebContextMenuItem, WebContextMenuPanelParams } from '../model/DemoTypes';

/**
 * 右键/长按菜单的兼容垫片（生产 :180-188 WebContextMenuCompat 逐位移植）：
 * enableDefaultContextMenu 是 API 24 起（API 23 设备上不存在），typeof 守卫后
 * 开启默认右键菜单——onContextMenuShow 的接管与「空集回退系统菜单」都以它
 * 为前提（默认 false 时系统菜单不出，接管链没有回退落点）。
 */
class WebContextMenuCompat implements AttributeModifier<WebAttribute> {
  applyNormalAttribute(instance: WebAttribute): void {
    if (deviceInfo.sdkApiVersion >= 24
      && typeof instance.enableDefaultContextMenu === 'function') {
      instance.enableDefaultContextMenu(true);
    }
  }
}

export const WEB_CONTEXT_MENU_COMPAT: WebContextMenuCompat = new WebContextMenuCompat();

/**
 * 网页上下文菜单面板（全局 @Builder，wrapBuilder 包装后交给 openMenu 的
 * ComponentContent）。WithTheme 包 Menu：菜单文字跟随应用外观而非系统外观，
 * 明暗由 themeDark 显式指定（生产 :213-225 逐位移植）。
 */
@Builder
function WebContextMenuPanel(params: WebContextMenuPanelParams) {
  WithTheme({ colorMode: params.themeDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT }) {
    Menu() {
      ForEach(params.items, (item: WebContextMenuItem): void => {
        MenuItem({ content: item.label })
          .onClick((): void => {
            item.run();
          })
      }, (item: WebContextMenuItem): string => item.label)
    }
  }
}

/**
 * 接管链宿主：一次菜单显示的挂起态（content/result/closed）与全链方法。
 * 一个 Web 组件一个实例（视图持有；重入由 closed 门控）。
 */
export class WebMenuHost {
  /** openMenu 之后、菜单消散之前的面板内容（非响应式：不驱动 UI）。 */
  private content: ComponentContent<WebContextMenuPanelParams> | undefined = undefined;
  /** ArkWeb 菜单结果（收尾时 closeContextMenu 用）。 */
  private result: WebContextMenuResult | undefined = undefined;
  /** 菜单是否已收（防「菜单项点击」与「onDisappear」双路径重入）。 */
  private closed: boolean = true;

  /**
   * 接管入口（生产 :7311-7496 逐位移植）。返回 true = 应用侧已接管
   * （openMenu 弹出）；false = 交还 ArkWeb 弹系统默认菜单。
   *
   * @param ui UI 上下文（ComponentContent/openMenu/closeMenu 经它构造）
   * @param dark 明暗已显式求值（themeDark(mode, systemDark)，生产纪律不用 SYSTEM 档）
   * @param event ArkWeb onContextMenuShow 事件
   */
  handleContextMenuShow(ui: UIContext, dark: boolean, event?: OnContextMenuShowEvent): boolean {
    try {
      if (event === undefined || event.param === undefined || event.result === undefined) {
        Diag.webmenu('fallback no-event');
        return false;
      }
      const param: WebContextMenuParam = event.param;
      const result: WebContextMenuResult = event.result;
      const px: number = param.x();
      const py: number = param.y();
      if (px < 0 || py < 0) {
        Diag.webmenu(`fallback coords x=${px} y=${py}`);
        return false;
      }
      const link: string = param.getLinkUrl();
      const selText: string = param.getSelectionText();
      const editable: boolean = param.isEditable();
      const flags: number = param.getEditStateFlags();
      const isImage: boolean = param.existsImageContents()
        || param.getMediaType() === ContextMenuMediaType.Image;
      const items: WebContextMenuItem[] = this.buildMenuItems(ui, param, result,
        link, selText, editable, flags, isImage);
      if (items.length === 0) {
        Diag.webmenu(`fallback empty link=${link.length} sel=${selText.length}`
          + ` editable=${editable ? 1 : 0} flags=${flags}`);
        return false;
      }
      this.result = result;
      this.closed = false;
      const panelParams: WebContextMenuPanelParams = {
        items: items,
        themeDark: dark
      };
      // 面板构造（生产 :7447-7452）：ComponentContent + wrapBuilder(全局 @Builder)
      const content: ComponentContent<WebContextMenuPanelParams> =
        new ComponentContent<WebContextMenuPanelParams>(ui, wrapBuilder(WebContextMenuPanel), panelParams);
      this.content = content;
      // THIN 材质仅 API>=26 求值（menuMaterial 内部守卫在实参求值前；<26 返回 undefined）
      const mat = menuMaterial(dark);
      const opts: MenuOptions = {
        anchorPosition: { x: px, y: py },
        onAppear: (): void => {
          Diag.webmenu('appear');
        },
        onDisappear: (): void => {
          Diag.webmenu('dismiss');
          this.dismiss();
          this.disposeContent();
        }
      };
      if (mat !== undefined) {
        opts.systemMaterial = mat;
      }
      Diag.webmenu(`show x=${px} y=${py} src=${param.getSourceType()} media=${param.getMediaType()} `
        + `link=${link.length > 0 ? 1 : 0} sel=${selText.length} editable=${editable ? 1 : 0} `
        + `flags=${flags} items=${items.length} mat=${mat !== undefined ? 1 : 0}`);
      ui.getPromptAction().openMenu(content, { id: 'dshm-demo-web-menu-anchor' }, opts).then((): void => {
        Diag.webmenu('open ok');
      }, (e: Error): void => {
        Diag.webmenu(`open fail ${e.message}`);
        this.dismiss();
        this.disposeContent();
      });
      return true;
    } catch (e) {
      // return false 路径不能调 closeContextMenu（系统默认菜单还要用 result）
      this.result = undefined;
      this.disposeContent();
      Diag.webmenu(`fallback exception ${(e as Error).message}`);
      return false;
    }
  }

  /**
   * 语境判定 → 菜单项构建（生产 :7331-7438 逐位移植）。
   *
   * 动作映射（FR-005）：打开链接直开（不二次确认，菜单点击即明确意图）；
   * 复制链接走系统剪贴板；复制/剪切/粘贴/全选走 ArkWeb result；
   * 复制图片走 result.copyImage；保存图片按 API 存在性 typeof 守卫
   * （saveImage 是 API 24 起：API 23 设备上字段不存在）。
   */
  private buildMenuItems(ui: UIContext, param: WebContextMenuParam, result: WebContextMenuResult,
    link: string, selText: string, editable: boolean, flags: number, isImage: boolean): WebContextMenuItem[] {
    const items: WebContextMenuItem[] = [];
    if (link.length > 0) {
      // 打开链接不二次确认：菜单点击即明确意图，与生产 onLoadIntercept 直开口径一致
      items.push({
        label: '打开链接',
        run: (): void => {
          this.runMenuItem(ui, '打开链接', undefined, (): void => {
            this.openExternal(ui, link);
          });
        }
      });
      items.push({
        label: '复制链接',
        run: (): void => {
          this.runMenuItem(ui, '复制链接', undefined, (): void => {
            this.copyText(link).then((): void => {
              // 复制成功无需打扰
            }, (): void => {
              Diag.webmenu('copy-link-fail');
            });
          });
        }
      });
    }
    if (isImage) {
      items.push({
        label: '复制图片',
        run: (): void => {
          this.runMenuItem(ui, '复制图片', (): void => {
            result.copyImage();
          });
        }
      });
      // saveImage 是 API 24 起：API 23 设备上字段不存在，typeof 守卫（生产 :7365 同款）
      if (typeof result.saveImage === 'function') {
        items.push({
          label: '保存图片',
          run: (): void => {
            this.runMenuItem(ui, '保存图片', (): void => {
              result.saveImage();
            });
          }
        });
      }
    }
    if (editable) {
      if ((flags & ContextMenuEditStateFlags.CAN_CUT) !== 0) {
        items.push({
          label: '剪切',
          run: (): void => {
            this.runMenuItem(ui, '剪切', (): void => {
              result.cut();
            });
          }
        });
      }
      if ((flags & ContextMenuEditStateFlags.CAN_COPY) !== 0) {
        items.push({
          label: '复制',
          run: (): void => {
            this.runMenuItem(ui, '复制', (): void => {
              result.copy();
            });
          }
        });
      }
      if ((flags & ContextMenuEditStateFlags.CAN_PASTE) !== 0) {
        items.push({
          label: '粘贴',
          run: (): void => {
            this.runMenuItem(ui, '粘贴', (): void => {
              result.paste();
            });
          }
        });
      }
      if ((flags & ContextMenuEditStateFlags.CAN_SELECT_ALL) !== 0) {
        items.push({
          label: '全选',
          run: (): void => {
            this.runMenuItem(ui, '全选', (): void => {
              result.selectAll();
            });
          }
        });
      }
    } else {
      if ((flags & ContextMenuEditStateFlags.CAN_COPY) !== 0 && selText.length > 0) {
        items.push({
          label: '复制',
          run: (): void => {
            this.runMenuItem(ui, '复制', (): void => {
              result.copy();
            });
          }
        });
      }
      if ((flags & ContextMenuEditStateFlags.CAN_SELECT_ALL) !== 0) {
        items.push({
          label: '全选',
          run: (): void => {
            this.runMenuItem(ui, '全选', (): void => {
              result.selectAll();
            });
          }
        });
      }
    }
    return items;
  }

  /**
   * 收菜单（幂等，生产 :7240-7254）：告诉 ArkWeb「菜单已关」
   * （closeContextMenu），网页恢复交互。closed 防「菜单项点击」与
   * 「onDisappear」双路径重入。
   */
  private dismiss(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    const r: WebContextMenuResult | undefined = this.result;
    this.result = undefined;
    if (r !== undefined) {
      try {
        r.closeContextMenu();
      } catch (e) {
        // 收不了就交还系统兜底，装饰性路径不抛错
      }
    }
  }

  /** 释放菜单的 ComponentContent（幂等；只在菜单确定离场后调；生产 :7257-7267）。 */
  private disposeContent(): void {
    const c: ComponentContent<WebContextMenuPanelParams> | undefined = this.content;
    this.content = undefined;
    if (c !== undefined) {
      try {
        c.dispose();
      } catch (e) {
        // 已释放
      }
    }
  }

  /**
   * 菜单项点击的统一收尾（生产 :7274-7295）：ArkWeb 动作 → closeContextMenu →
   * closeMenu → 后置动作。顺序依据 web.d.ts：result 里没有别的调用时须主动
   * closeContextMenu 收菜单；我们自己的 openMenu 菜单由 closeMenu 收，
   * onDisappear 再做幂等清场。
   */
  private runMenuItem(ui: UIContext, label: string, action?: () => void, post?: () => void): void {
    Diag.webmenu(`item ${label}`);
    if (action !== undefined) {
      try {
        action();
      } catch (e) {
        // 动作失败也照常收菜单
      }
    }
    this.dismiss();
    const c: ComponentContent<WebContextMenuPanelParams> | undefined = this.content;
    if (c !== undefined) {
      try {
        ui.getPromptAction().closeMenu(c);
      } catch (e) {
        // 菜单已在关闭中
      }
    }
    if (post !== undefined) {
      post();
    }
  }

  /**
   * 打开链接拉系统浏览器（生产「打开链接」→ launchExternal → platform
   * OpenLink.ets openExternalUrl 的 demo 等价）：只放行 http/https；
   * openLink（appLinkingOnly: false）让无应用接管时走浏览器兜底。
   */
  private openExternal(ui: UIContext, url: string): void {
    const lower: string = url.trim().toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      Diag.webmenu(`openlink rejected ${url}`);
      return;
    }
    try {
      const ctx: common.UIAbilityContext = ui.getHostContext() as common.UIAbilityContext;
      ctx.openLink(url.trim(), { appLinkingOnly: false }).then((): void => {
        Diag.webmenu(`openlink ok ${url}`);
      }, (e: BusinessError): void => {
        // 失败必须让用户看见（生产纪律）：demo 只留痕，失败弹窗形态见弹窗演示区
        Diag.webmenu(`openlink fail ${e.message}`);
      });
    } catch (e) {
      Diag.webmenu(`openlink throw ${(e as BusinessError).message}`);
    }
  }

  /**
   * 写系统剪贴板（生产 platform/Clipboard.ets copyText 的 demo 等价）；
   * 失败不抛，调用方降级留痕。
   */
  private async copyText(text: string): Promise<boolean> {
    try {
      const data: pasteboard.PasteData =
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      return true;
    } catch (err) {
      return false;
    }
  }
}
