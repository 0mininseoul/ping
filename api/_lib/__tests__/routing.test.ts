import { describe, expect, it } from 'vitest';
import { selectPushTokens, type DeviceToken } from '../routing';

const macToken: DeviceToken = {
  uid: 'receiver-1',
  token: 'mac-token',
  platform: 'macos',
  environment: 'production',
  soundPreference: 'none',
};

const iosToken: DeviceToken = {
  uid: 'receiver-1',
  token: 'ios-token',
  platform: 'ios',
  environment: 'production',
  soundPreference: 'default',
};

const watchToken: DeviceToken = {
  uid: 'receiver-1',
  token: 'watch-token',
  platform: 'watchos',
  environment: 'sandbox',
  soundPreference: 'default',
};

describe('selectPushTokens', () => {
  it('selects only macOS tokens when any Mac presence is live', () => {
    const tokens = selectPushTokens([macToken, iosToken, watchToken], true);
    expect(tokens.map((token) => token.platform)).toEqual(['macos']);
  });

  it('selects only mobile tokens when no Mac is live and mobile tokens exist', () => {
    const tokens = selectPushTokens([macToken, iosToken, watchToken], false);
    expect(tokens.map((token) => token.platform)).toEqual(['ios', 'watchos']);
  });

  it('falls back to macOS tokens when no Mac is live and mobile is absent', () => {
    expect(selectPushTokens([macToken], false)).toEqual([macToken]);
  });

  it('returns no tokens when the receiver has no registered devices', () => {
    expect(selectPushTokens([], false)).toEqual([]);
  });
});
