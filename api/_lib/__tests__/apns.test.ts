import { describe, it, expect } from 'vitest';
import { generateKeyPair, exportPKCS8, decodeJwt, decodeProtectedHeader } from 'jose';
import { makeApnsJwt } from '../apns';

describe('makeApnsJwt', () => {
  it('signs an ES256 token with kid header and team iss', async () => {
    const { privateKey } = await generateKeyPair('ES256');
    const p8 = await exportPKCS8(privateKey);

    const jwt = await makeApnsJwt({ keyId: 'KEY1234567', teamId: 'TEAM999999', p8 });

    const header = decodeProtectedHeader(jwt);
    const claims = decodeJwt(jwt);
    expect(header.alg).toBe('ES256');
    expect(header.kid).toBe('KEY1234567');
    expect(claims.iss).toBe('TEAM999999');
    expect(typeof claims.iat).toBe('number');
  });
});
