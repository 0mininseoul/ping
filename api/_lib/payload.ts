export interface PingPayloadInput {
  senderName: string;
  messageId: string;
  roomId: string;
  videoSignedUrl: string;
}

export interface PingPayload {
  aps: {
    alert: { title: string; body: string };
    sound: string;
    'mutable-content': 1;
    category: 'PING_MESSAGE';
  };
  messageId: string;
  roomId: string;
  videoSignedUrl: string;
  senderName: string;
}

export function buildPingPayload(input: PingPayloadInput): PingPayload {
  return {
    aps: {
      // body is intentionally Korean-only for the MVP
      alert: { title: input.senderName, body: 'ping 영상 메시지' },
      sound: 'default',
      'mutable-content': 1,
      category: 'PING_MESSAGE',
    },
    messageId: input.messageId,
    roomId: input.roomId,
    videoSignedUrl: input.videoSignedUrl,
    senderName: input.senderName,
  };
}

export interface ChatPayloadInput {
  senderName: string;
  body: string;
  roomId: string;
  chatId: string;
}

export interface ChatPayload {
  aps: {
    alert: { title: string; body: string };
    sound: string;
    category: 'PING_MESSAGE';
  };
  kind: 'chat';
  roomId: string;
  chatId: string;
  senderName: string;
}

/// Text chat push: no video attachment, shows the message body. Uses the same
/// PING_MESSAGE category so the dictation reply action is available.
export function buildChatPayload(input: ChatPayloadInput): ChatPayload {
  return {
    aps: {
      alert: { title: input.senderName, body: input.body },
      sound: 'default',
      category: 'PING_MESSAGE',
    },
    kind: 'chat',
    roomId: input.roomId,
    chatId: input.chatId,
    senderName: input.senderName,
  };
}
