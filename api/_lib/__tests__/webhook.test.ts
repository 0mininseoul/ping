import { describe, it, expect } from 'vitest';
import { verifyWebhookSecret, parseMessageRecord } from '../webhook';

describe('verifyWebhookSecret', () => {
  it('accepts matching non-empty secret', () => {
    expect(verifyWebhookSecret('s3cret', 's3cret')).toBe(true);
  });
  it('rejects mismatch, missing, or empty expected', () => {
    expect(verifyWebhookSecret('a', 'b')).toBe(false);
    expect(verifyWebhookSecret(undefined, 'b')).toBe(false);
    expect(verifyWebhookSecret('a', '')).toBe(false);
  });
});

describe('parseMessageRecord', () => {
  const good = {
    type: 'INSERT',
    table: 'messages',
    record: {
      id: 'msg-1',
      receiver_uid: 'rcv-1',
      sender_uid: 'snd-1',
      video_id: 'vid-1',
      room_id: 'room-1',
      sender_nickname: '박영민',
    },
  };

  it('parses a valid INSERT on messages', () => {
    expect(parseMessageRecord(good)).toEqual({
      messageId: 'msg-1',
      receiverUid: 'rcv-1',
      senderUid: 'snd-1',
      videoId: 'vid-1',
      roomId: 'room-1',
      senderNickname: '박영민',
    });
  });

  it('defaults sender nickname when absent', () => {
    const r = { ...good, record: { ...good.record, sender_nickname: undefined } };
    expect(parseMessageRecord(r)?.senderNickname).toBe('Ping');
  });

  it('ignores non-INSERT, wrong table, or missing fields', () => {
    expect(parseMessageRecord({ ...good, type: 'UPDATE' })).toBeNull();
    expect(parseMessageRecord({ ...good, table: 'chat_messages' })).toBeNull();
    expect(parseMessageRecord({ ...good, record: { ...good.record, video_id: undefined } })).toBeNull();
    expect(parseMessageRecord(null)).toBeNull();
  });
});
