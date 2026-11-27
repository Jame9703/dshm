import { getNumber, getRecord, getString } from 'connection';

export const PAGE_CARD: string = 'create_personalized_page';
export const PLUGIN_CARD: string = 'enable_official_plugin';

export interface DesktopActionCard {
  id: string;
  action: string;
  title: string;
  brief: string;
  details?: Object;
  phase: string;
  data?: Object;
}

export class DesktopActionCardState {
  private sequence: number = -1;
  cards: Map<number, DesktopActionCard> = new Map();

  clear(): void {
    this.sequence = -1;
    this.cards = new Map();
  }

  observe(values: Object | undefined, sequence: number): boolean {
    const view = getRecord(values, 'actionCards');
    if (view === undefined || sequence <= this.sequence) { return false; }
    const proposals = getRecord(view, 'proposals');
    const decisions = getRecord(view, 'decisions');
    const cards: Map<number, DesktopActionCard> = new Map();
    if (proposals !== undefined) {
      for (const key of Object.keys(proposals)) {
        const proposal = getRecord(proposals, key);
        const turn = getNumber(proposal, 'turn');
        const id = getString(proposal, 'cardId') ?? '';
        if (turn === undefined || !id || (cards.get(turn)?.id ?? id) < id) { continue; }
        const decision = getRecord(decisions, id);
        cards.set(turn, { id: id, action: getString(proposal, 'action') ?? '',
          title: getString(proposal, 'title') ?? '', brief: getString(proposal, 'brief') ?? '',
          details: getRecord(proposal, 'details'), phase: getString(decision, 'phase') ?? '', data: getRecord(decision, 'data') });
      }
    }
    this.sequence = sequence;
    this.cards = cards;
    return true;
  }
}

/** The host owns card admission. Only strip its fenced metadata from the displayed answer. */
export function desktopHideActionCardFences(text: string): string {
  if (!/action-card/i.test(text)) { return text; }
  const visible: string[] = [];
  let closing: RegExp | undefined;
  let hidden = false;
  for (const line of text.split(/\r?\n/)) {
    if (closing !== undefined) {
      if (closing.test(line)) {
        closing = undefined;
        if (!hidden) { visible.push(line); }
        hidden = false;
      } else if (!hidden) {
        visible.push(line);
      }
      continue;
    }
    const fence = /^( {0,3})((?:[-+*]|\d{1,9}[.)]) {1,4})?(`{3,}|~{3,})(.*)$/.exec(line);
    if (fence !== null && !(fence[3].startsWith('`') && fence[4].includes('`'))) {
      const indent = fence[2] === undefined ? 3 : fence[1].length + fence[2].length + 3;
      closing = new RegExp(`^ {0,${indent}}${fence[3].charAt(0)}{${fence[3].length},}[ \\t]*$`);
      hidden = /^action-card(?=[^\w-]|$)/i.test(fence[4].trimStart());
    }
    if (!hidden) { visible.push(line); }
  }
  return visible.join('\n');
}
