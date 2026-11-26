import { window } from '@kit.ArkUI';

/** 子窗与最近一次宠物本体包围盒（物理像素），供宿主主窗「藏到宠物身下」定位。 */
export class PetWindowHolder {
  static sub: window.Window | undefined = undefined;
  static boxX: number = -1;
  static boxY: number = -1;
  static boxSize: number = 0;
  /** 最近一次宠物本体快速位移（拖拽）的时间戳；用于拖动期临时套宠物形状掩码。 */
  static lastFastMove: number = 0;
  static lastBoxX: number = -1;
  static lastBoxY: number = -1;
}
