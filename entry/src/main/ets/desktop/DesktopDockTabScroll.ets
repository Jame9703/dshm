/** Scroll to the nearest edge that exposes the selected tab and its actions. */
export function desktopDockTabRevealDelta(viewStart: number, viewWidth: number,
  tabStart: number, tabWidth: number): number {
  if (!Number.isFinite(viewStart) || !Number.isFinite(viewWidth) || !Number.isFinite(tabStart) ||
    !Number.isFinite(tabWidth) || viewWidth <= 0 || tabWidth <= 0) { return 0; }
  const leading = tabStart - viewStart;
  const trailing = leading + tabWidth - viewWidth;
  if (tabWidth > viewWidth) { return trailing; }
  return leading < 0 ? leading : Math.max(0, trailing);
}
