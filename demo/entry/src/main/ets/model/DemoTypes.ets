/**
 * Demo 全域共享类型（单源，arkts-no-decl-merging：共享类型只在此声明一次）。
 *
 * 各类型的生产对照锚点：
 *   - KnockFile：entry/src/main/ets/system/KnockShareReceiver.ets（同名接口，逐位对齐）
 *   - WebContextMenuItem / WebContextMenuPanelParams：
 *     entry/src/main/ets/pages/WebApp.ets :195-207（同名接口，逐位对齐）
 *   - ThemeMode：demo 侧新增（生产 themeMode 是 string，demo 收敛为三档字面量联合）
 *
 * @module DemoTypes
 */

/**
 * 经 base64 通道送进 Web 层的单个文件载荷（JSON 序列化后嵌入注入脚本）。
 * 三路来源收敛到同一形状：内置样例（rawfile）/ 文件选择器 / 真实接收落盘读取。
 */
export interface KnockFile {
  /** 展示文件名。 */
  name: string;
  /** MIME 类型；推不出为空串，由垫片兜底 application/octet-stream。 */
  mime: string;
  /** 原始字节数（诊断用）。 */
  size: number;
  /** 文件内容 base64。 */
  base64: string;
}

/**
 * 沉浸光感·混合承载：网页右键/长按菜单的应用侧菜单项。
 * ArkTS 禁止无类型对象字面量（arkts-no-untyped-obj-literal），这里给出显式形状；
 * label 进 MenuItem.content，run 由菜单项点击的统一收尾执行。
 */
export interface WebContextMenuItem {
  label: string;
  run: () => void;
}

/**
 * 网页上下文菜单面板的入参。themeDark 显式定 WithTheme 深浅——
 * 生产真机结论（2026-10-11）：SYSTEM 档实测仍给深色玻璃，必须显式指定。
 */
export interface WebContextMenuPanelParams {
  items: WebContextMenuItem[];
  themeDark: boolean;
}

/**
 * demo 主题档位：System=跟随系统明暗；Light/Dark=显式指定。
 * 材质/面板明暗一律经 themeDark(mode, systemDark) 显式求值，不用 SYSTEM 档（生产纪律）。
 */
export type ThemeMode = 'System' | 'Light' | 'Dark';
