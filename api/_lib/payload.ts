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
