export function toMinorUnits(amount: number, currency: string): number {
  const zeroDecimal = new Set(['BIF', 'CLP', 'DJF', 'GNF', 'JPY', 'KMF', 'KRW', 'MGA', 'PYG', 'RWF', 'UGX', 'VND', 'VUV', 'XAF', 'XOF', 'XPF']);
  return Math.round(amount * (zeroDecimal.has(currency.toUpperCase()) ? 1 : 100));
}

export function fromMinorUnits(amount: number, currency: string): number {
  const zeroDecimal = new Set(['BIF', 'CLP', 'DJF', 'GNF', 'JPY', 'KMF', 'KRW', 'MGA', 'PYG', 'RWF', 'UGX', 'VND', 'VUV', 'XAF', 'XOF', 'XPF']);
  return amount / (zeroDecimal.has(currency.toUpperCase()) ? 1 : 100);
}

export function feeFor(base: number, basisPoints: number): number {
  return Math.round(base * basisPoints) / 10_000;
}
