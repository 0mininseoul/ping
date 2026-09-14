import { describe, it, expect, vi } from 'vitest';
import { handlePush, type PushDeps } from '../../push';

interface PresenceRow {
  uid: string;
  updated_at: string;
  /// null이면 살아 있는 세션, 값이 있으면 Ping을 끈 기기다.
  ended_at?: string | null;
}

interface FakeOptions {
  tokenQueryError?: { message: string } | null;
  signedUrlError?: { message: string } | null;
  signedUrl?: string | null;
  desktopPresence?: PresenceRow[];
}

/// PostgREST 체인처럼 필터를 쌓았다가 await 시점에 적용한다. 필터를 정직하게
/// 흉내 내야 쿼리에서 조건이 빠졌을 때 테스트가 조용히 통과하지 않는다.
function presenceTable(rows: PresenceRow[]) {
  return {
    select() {
      let result = rows;
      const builder = {
        in(_col: string, uids: string[]) {
          result = result.filter((row) => uids.includes(row.uid));
          return builder;
        },
        gte(_col: string, cutoff: string) {
          result = result.filter((row) => row.updated_at >= cutoff);
          return builder;
        },
        is(column: string, value: null) {
          result = result.filter(
            (row) => ((row as Record<string, unknown>)[column] ?? null) === value
          );
          return builder;
        },
        then(resolve: (value: { data: PresenceRow[]; error: null }) => unknown) {
          return Promise.resolve({ data: result, error: null }).then(resolve);
        },
      };
      return builder;
    },
  };
}

function fakeSupabase(
  tokens: Array<{ token: string; environment: string }>,
  opts: FakeOptions = {}
) {
  const deleted: string[][] = [];
  const supabase = {
    from(table: string) {
      if (table === 'desktop_presence') {
        return presenceTable(opts.desktopPresence ?? []);
      }
      return {
        select() {
          return {
            eq: async () => {
              if (opts.tokenQueryError) {
                return { data: null, error: opts.tokenQueryError };
              }
              return { data: tokens, error: null };
            },
          };
        },
        delete() {
          return {
            in: async (_col: string, vals: string[]) => {
              deleted.push(vals);
              return { data: null, error: null };
            },
          };
        },
      };
    },
    storage: {
      from() {
        return {
          createSignedUrl: async () => {
            if (opts.signedUrlError) {
              return { data: null, error: opts.signedUrlError };
            }
            const url = opts.signedUrl !== undefined ? opts.signedUrl : 'https://signed.example/clip.mp4';
            return {
              data: url ? { signedUrl: url } : null,
              error: null,
            };
          },
        };
      },
    },
  };
  return { supabase, deleted };
}

