/** Uppercase hex of a byte buffer: how certificates and keys are uploaded. */
export function bytesToHex(buf: ArrayBuffer): string {
  let out = '';
  for (const b of new Uint8Array(buf)) out += b.toString(16).padStart(2, '0');
  return out.toUpperCase();
}
