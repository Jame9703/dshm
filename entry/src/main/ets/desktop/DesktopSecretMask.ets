/*
 * Credential recognition follows @deepseek-ai/dsh-client-ui-secret-mask.
 *
 * MIT License
 *
 * Copyright (c) 2026 DeepSeek
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

const KEY = 1;
const ALNUM = 2;
const WORD = 4;
const ALNUM_DASH = 8;
const UPPER_ALNUM = 16;
const LABEL = 32;
const SCHEME = 64;
const LOWER = 128;
const USER = 256;

const KEY_BLOCK = 0;
const ADDRESS = 1;
const PREFIXED = 2;

const RUN = 0;
const BOUNDED = 1;
const SK = 2;
const GOOGLE = 3;
const JWT = 4;

interface CredentialFormat {
  literal: string;
  kind: number;
  shape: number;
  run: number;
  min: number;
  max: number;
}

function prefixed(literal: string, shape: number, run: number, min: number, max: number = 0): CredentialFormat {
  return { literal: literal, kind: PREFIXED, shape: shape, run: run, min: min, max: max };
}

const FORMATS: CredentialFormat[] = [
  { literal: '-----BEGIN ', kind: KEY_BLOCK, shape: RUN, run: 0, min: 0, max: 0 },
  { literal: '://', kind: ADDRESS, shape: RUN, run: 0, min: 0, max: 0 },
  prefixed('sk-', SK, KEY, 20),
  prefixed('AIza', GOOGLE, KEY, 35),
  prefixed('ghp_', RUN, ALNUM, 36),
  prefixed('gho_', RUN, ALNUM, 36),
  prefixed('ghu_', RUN, ALNUM, 36),
  prefixed('ghs_', RUN, ALNUM, 36),
  prefixed('ghr_', RUN, ALNUM, 36),
  prefixed('github_pat_', RUN, WORD, 22),
  prefixed('glpat-', RUN, KEY, 20),
  prefixed('npm_', RUN, ALNUM, 36),
  prefixed('hf_', RUN, ALNUM, 30),
  prefixed('AKIA', BOUNDED, UPPER_ALNUM, 16, 16),
  prefixed('ASIA', BOUNDED, UPPER_ALNUM, 16, 16),
  prefixed('LTAI', BOUNDED, ALNUM, 12, 20),
  prefixed('AKID', BOUNDED, ALNUM, 28, 36),
  prefixed('xoxa-', RUN, ALNUM_DASH, 10),
  prefixed('xoxb-', RUN, ALNUM_DASH, 10),
  prefixed('xoxp-', RUN, ALNUM_DASH, 10),
  prefixed('xoxr-', RUN, ALNUM_DASH, 10),
  prefixed('xoxs-', RUN, ALNUM_DASH, 10),
  prefixed('sk_live_', RUN, ALNUM, 16),
  prefixed('sk_test_', RUN, ALNUM, 16),
  prefixed('rk_live_', RUN, ALNUM, 16),
  prefixed('rk_test_', RUN, ALNUM, 16),
  prefixed('whsec_', RUN, ALNUM, 24),
  prefixed('eyJ', JWT, KEY, 8, 2048)
];

export interface DesktopSecretRange {
  start: number;
  end: number;
  masked: string;
}

const KEY_NEXT = 8;
const ALNUM_SLOT = 9;
const WORD_SLOT = 11;
const ALNUM_DASH_SLOT = 13;
const UPPER_ALNUM_SLOT = 15;
const USER_SLOT = 17;
const PASSWORD_SLOT = 19;
const DIGIT_FROM = 21;
const DIGIT_AT = 22;
const BLOCK_FROM = 23;
const BLOCK_END_START = 24;
const BLOCK_END = 25;
const CANDIDATE_START = 26;
const MEMO_SIZE = 27;

function classTable(): Uint16Array {
  const classes = new Uint16Array(128);
  for (let code = 0; code < 128; code++) {
    const upper = code >= 65 && code <= 90;
    const lower = code >= 97 && code <= 122;
    const digit = code >= 48 && code <= 57;
    const alnum = upper || lower || digit;
    const authority = !((code >= 9 && code <= 13) || code === 32 || code === 47 ||
      code === 64 || code === 63 || code === 35);
    classes[code] = (alnum || code === 95 || code === 45 ? KEY : 0) |
      (alnum ? ALNUM : 0) | (alnum || code === 95 ? WORD : 0) |
      (alnum || code === 45 ? ALNUM_DASH : 0) | (upper || digit ? UPPER_ALNUM : 0) |
      (upper || digit || code === 32 ? LABEL : 0) |
      (lower || digit || code === 43 || code === 46 || code === 45 ? SCHEME : 0) |
      (lower ? LOWER : 0) | (authority && code !== 58 ? USER : 0);
  }
  return classes;
}

function isWideSpace(code: number): boolean {
  return code === 0xa0 || code === 0x1680 || (code >= 0x2000 && code <= 0x200a) ||
    code === 0x2028 || code === 0x2029 || code === 0x202f || code === 0x205f || code === 0x3000 || code === 0xfeff;
}

function runEnd(pattern: RegExp, text: string, start: number): number {
  pattern.lastIndex = start;
  pattern.test(text);
  return pattern.lastIndex;
}

function overlap(literal: string): number {
  for (let size = literal.length - 1; size > 0; size--) {
    const suffix = literal.slice(-size);
    if (FORMATS.some((format: CredentialFormat): boolean => format.literal.startsWith(suffix))) { return size; }
  }
  return 0;
}

function maskCharacters(text: string): string {
  return text.replace(new RegExp('[^\\r\\n]', 'gu'), '*');
}

function maskKeyBlock(text: string, start: number, end: number): string {
  const firstLine = text.indexOf('\n', start);
  if (firstLine < 0 || firstLine >= end) { return maskCharacters(text.slice(start, end)); }
  const bodyStart = firstLine + 1;
  const footer = text.lastIndexOf('\n-----END', end - '\n-----END'.length);
  const bodyEnd = footer >= bodyStart ? footer : end;
  return text.slice(start, bodyStart) + maskCharacters(text.slice(bodyStart, bodyEnd)) + text.slice(bodyEnd, end);
}

class CredentialScanner {
  private readonly classes = classTable();
  private readonly formats = new Map<string, CredentialFormat>();
  private readonly overlaps = new Map<string, number>();
  // The delimiter and provider literals in FORMATS are all literal outside a character class.
  private readonly prefixes = new RegExp(FORMATS.map((format: CredentialFormat): string => format.literal).join('|'), 'g');
  private readonly keyRun = new RegExp('[A-Za-z0-9_-]*', 'y');
  private readonly alnumRun = new RegExp('[A-Za-z0-9]*', 'y');
  private readonly wordRun = new RegExp('\\w*', 'y');
  private readonly alnumDashRun = new RegExp('[A-Za-z0-9-]*', 'y');
  private readonly upperAlnumRun = new RegExp('[A-Z0-9]*', 'y');
  private readonly userRun = new RegExp('[^\\s/:@?#]*', 'y');
  private readonly passwordRun = new RegExp('[^\\s/@?#]*', 'y');
  private readonly nonDigits = new RegExp('\\D*', 'y');
  // Reuse measured runs and block ends when prefixes overlap. Each pair is [start, end].
  private readonly memo = new Int32Array(MEMO_SIZE).fill(-1);
  private source: string = '';

  constructor() {
    for (const format of FORMATS) {
      this.formats.set(format.literal, format);
      this.overlaps.set(format.literal, overlap(format.literal));
    }
  }

  ranges(source: string): DesktopSecretRange[] {
    const ranges: DesktopSecretRange[] = [];
    this.source = source;
    this.memo.fill(-1);
    try {
      let offset = 0;
      while (offset < source.length) {
        const range = this.next(offset);
        if (range === undefined) { break; }
        ranges.push(range);
        offset = range.end;
      }
      return ranges;
    } finally {
      this.source = '';
    }
  }

  /** The earliest candidate owns the mask for all overlapping matches. */
  private next(from: number): DesktopSecretRange | undefined {
    const length = this.source.length;
    let start = -1;
    let end = -1;
    let kind = PREFIXED;
    let plain = true;
    let deferredEnd = this.addressBefore(from);
    let deferredStart = deferredEnd < 0 ? -1 : this.memo[CANDIDATE_START];
    this.prefixes.lastIndex = from;
    let match = this.prefixes.exec(this.source);
    while (match !== null) {
      const at = match.index;
      const literal = match[0];
      const format = this.formats.get(literal);
      this.prefixes.lastIndex -= this.overlaps.get(literal) ?? 0;
      // An address candidate starts at its password, which lies after the match for "://".
      if (deferredStart >= 0 && deferredStart <= at) {
        if (start < 0) {
          start = deferredStart;
          end = deferredEnd;
          kind = ADDRESS;
        } else if (deferredStart >= end) {
          break;
        }
        deferredStart = -1;
      }
      if (start >= 0 && (at >= end || end === length)) { break; }
      if (format?.kind === ADDRESS) {
        deferredEnd = this.addressPassword(at);
        deferredStart = deferredEnd < 0 ? -1 : this.memo[CANDIDATE_START];
      } else if (format !== undefined) {
        const candidate = format.kind === KEY_BLOCK ? this.keyBlockEnd(at) : this.prefixedEnd(format, at);
        if (candidate >= 0 && start < 0) {
          start = at;
          end = candidate;
          kind = format.kind;
          plain = kind === PREFIXED;
        } else if (candidate > end) {
          end = candidate;
          if (format.kind !== PREFIXED) { plain = false; }
        }
      }
      match = this.prefixes.exec(this.source);
    }
    if (start < 0 && deferredStart >= 0) {
      start = deferredStart;
      end = deferredEnd;
      kind = ADDRESS;
    }
    if (start < 0) { return undefined; }
    if (kind === ADDRESS) {
      return { start: start, end: end, masked: maskCharacters(this.source.slice(start, end)) };
    }
    if (kind === KEY_BLOCK) {
      return { start: start, end: end, masked: maskKeyBlock(this.source, start, end) };
    }
    const readable = this.source.slice(start, start + 8);
    const remainder = plain ? '*'.repeat(end - start - 8) : maskCharacters(this.source.slice(start + 8, end));
    return { start: start, end: end, masked: readable + remainder };
  }

  private wordAt(index: number): boolean {
    const code = this.source.charCodeAt(index);
    return code < 128 && (this.classes[code] & WORD) !== 0;
  }

  private userCode(code: number): boolean {
    return code < 128 ? (this.classes[code] & USER) !== 0 : Number.isFinite(code) && !isWideSpace(code);
  }

  private keyRunEnd(start: number): number {
    for (let slot = 0; slot < KEY_NEXT; slot += 2) {
      if (this.memo[slot] <= start && start <= this.memo[slot + 1]) { return this.memo[slot + 1]; }
    }
    const end = runEnd(this.keyRun, this.source, start);
    const next = (this.memo[KEY_NEXT] + 1) & 3;
    this.memo[KEY_NEXT] = next;
    this.memo[2 * next] = start;
    this.memo[2 * next + 1] = end;
    return end;
  }

  private memoRunEnd(pattern: RegExp, start: number, slot: number): number {
    if (this.memo[slot] <= start && start <= this.memo[slot + 1]) { return this.memo[slot + 1]; }
    const end = runEnd(pattern, this.source, start);
    this.memo[slot] = start;
    this.memo[slot + 1] = end;
    return end;
  }

  private nextDigit(start: number): number {
    if (this.memo[DIGIT_FROM] <= start && start <= this.memo[DIGIT_AT]) { return this.memo[DIGIT_AT]; }
    this.memo[DIGIT_FROM] = start;
    this.memo[DIGIT_AT] = runEnd(this.nonDigits, this.source, start);
    return this.memo[DIGIT_AT];
  }

  /** Offset after [A-Z0-9 ]{0,40}PRIVATE KEY----- at start, or -1. */
  private privateKeyLabelEnd(start: number): number {
    const limit = Math.min(this.source.length, start + 52);
    let index = start;
    while (index < limit) {
      const code = this.source.charCodeAt(index);
      if (code > 127 || (this.classes[code] & LABEL) === 0) { break; }
      index++;
    }
    const tail = index - 'PRIVATE KEY'.length;
    return index < start + 52 && tail >= start && this.source.startsWith('PRIVATE KEY-----', tail) ?
      tail + 'PRIVATE KEY-----'.length : -1;
  }

  private keyBlockEnd(at: number): number {
    const header = this.privateKeyLabelEnd(at + '-----BEGIN '.length);
    if (header < 0) { return -1; }
    if (this.memo[BLOCK_FROM] <= header && header <= this.memo[BLOCK_END_START]) { return this.memo[BLOCK_END]; }
    const length = this.source.length;
    this.memo[BLOCK_FROM] = header;
    this.memo[BLOCK_END_START] = length;
    this.memo[BLOCK_END] = length;
    const marker = '-----END ';
    for (let line = this.source.indexOf(marker, header); line >= 0; line = this.source.indexOf(marker, line + 1)) {
      const end = this.privateKeyLabelEnd(line + marker.length);
      if (end < 0) { continue; }
      this.memo[BLOCK_END_START] = line;
      this.memo[BLOCK_END] = end;
      break;
    }
    return this.memo[BLOCK_END];
  }

  /** Whether a lower-case URL scheme of 2–16 characters ends at the delimiter. */
  private schemeBefore(at: number): boolean {
    for (let start = at - 1; start >= 0 && start >= at - 16; start--) {
      const code = this.source.charCodeAt(start);
      const bits = code < 128 ? this.classes[code] : 0;
      if ((bits & SCHEME) === 0) { return false; }
      if ((bits & LOWER) !== 0 && at - start >= 2 && !this.wordAt(start - 1)) { return true; }
    }
    return false;
  }

  private addressPassword(at: number): number {
    if (!this.schemeBefore(at)) { return -1; }
    const userStart = at + 3;
    const userEnd = this.memoRunEnd(this.userRun, userStart, USER_SLOT);
    if (userEnd - userStart > 256 || this.source.charCodeAt(userEnd) !== 58) { return -1; }
    const start = userEnd + 1;
    const end = this.memoRunEnd(this.passwordRun, start, PASSWORD_SLOT);
    if (end === start || this.source.charCodeAt(end) !== 64) { return -1; }
    this.memo[CANDIDATE_START] = start;
    return end;
  }

  /** Look behind the scan cursor for a delimiter that starts an address whose password still lies ahead. */
  private addressBefore(from: number): number {
    if (from < 3) { return -1; }
    const source = this.source;
    if (source.startsWith('://', from - 1)) { return this.addressPassword(from - 1); }
    if (source.startsWith('://', from - 2)) { return this.addressPassword(from - 2); }
    let index = from - 1;
    const before = source.charCodeAt(index);
    let passwordStart: number;
    if (before === 58) {
      passwordStart = from;
      index--;
    } else if (this.userCode(before)) {
      const userEnd = this.memoRunEnd(this.userRun, from, USER_SLOT);
      if (source.charCodeAt(userEnd) !== 58) { return -1; }
      passwordStart = userEnd + 1;
    } else {
      return source.startsWith('://', from - 3) ? this.addressPassword(from - 3) : -1;
    }
    const passwordEnd = this.memoRunEnd(this.passwordRun, passwordStart, PASSWORD_SLOT);
    if (passwordEnd === passwordStart || source.charCodeAt(passwordEnd) !== 64) { return -1; }
    const lowest = Math.max(0, passwordStart - 258);
    while (index >= lowest && this.userCode(source.charCodeAt(index))) { index--; }
    return index >= 2 && source.startsWith('://', index - 2) ? this.addressPassword(index - 2) : -1;
  }

  private tokenEnd(type: number, start: number): number {
    switch (type) {
      case ALNUM: return this.memoRunEnd(this.alnumRun, start, ALNUM_SLOT);
      case WORD: return this.memoRunEnd(this.wordRun, start, WORD_SLOT);
      case ALNUM_DASH: return this.memoRunEnd(this.alnumDashRun, start, ALNUM_DASH_SLOT);
      case UPPER_ALNUM: return this.memoRunEnd(this.upperAlnumRun, start, UPPER_ALNUM_SLOT);
      default: return this.keyRunEnd(start);
    }
  }

  private prefixedEnd(format: CredentialFormat, at: number): number {
    if (this.wordAt(at - 1)) { return -1; }
    const start = at + format.literal.length;
    if (format.shape === SK) {
      const digit = this.nextDigit(start);
      if (digit - start > 255) { return -1; }
      const end = this.keyRunEnd(start);
      return end - start >= format.min && digit < end ? end : -1;
    }
    const end = this.tokenEnd(format.run, start);
    const length = end - start;
    if (length < format.min) { return -1; }
    if (format.shape === RUN) { return end; }
    if (format.shape === GOOGLE) { return start + format.min; }
    if (format.shape === BOUNDED) { return length <= format.max && !this.wordAt(end) ? end : -1; }
    if (length > format.max || !this.source.startsWith('.eyJ', end)) { return -1; }
    const payloadStart = end + 4;
    const payloadEnd = this.keyRunEnd(payloadStart);
    if (payloadEnd - payloadStart < format.min || this.source.charCodeAt(payloadEnd) !== 46) { return -1; }
    const signatureEnd = this.keyRunEnd(payloadEnd + 1);
    return signatureEnd - (payloadEnd + 1) >= format.min ? signatureEnd : -1;
  }
}

let scanner: CredentialScanner | undefined;

export function desktopSecretRanges(source: string): DesktopSecretRange[] {
  if (!source) { return []; }
  const current = scanner ?? new CredentialScanner();
  scanner = current;
  return current.ranges(source);
}
