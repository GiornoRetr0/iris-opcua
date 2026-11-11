/**
 * OPC UA timestamps as the REST API sends them: `2026-11-10 23:43:40.3923420`, UTC
 * with no offset (the native layer converts the server's UTC DateTime as is).
 *
 * `new Date()` reads that form as *local* time, so the console showed every
 * timestamp off by the browser's UTC offset; and the form is not ISO 8601, so
 * browsers other than Chrome may reject it outright. This builds a real ISO string:
 * `T` separator, at most three fraction digits, `Z`. A string that already carries
 * `Z` or an offset is kept as given.
 *
 * Returns null for anything unparseable and for the OPC UA null DateTime
 * (1601-01-01, the FILETIME epoch), which a server sends in full when it has no
 * timestamp to report.
 */
export function parseIrisUtc(raw: string | null | undefined): Date | null {
  const s = String(raw ?? '').trim();
  if (!s) return null;
  const m = /^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})?$/.exec(s);
  if (!m) return null;
  const [, date, time, frac, zone] = m;
  const ms = frac ? '.' + frac.slice(0, 3).padEnd(3, '0') : '';
  const d = new Date(`${date}T${time}${ms}${zone ?? 'Z'}`);
  if (isNaN(d.getTime()) || d.getUTCFullYear() <= 1601) return null;
  return d;
}

const pad = (n: number) => String(n).padStart(2, '0');

/** Local clock time, HH:MM:SS (24-hour). */
export function localClock(d: Date): string {
  return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

/** Local date and time, YYYY-MM-DD HH:MM:SS. */
export function localDateTime(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${localClock(d)}`;
}