const insertBody = {
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

function deps(
  overrides: Partial<PushDeps>,
  tokens = [{ token: 't1', environment: 'production' }],
  opts: FakeOptions = {}
): {
  d: PushDeps;
  send: ReturnType<typeof vi.fn>;
  deleted: string[][];
} {
  const { supabase, deleted } = fakeSupabase(tokens, opts);
  const send = vi.fn(async () => ({ status: 200, body: '' }));
  const d: PushDeps = {
    supabase: supabase as unknown as PushDeps['supabase'],
    makeJwt: async () => 'jwt-abc',
    send,
    bundleId: 'com.example.app',
    expectedSecret: 's3cret',
    ...overrides,
  };
  return { d, send, deleted };
}

describe('handlePush', () => {
  it('rejects a bad secret with 401', async () => {
    const { d } = deps({});
    const out = await handlePush(insertBody, 'wrong', d);
    expect(out.code).toBe(401);
  });

  it('ignores non-message events with 200', async () => {
    const { d, send } = deps({});
    const out = await handlePush({ type: 'UPDATE', table: 'messages', record: {} }, 's3cret', d);
    expect(out.code).toBe(200);
    expect(send).not.toHaveBeenCalled();
  });

  it('sends one push per token with a signed url payload', async () => {
    const { d, send } = deps({}, [
      { token: 't1', environment: 'production' },
      { token: 't2', environment: 'sandbox' },
    ]);
    const out = await handlePush(insertBody, 's3cret', d);
    expect(send).toHaveBeenCalledTimes(2);
    const firstArg = send.mock.calls[0][0];
    expect(firstArg.payload.videoSignedUrl).toBe('https://signed.example/clip.mp4');
    expect(firstArg.collapseId).toBe('msg-1');
    expect(out.body).toEqual({ sent: 2, removed: 0 });
  });

  it('prunes tokens that APNs reports as 410 Unregistered', async () => {
    const send = vi.fn(async (i: { token: string }) => ({
      status: i.token === 't2' ? 410 : 200,
      body: '',
    }));
    const { d, deleted } = deps({ send }, [
      { token: 't1', environment: 'production' },
      { token: 't2', environment: 'production' },
    ]);
    const out = await handlePush(insertBody, 's3cret', d);
    expect(out.body).toEqual({ sent: 1, removed: 1 });
    expect(deleted).toEqual([['t2']]);
  });

  it('returns sent:0 when receiver has no tokens', async () => {
    const { d, send } = deps({}, []);
    const out = await handlePush(insertBody, 's3cret', d);
    expect(out.code).toBe(200);
    expect(out.body).toEqual({ sent: 0, removed: 0 });
    expect(send).not.toHaveBeenCalled();
  });

  it('suppresses video push while the receiver has fresh desktop presence', async () => {
    const { d, send } = deps(
      {},
      [{ token: 't1', environment: 'production' }],
      { desktopPresence: [{ uid: 'rcv-1', updated_at: new Date().toISOString() }] }
    );
    const out = await handlePush(insertBody, 's3cret', d);
    expect(out.code).toBe(200);
    expect(out.body).toEqual({ sent: 0, removed: 0, suppressed: 1 });
    expect(send).not.toHaveBeenCalled();
  });

  it('still pushes a video ping once the desktop session has ended', async () => {
    const now = new Date().toISOString();
    const { d, send } = deps(
      {},
      [{ token: 't1', environment: 'production' }],
      { desktopPresence: [{ uid: 'rcv-1', updated_at: now, ended_at: now }] }
    );
    const out = await handlePush(insertBody, 's3cret', d);
    expect(send).toHaveBeenCalledTimes(1);
    expect(out.body).toEqual({ sent: 1, removed: 0 });
  });

  it('returns 500 when the device_tokens query errors', async () => {
    const { d, send } = deps(
      {},
      [],
      { tokenQueryError: { message: 'db down' } }
    );
    const out = await handlePush(insertBody, 's3cret', d);
    expect(out.code).toBe(500);
    expect(send).not.toHaveBeenCalled();
  });

  it('returns 500 when the signed URL cannot be created', async () => {
    const { d, send } = deps(
      {},
      [{ token: 't1', environment: 'production' }],
      { signedUrlError: { message: 'not found' } }
    );
    const out = await handlePush(insertBody, 's3cret', d);
    expect(out.code).toBe(500);
    expect(send).not.toHaveBeenCalled();
  });
});

// --- Text chat push (room-scoped) ---

function chatFakeSupabase(
  members: Array<{ user_id: string }>,
  tokens: Array<{ token: string; environment: string }>,
  desktopPresence: PresenceRow[] = []
) {
  const deleted: string[][] = [];
  const supabase = {
    from(table: string) {
      if (table === 'room_members') {
        return {
          select() {
            return {
              eq() {
                return { neq: async () => ({ data: members, error: null }) };
              },
            };
          },
        };
      }
      if (table === 'desktop_presence') {
        return presenceTable(desktopPresence);
      }
      // device_tokens
      return {
        select() {
          return { in: async () => ({ data: tokens, error: null }) };
        },
        delete() {
          return {
            in: async (_col: string, vals: string[]) => {
              deleted.push(vals);
              return { data: null, error: null };
            },
          };
        },
      };
    },
  };
  return { supabase, deleted };
}

const chatBody = {
  type: 'INSERT',
  table: 'chat_messages',
  record: {
    id: 'chat-1',
    room_id: 'room-1',
    sender_uid: 'snd-1',
    sender_nickname: '박영민',
    body: '안녕하세요',
  },
};

function chatDeps(
  members: Array<{ user_id: string }>,
  tokens: Array<{ token: string; environment: string }>,
  desktopPresence: PresenceRow[] = []
) {
  const { supabase, deleted } = chatFakeSupabase(members, tokens, desktopPresence);
  const send = vi.fn(async () => ({ status: 200, body: '' }));
  const d: PushDeps = {
    supabase: supabase as unknown as PushDeps['supabase'],
    makeJwt: async () => 'jwt-abc',
    send,
    bundleId: 'com.example.app',
    expectedSecret: 's3cret',
  };
  return { d, send, deleted };
}

describe('handlePush (chat)', () => {
  it("pushes a chat to the room's other members with the body text", async () => {
    const { d, send } = chatDeps(
      [{ user_id: 'rcv-1' }],
      [{ token: 't1', environment: 'production' }]
    );
    const out = await handlePush(chatBody, 's3cret', d);
    expect(send).toHaveBeenCalledTimes(1);
    const arg = send.mock.calls[0][0];
    expect(arg.payload.kind).toBe('chat');
    expect(arg.payload.aps.alert.body).toBe('안녕하세요');
    expect(arg.collapseId).toBe('chat-1');
    expect(out.body).toEqual({ sent: 1, removed: 0, kind: 'chat' });
  });

  it('suppresses chat push for members with fresh desktop presence', async () => {
    const { d, send } = chatDeps(
      [{ user_id: 'rcv-1' }],
      [{ token: 't1', environment: 'production' }],
      [{ uid: 'rcv-1', updated_at: new Date().toISOString() }]
    );
    const out = await handlePush(chatBody, 's3cret', d);
    expect(out.code).toBe(200);
    expect(out.body).toEqual({ sent: 0, removed: 0, kind: 'chat', suppressed: 1 });
    expect(send).not.toHaveBeenCalled();
  });

  /// 종료한 데스크톱 세션이 계속 "켜져 있음"으로 읽히면, Ping을 끈 뒤에도 마지막
  /// 하트비트가 만료될 때까지(최대 45초) 휴대폰 알림이 막힌다.
  it('still pushes chat once the desktop session has ended', async () => {
    const now = new Date().toISOString();
    const { d, send } = chatDeps(
      [{ user_id: 'rcv-1' }],
      [{ token: 't1', environment: 'production' }],
      [{ uid: 'rcv-1', updated_at: now, ended_at: now }]
    );
    const out = await handlePush(chatBody, 's3cret', d);
    expect(send).toHaveBeenCalledTimes(1);
    expect(out.body).toEqual({ sent: 1, removed: 0, kind: 'chat' });
  });

  it('returns sent:0 when the room has no other members', async () => {
    const { d, send } = chatDeps([], []);
    const out = await handlePush(chatBody, 's3cret', d);
    expect(out.code).toBe(200);
    expect(out.body).toEqual({ sent: 0, removed: 0 });
    expect(send).not.toHaveBeenCalled();
  });
});
