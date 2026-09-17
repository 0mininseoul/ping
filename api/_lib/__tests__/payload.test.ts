import { describe, it, expect } from 'vitest';
import {
  buildInvitationPayload,
  buildMacChatPayload,
  buildMacInvitationPayload,
  buildMacPingPayload,
  buildPingPayload,
} from '../payload';

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

describe('macOS payload builders', () => {
  it('uses the macOS video category and identifier keys without a signed URL', () => {
    const payload = buildMacPingPayload({
      senderName: '박영민',
      messageId: 'msg-1',
      roomId: 'room-1',
      soundPreference: 'none',
    });

    expect(payload.aps.category).toBe('ping.message');
    expect(payload.aps).not.toHaveProperty('sound');
    expect(payload.messageId).toBe('msg-1');
    expect(payload.room_id).toBe('room-1');
    expect(payload).not.toHaveProperty('videoSignedUrl');
  });

  it('identifies macOS chat with type and snake-case IDs', () => {
    const payload = buildMacChatPayload({
      senderName: '박영민',
      body: '안녕하세요',
      roomId: 'room-1',
      chatId: 'chat-1',
      soundPreference: 'default',
    });

    expect(payload.aps).not.toHaveProperty('category');
    expect(payload.type).toBe('chat');
    expect(payload.chat_id).toBe('chat-1');
    expect(payload.room_id).toBe('room-1');
  });

  it('uses invitation category and the notification delegate keys', () => {
    const input = {
      inviteId: 'invite-1',
      roomId: 'room-1',
      fromNickname: '박영민',
      roomName: '우리 방',
      soundPreference: 'default' as const,
    };
    const payload = buildMacInvitationPayload(input);

    expect(payload.aps.category).toBe('ping.invitation');
    expect(payload.inviteId).toBe('invite-1');
    expect(payload.room_id).toBe('room-1');
    expect(payload.from_nickname).toBe('박영민');
    expect(payload.room_name).toBe('우리 방');
  });

  it('keeps mobile video payloads on PING_MESSAGE with the signed URL', () => {
    const payload = buildPingPayload({
      senderName: '박영민',
      messageId: 'msg-1',
      roomId: 'room-1',
      videoSignedUrl: 'https://signed.example/clip.mp4',
      soundPreference: 'none',
    });

    expect(payload.aps.category).toBe('PING_MESSAGE');
    expect(payload.aps.sound).toBe('default');
    expect(payload.videoSignedUrl).toBe('https://signed.example/clip.mp4');
  });

  it('builds a mobile invitation payload with the same delegate identifiers', () => {
    const payload = buildInvitationPayload({
      inviteId: 'invite-1',
      roomId: 'room-1',
      fromNickname: '박영민',
      roomName: '우리 방',
    });

    expect(payload.aps.category).toBe('ping.invitation');
    expect(payload.inviteId).toBe('invite-1');
    expect(payload.room_id).toBe('room-1');
  });
});
