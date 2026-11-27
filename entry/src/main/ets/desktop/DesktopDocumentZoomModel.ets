export const DESKTOP_DOCUMENT_ZOOM_MINIMUM: number = 0.25;
export const DESKTOP_DOCUMENT_ZOOM_MAXIMUM: number = 4;
const ZOOM_STEP: number = 0.25;
export const DESKTOP_DOCUMENT_ZOOM_PRESETS: number[] = [0.25, 0.5, 1, 1.5, 2];

export interface DesktopDocumentViewState {
  page: number;
  scale: number;
  fitWidth: boolean;
}

export function desktopFitWidthZoom(viewportWidth: number, intrinsicWidth?: number, horizontalInset: number = 24):
  number {
  if (intrinsicWidth === undefined || intrinsicWidth <= 0) { return 1; }
  return Math.min(1, Math.max(1, viewportWidth - horizontalInset) / intrinsicWidth);
}

export function clampDesktopDocumentZoom(scale: number, minimum: number = DESKTOP_DOCUMENT_ZOOM_MINIMUM,
  maximum: number = DESKTOP_DOCUMENT_ZOOM_MAXIMUM): number {
  return Math.min(maximum, Math.max(minimum, Number.isFinite(scale) ? scale : 1));
}

export function steppedDesktopDocumentZoom(scale: number, direction: number,
  minimum: number = DESKTOP_DOCUMENT_ZOOM_MINIMUM, maximum: number = DESKTOP_DOCUMENT_ZOOM_MAXIMUM): number {
  const step: number = direction < 0 ? Math.ceil(scale / ZOOM_STEP) - 1 : Math.floor(scale / ZOOM_STEP) + 1;
  return clampDesktopDocumentZoom(step * ZOOM_STEP, minimum, maximum);
}

export function desktopDocumentZoomOffset(viewport: number, intrinsic: number, previous: number, next: number,
  offset: number, position: number, inset: number = 24): number {
  const oldSize: number = intrinsic * previous;
  const newSize: number = intrinsic * next;
  const oldMargin: number = Math.max(inset / 2, (viewport - oldSize) / 2);
  const newMargin: number = Math.max(inset / 2, (viewport - newSize) / 2);
  const anchor: number = offset + position - oldMargin;
  const candidate: number = anchor >= 0 && anchor <= oldSize
    ? newMargin + anchor * (next / previous) - position : (offset + position) * (next / previous) - position;
  return Math.max(0, Math.min(candidate, Math.max(0, newSize + inset - viewport)));
}
