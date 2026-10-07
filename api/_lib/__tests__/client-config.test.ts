import { describe, it, expect } from 'vitest';
import { publicClientConfig } from '../../client-config';

const url = 'https://qxjtprxvjmaxlbtljcjw.supabase.co';
describe('public client configuration', () => {
  it('returns only the pinned project and public key', () => {
    expect(publicClientConfig({ SUPABASE_URL: url, PING_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test', SUPABASE_SERVICE_ROLE_KEY: 'sb_secret_private' }))
      .toEqual({ url, anonKey: 'sb_publishable_test' });
  });
  it.each(['sb_secret_private', 'eyJlegacy', ''])('refuses non-public credentials: %s', (key) => {
    expect(publicClientConfig({ SUPABASE_URL: url, PING_SUPABASE_PUBLISHABLE_KEY: key })).toBeUndefined();
  });
  it('refuses a different backend', () => {
    expect(publicClientConfig({ SUPABASE_URL: 'https://wrong.supabase.co', PING_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test' })).toBeUndefined();
  });
});
