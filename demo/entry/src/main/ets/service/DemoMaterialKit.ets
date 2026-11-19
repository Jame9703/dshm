/**
 * 沉浸光感材质工具（API 26 `uiMaterial`）——demo 版**共享单源**。
 *
 * 【移植锚点】逐位移植生产 platform/src/main/ets/ui/ImmersiveMaterialKit.ets，
 * 另加 menuMaterial(themeDark) 包装（生产 WebApp.ets handleWebContextMenuShow 的
 * 内联 THIN 构造收敛到此处，demo 一职责一源）。
 *
 * 【两条真机血泪换来的纪律（照搬）】
 *   ① `uiMaterial.ImmersiveStyle` 在未实现该能力的设备上是 `undefined`——真机踩过
 *      `Cannot read property THICK of undefined` ⇒ 组件更新抛错、**闪退循环**
 *      （生产 docs/196）；
 *   ② 装饰性能力绝不该让界面起不来 ⇒ **API 判定 + try/catch 双保险**，取不到就
 *      返回 `undefined`（`systemMaterial(undefined)` = 不挂材质，纯色底照常可读）。
 *
 * 【守卫在实参求值前（关键，2026-11-17 生产教训）】`style` 实参在进入
 * immersiveMaterialOf **之前**求值——API<26 设备上 `uiMaterial`/`ImmersiveStyle`
 * 可能是 `undefined`，裸求值 `.THIN`/`.THICK` 会当场抛错（函数内部的 API 判定
 * 来不及兜）。以 `uiMaterial.ImmersiveStyle.X` 作实参的调用点必须先判
 * `deviceInfo.sdkApiVersion >= 26` 再进 try（下方各包装即此范式）。
 *
 * 【第三个纪律：不整块大面铺】材质只挂弹窗 / 菜单面板 / 小控件（染蓝教训）。
 *
 * @module DemoMaterialKit
 */
import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Diag } from './Diag';

/**
 * 构造沉浸光感材质；**取不到就返回 `undefined`**（调用方把 undefined 传给
 * `systemMaterial` 即"不挂材质"，界面按纯色底渲染——绝不因装饰能力缺席而崩）。
 *
 * @param style 材质档位（THIN/REGULAR/THICK/ULTRA_THIN/ULTRA_THICK）
 * @param interactive 是否带按压触点光感（交互控件用 true；弹窗/外壳用 false）
 */
export function immersiveMaterialOf(style: uiMaterial.ImmersiveStyle,
  interactive: boolean): uiMaterial.ImmersiveMaterial | undefined {
  if (deviceInfo.sdkApiVersion < 26) {
    return undefined;
  }
  try {
    const opts: uiMaterial.ImmersiveOptions = {
      style: style,
      applyShadow: true,
      interactive: interactive
    };
    return new uiMaterial.ImmersiveMaterial(opts);
  } catch (e) {
    return undefined;
  }
}

/**
 * 弹窗/半模态 options 用的材质（THICK + 非交互）。
 * `AlertDialogParam.systemMaterial` 等字段直接吃这个函数的返回值；
 * undefined 时该字段**省略**（options 里传 undefined 等于不设置）。
 */
export function dialogMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  if (deviceInfo.sdkApiVersion < 26) {
    return undefined;
  }
  try {
    return immersiveMaterialOf(uiMaterial.ImmersiveStyle.THICK, false);
  } catch (e) {
    return undefined;
  }
}

/**
 * 常驻外壳条带（自绘顶栏）用的材质（THIN + 非交互）。
 * ⚠️ 只挂**条带**，不铺大面（染蓝教训，见文件头注）。
 */
export function shellMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  if (deviceInfo.sdkApiVersion < 26) {
    return undefined;
  }
  try {
    return immersiveMaterialOf(uiMaterial.ImmersiveStyle.THIN, false);
  } catch (e) {
    return undefined;
  }
}

/**
 * 交互控件（按钮/页签）用的材质（REGULAR + 按压触点光感）。
 */
export function controlMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  if (deviceInfo.sdkApiVersion < 26) {
    return undefined;
  }
  try {
    return immersiveMaterialOf(uiMaterial.ImmersiveStyle.REGULAR, true);
  } catch (e) {
    return undefined;
  }
}

/**
 * 网页右键/长按菜单面板用的材质（THIN + 非交互）——生产 WebApp.ets
 * handleWebContextMenuShow 的内联构造（API≥26 才求值 THIN）收敛到本包装。
 *
 * 【明暗显式（生产纪律：不用 SYSTEM 档）】`ImmersiveOptions`（API 26 d.ts 已核）
 * 没有明暗字段——面板明暗由 WithTheme 的 colorMode 显式指定。themeDark 形参是
 * 调用方「明暗已显式求值」的契约：面板与本函数必须共用同一个显式值；这里把它
 * 写入 diag-webmenu 一行留痕（真机可核对「材质构造时的明暗」与「面板实际明暗」
 * 是否一致），不参与材质参数本身。
 *
 * 【守卫在实参求值前】API<26 提前返回，`uiMaterial.ImmersiveStyle.THIN` 只在
 * API≥26 分支求值（docs/196 闪退循环教训照搬）。
 */
export function menuMaterial(themeDark: boolean): uiMaterial.ImmersiveMaterial | undefined {
  if (deviceInfo.sdkApiVersion < 26) {
    return undefined;
  }
  Diag.webmenu(`material themeDark=${themeDark ? 1 : 0}`);
  try {
    return immersiveMaterialOf(uiMaterial.ImmersiveStyle.THIN, false);
  } catch (e) {
    return undefined;
  }
}
