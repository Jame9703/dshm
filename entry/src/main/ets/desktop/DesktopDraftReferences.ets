export interface DesktopDraftReference {
  start: number;
  end: number;
  kind: string;
  label: string;
}

export interface DesktopComposerDraft {
  text: string;
  references: DesktopDraftReference[];
  recalledSequence?: number;
}

export const EMPTY_DESKTOP_DRAFT: DesktopComposerDraft = { text: '', references: [] };

export function sameDesktopDraft(left: DesktopComposerDraft, right: DesktopComposerDraft): boolean {
  return left.text === right.text && left.references.length === right.references.length &&
    left.references.every((reference: DesktopDraftReference, index: number): boolean => {
      const other = right.references[index];
      return reference.start === other.start && reference.end === other.end &&
        reference.kind === other.kind && reference.label === other.label;
    });
}

// The editor stores an inline reference as one native position. The host receives the full token.
export function desktopDraftWireOffset(draft: DesktopComposerDraft, editorOffset: number): number {
  let offset = editorOffset;
  for (const reference of draft.references) {
    if (offset <= reference.start) { break; }
    offset += reference.end - reference.start - 1;
  }
  return offset;
}

export function desktopDraftEditorOffset(draft: DesktopComposerDraft, wireOffset: number): number {
  let offset = wireOffset;
  for (const reference of draft.references) {
    if (wireOffset <= reference.start) { break; }
    offset -= Math.min(wireOffset, reference.end) - reference.start - 1;
  }
  return offset;
}

// Keep the canonical offsets while hiding token syntax from the @ and / trigger detectors.
export function desktopDraftTriggerText(draft: DesktopComposerDraft): string {
  let text = '';
  let start = 0;
  for (const reference of draft.references) {
    text += draft.text.slice(start, reference.start) + '\uFFFC'.repeat(reference.end - reference.start);
    start = reference.end;
  }
  return text + draft.text.slice(start);
}

export function replaceDesktopDraftRange(draft: DesktopComposerDraft, start: number, end: number, text: string,
  inserted?: DesktopDraftReference): DesktopComposerDraft {
  const references: DesktopDraftReference[] = [];
  const delta = text.length - (end - start);
  for (const reference of draft.references) {
    if (reference.end <= start) { references.push(reference); }
  }
  if (inserted !== undefined) { references.push(inserted); }
  for (const reference of draft.references) {
    if (reference.start >= end) {
      references.push({ start: reference.start + delta, end: reference.end + delta,
        kind: reference.kind, label: reference.label });
    }
  }
  return { text: draft.text.slice(0, start) + text + draft.text.slice(end), references: references };
}
