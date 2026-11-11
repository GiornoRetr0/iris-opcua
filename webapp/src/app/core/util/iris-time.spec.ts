import { parseIrisUtc, localClock, localDateTime } from './iris-time';

describe('parseIrisUtc', () => {
  it('reads the API form as UTC, not local time', () => {
    const d = parseIrisUtc('2026-11-10 23:41:29.3923420');
    expect(d?.toISOString()).toBe('2026-11-10T23:41:29.392Z');
  });

  it('accepts no fraction, a T separator, and keeps an explicit zone', () => {
    expect(parseIrisUtc('2026-11-10 23:41:29')?.toISOString()).toBe('2026-11-10T23:41:29.000Z');
    expect(parseIrisUtc('2026-11-10T23:41:29.5Z')?.toISOString()).toBe('2026-11-10T23:41:29.500Z');
    expect(parseIrisUtc('2026-11-11 00:41:29+01:00')?.toISOString()).toBe('2026-11-10T23:41:29.000Z');
  });

  it('is null for nothing, garbage and the OPC UA null DateTime', () => {
    expect(parseIrisUtc(undefined)).toBeNull();
    expect(parseIrisUtc('')).toBeNull();
    expect(parseIrisUtc('3 phases')).toBeNull();
    expect(parseIrisUtc('1601-01-01 00:00:00.0000000')).toBeNull();
  });
});

describe('localClock / localDateTime', () => {
  it('formats in the browser time zone', () => {
    const d = new Date(2026, 10, 11, 0, 41, 9);
    expect(localClock(d)).toBe('00:41:09');
    expect(localDateTime(d)).toBe('2026-11-11 00:41:09');
  });
});
