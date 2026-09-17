export type PushPlatform = 'macos' | 'ios' | 'watchos';
export type PushEnvironment = 'production' | 'sandbox';
export type SoundPreference = 'default' | 'none';

export interface DeviceToken {
  uid: string;
  token: string;
  platform: PushPlatform;
  environment: PushEnvironment;
  soundPreference: SoundPreference;
}

/**
 * Select one exclusive push target set for a receiver.
 *
 * A live Mac owns delivery while it is present. Once it is absent, mobile
 * devices are preferred, with registered Mac devices as the final fallback.
 */
export function selectPushTokens(tokens: DeviceToken[], hasLiveMac: boolean): DeviceToken[] {
  if (hasLiveMac) return tokens.filter((token) => token.platform === 'macos');

  const mobile = tokens.filter((token) => token.platform === 'ios' || token.platform === 'watchos');
  return mobile.length > 0 ? mobile : tokens.filter((token) => token.platform === 'macos');
}

export function isMobilePlatform(platform: PushPlatform): boolean {
  return platform === 'ios' || platform === 'watchos';
}
