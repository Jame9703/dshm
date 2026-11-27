/** Display formats owned by the Chat statistics components. */
export function desktopChatCompactTokens(value: number): string {
  if (value < 1000) { return String(value); }
  const scale = value < 1000000 ? 1000 : 1000000;
  const units = value / scale;
  return String(units >= 100 ? Math.round(units) : Math.round(units * 10) / 10) +
    (scale === 1000 ? 'K' : 'M');
}

export function desktopChatExactTokens(value: number): string {
  const digits = String(value);
  const groups: string[] = [];
  for (let end = digits.length; end > 0; end -= 3) {
    groups.unshift(digits.slice(Math.max(0, end - 3), end));
  }
  return groups.join(',');
}

export function desktopChatTokensPerSecond(tokens: number, decodeMs: number): string {
  if (decodeMs <= 0) { return ''; }
  const speed = tokens / (decodeMs / 1000);
  if (!Number.isFinite(speed)) { return ''; }
  return String(speed >= 10 ? Math.round(speed) : Math.round(speed * 10) / 10);
}

function roundedPercentUnits(read: number, input: number, scale: number): number {
  const doubled = scale * 2;
  const quotient = Math.floor(input / doubled);
  const remainder = input % doubled;
  let low = 0;
  let high = scale;
  while (low < high) {
    const candidate = Math.floor((low + high + 1) / 2);
    const factor = candidate * 2 - 1;
    const threshold = factor * quotient + Math.ceil(factor * remainder / doubled);
    if (read >= threshold) { low = candidate; } else { high = candidate - 1; }
  }
  return low;
}

/** Preserve the distinction between a full hit and a rounded partial hit, even at safe-integer limits. */
export function desktopChatCachePercent(read: number | undefined, input: number, perTurn: boolean = false): string {
  if (read === undefined || input <= 0 || read < 0 || read > input) { return ''; }
  const missed = input - read;
  if (missed === 0) { return '100'; }
  const scale = perTurn ? 1000 : 100;
  const rounded = roundedPercentUnits(read, input, scale);
  if (rounded < scale) { return String(perTurn ? rounded / 10 : rounded); }
  let places = 1;
  let doubledGap = missed * 200;
  const inputTens = Math.floor(input / 10);
  while (doubledGap <= inputTens) {
    doubledGap *= 10;
    places++;
  }
  const inputOnes = input % 10;
  let roundedLoss = 5;
  for (let loss = 1; loss < 5; loss++) {
    const factor = loss * 2 + 1;
    if (doubledGap <= factor * inputTens + Math.floor(factor * inputOnes / 10)) {
      roundedLoss = loss;
      break;
    }
  }
  return '99.' + '9'.repeat(places - 1) + String(10 - roundedLoss);
}
