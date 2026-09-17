import type { SoundPreference } from './routing';

export interface PingPayloadInput {
  senderName: string;
  messageId: string;
  roomId: string;
  videoSignedUrl: string;
  /** Mobile devices always use their existing default sound contract. */
  soundPreference?: SoundPreference;
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

export interface MacPingPayloadInput {
  senderName: string;
  messageId: string;
  roomId: string;
  soundPreference?: SoundPreference;
}

export interface MacPingPayload {
  aps: {
    alert: { title: string; body: string };
    sound?: 'default';
    category: 'ping.message';
  };
  messageId: string;
  room_id: string;
  senderName: string;
}

export function buildMacPingPayload(input: MacPingPayloadInput): MacPingPayload {
  return {
    aps: {
      alert: { title: input.senderName, body: 'ping 영상 메시지' },
      ...(input.soundPreference === 'none' ? {} : { sound: 'default' as const }),
      category: 'ping.message',
    },
    messageId: input.messageId,
    room_id: input.roomId,
    senderName: input.senderName,
  };
}

export interface ChatPayloadInput {
  senderName: string;
  body: string;
  roomId: string;
  chatId: string;
  /** Mobile devices always use their existing default sound contract. */
  soundPreference?: SoundPreference;
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

export interface MacChatPayloadInput {
  senderName: string;
  body: string;
  roomId: string;
  chatId: string;
  soundPreference?: SoundPreference;
}

export interface MacChatPayload {
  aps: {
    alert: { title: string; body: string };
    sound?: 'default';
  };
  type: 'chat';
  room_id: string;
  chat_id: string;
  senderName: string;
}

export function buildMacChatPayload(input: MacChatPayloadInput): MacChatPayload {
  return {
    aps: {
      alert: { title: input.senderName, body: boundedPreview(input.body) },
      ...(input.soundPreference === 'none' ? {} : { sound: 'default' as const }),
    },
    type: 'chat',
    room_id: input.roomId,
    chat_id: input.chatId,
    senderName: input.senderName,
  };
}

export interface InvitationPayloadInput {
  inviteId: string;
  roomId: string;
  fromNickname: string;
  roomName: string;
  soundPreference?: SoundPreference;
}

export interface InvitationPayload {
  aps: {
    alert: { title: string; body: string };
    sound: 'default';
    category: 'ping.invitation';
  };
  inviteId: string;
  room_id: string;
  from_nickname: string;
  room_name: string;
}

/** Invitation payload for iOS/watchOS. Keep the established default sound. */
export function buildInvitationPayload(input: InvitationPayloadInput): InvitationPayload {
  return {
    aps: {
      alert: {
        title: `${input.fromNickname}님이 룸에 초대했습니다`,
        body: input.roomName,
      },
      sound: 'default',
      category: 'ping.invitation',
    },
    inviteId: input.inviteId,
    room_id: input.roomId,
    from_nickname: input.fromNickname,
    room_name: input.roomName,
  };
}

export interface MacInvitationPayload {
  aps: {
    alert: { title: string; body: string };
    sound?: 'default';
    category: 'ping.invitation';
  };
  inviteId: string;
  room_id: string;
  from_nickname: string;
  room_name: string;
}

export function buildMacInvitationPayload(input: InvitationPayloadInput): MacInvitationPayload {
  const payload = buildInvitationPayload(input);
  return {
    aps: {
      alert: payload.aps.alert,
      ...(input.soundPreference === 'none' ? {} : { sound: 'default' as const }),
      category: 'ping.invitation',
    },
    inviteId: payload.inviteId,
    room_id: payload.room_id,
    from_nickname: payload.from_nickname,
    room_name: payload.room_name,
  };
}

function boundedPreview(value: string): string {
  return value.length > 200 ? `${value.slice(0, 200)}…` : value;
}
