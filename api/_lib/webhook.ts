export function verifyWebhookSecret(provided: string | undefined, expected: string): boolean {
  return Boolean(provided) && Boolean(expected) && provided === expected;
}

export interface MessageRecord {
  messageId: string;
  receiverUid: string;
  senderUid: string;
  videoId: string;
  roomId: string;
  senderNickname: string;
}

export function parseMessageRecord(body: unknown): MessageRecord | null {
  if (!body || typeof body !== 'object') return null;
  const b = body as Record<string, unknown>;
  if (b.type !== 'INSERT' || b.table !== 'messages' || !b.record) return null;
  const r = b.record as Record<string, unknown>;
  if (!r.id || !r.receiver_uid || !r.sender_uid || !r.video_id || !r.room_id) return null;
  return {
    messageId: String(r.id),
    receiverUid: String(r.receiver_uid),
    senderUid: String(r.sender_uid),
    videoId: String(r.video_id),
    roomId: String(r.room_id),
    senderNickname: r.sender_nickname ? String(r.sender_nickname) : 'Ping',
  };
}
