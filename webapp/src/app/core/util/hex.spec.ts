import { bytesToHex } from './hex';

describe('bytesToHex', () => {
  it('writes uppercase, zero-padded hex', () => {
    expect(bytesToHex(new Uint8Array([0, 255, 16]).buffer)).toBe('00FF10');
  });
});
