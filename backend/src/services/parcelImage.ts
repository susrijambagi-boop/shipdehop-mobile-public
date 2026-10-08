/** Bounded input validation, not a claim that the contents are safe. */
export function validParcelImage(base64: string, mime: string): boolean {
  if (base64.length > 6_990_508 || base64.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) return false;
  const bytes = Buffer.from(base64, 'base64');
  if (bytes.length < 75 || bytes.length > 5 * 1024 * 1024 || bytes.toString('base64') !== base64) return false;
  if (mime === 'image/jpeg') return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (mime === 'image/png') return bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]));
  return mime === 'image/webp' && bytes.toString('ascii',0,4) === 'RIFF' && bytes.toString('ascii',8,12) === 'WEBP';
}
