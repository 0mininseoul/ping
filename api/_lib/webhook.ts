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

export interface ChatRecord {
  chatId: string;
  roomId: string;
  senderUid: string;
  senderNickname: string;
  body: string;
}

// Parse a `chat_messages` INSERT (text chat/reply). Chat is room-scoped (no
// receiver_uid), so the handler pushes to the room's other members.
export function parseChatRecord(body: unknown): ChatRecord | null {
  if (!body || typeof body !== 'object') return null;
  const b = body as Record<string, unknown>;
  if (b.type !== 'INSERT' || b.table !== 'chat_messages' || !b.record) return null;
  const r = b.record as Record<string, unknown>;
  if (!r.id || !r.room_id || !r.sender_uid || !r.body) return null;
  return {
    chatId: String(r.id),
    roomId: String(r.room_id),
    senderUid: String(r.sender_uid),
    senderNickname: r.sender_nickname ? String(r.sender_nickname) : 'Ping',
    body: String(r.body),
  };
}
