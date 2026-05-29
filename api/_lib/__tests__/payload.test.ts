import { describe, it, expect } from 'vitest';
import { buildPingPayload } from '../payload';

describe('buildPingPayload', () => {
  const p = buildPingPayload({
    senderName: '박영민',
    messageId: 'msg-1',
    roomId: 'room-1',
    videoSignedUrl: 'https://signed.example/clip.mp4',
  });

  it('sets mutable-content so the NSE can attach the video', () => {
    expect(p.aps['mutable-content']).toBe(1);
  });

  it('sets the PING_MESSAGE category for the reply action', () => {
    expect(p.aps.category).toBe('PING_MESSAGE');
  });

  it('shows the sender name in the alert title', () => {
    expect(p.aps.alert.title).toBe('박영민');
  });

  it('carries custom keys the client needs', () => {
    expect(p.messageId).toBe('msg-1');
    expect(p.roomId).toBe('room-1');
    expect(p.videoSignedUrl).toBe('https://signed.example/clip.mp4');
  });
});
