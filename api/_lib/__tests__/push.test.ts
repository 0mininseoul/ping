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
  deleteError?: { message: string } | null;
  desktopPresence?: PresenceRow[];
}

interface DeleteFilter {
  column: string;
  value: unknown;
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
  tokens: Array<{ token: string; environment: string; platform?: 'macos' | 'ios' | 'watchos'; uid?: string }>,
  opts: FakeOptions = {}
) {
  const deleted: string[][] = [];
  const deleteFilters: DeleteFilter[][] = [];
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
          const filters: DeleteFilter[] = [];
          const builder = {
            eq(column: string, value: unknown) {
              filters.push({ column, value });
              return builder;
            },
            in(column: string, values: string[]) {
              filters.push({ column, value: values });
              return builder;
            },
            then(resolve: (value: { data: null; error: { message: string } | null }) => unknown) {
              deleteFilters.push(filters);
              const tokenFilter = filters.find((filter) => filter.column === 'token');
              const tokenValue = tokenFilter?.value;
              deleted.push(Array.isArray(tokenValue) ? tokenValue : [String(tokenValue)]);
              return Promise.resolve({ data: null, error: opts.deleteError ?? null }).then(resolve);
            },
          };
          return builder;
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
  return { supabase, deleted, deleteFilters };
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
  tokens: Array<{ token: string; environment: string; platform?: 'macos' | 'ios' | 'watchos'; uid?: string }> = [{ token: 't1', environment: 'production' }],
  opts: FakeOptions = {}
): {
  d: PushDeps;
  send: ReturnType<typeof vi.fn>;
  deleted: string[][];
  deleteFilters: DeleteFilter[][];
} {
  const { supabase, deleted, deleteFilters } = fakeSupabase(tokens, opts);
  const send = vi.fn(async () => ({ status: 200, body: '' }));
  const d: PushDeps = {
    supabase: supabase as unknown as PushDeps['supabase'],
    makeJwt: async () => 'jwt-abc',
    send,
    bundleIds: {
      macos: 'com.example.app',
      ios: 'com.example.app',
      watchos: 'com.example.app',
    },
    bundleId: 'com.example.app',
    expectedSecret: 's3cret',
    ...overrides,
  };
  return { d, send, deleted, deleteFilters };
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

  it('scopes 410 cleanup to the failed token platform and uid', async () => {
    const send = vi.fn(async (input: { bundleId: string }) => ({
      status: input.bundleId === 'com.example.ios' ? 410 : 200,
      body: '',
    }));
    const { d, deleteFilters } = deps({ send }, [
      { uid: 'rcv-1', token: 'shared-token', environment: 'production', platform: 'ios' },
      { uid: 'rcv-1', token: 'shared-token', environment: 'production', platform: 'watchos' },
    ]);
    d.bundleIds = {
      macos: 'com.example.mac',
      ios: 'com.example.ios',
      watchos: 'com.example.watch',
    };

    const out = await handlePush(insertBody, 's3cret', d);

    expect(out.body).toEqual({ sent: 1, removed: 1 });
    expect(send).toHaveBeenCalledTimes(2);
    expect(deleteFilters).toEqual([[
      { column: 'token', value: 'shared-token' },
      { column: 'platform', value: 'ios' },
      { column: 'uid', value: 'rcv-1' },
    ]]);
  });

  it('returns a retryable error for APNs failures while reporting mixed delivery safely', async () => {
    const send = vi.fn(async (i: { token: string }) => ({
      status: i.token === 't2' ? 503 : 200,
      body: i.token === 't2' ? 'provider response must not be logged' : '',
    }));
    const { d } = deps({ send }, [
      { token: 't1', environment: 'production' },
      { token: 't2', environment: 'production' },
    ]);

    const out = await handlePush(insertBody, 's3cret', d);

    // One attempt per token lets healthy devices receive this event now. The
    // 500 asks the webhook to retry the event; collapseId remains the event id
    // because this endpoint has no durable per-token delivery ledger.
    expect(out).toEqual({
      code: 500,
      body: {
        error: 'apns_error',
        detail: 'APNs returned failure status 503',
        sent: 1,
        removed: 0,
      },
    });
    expect(send).toHaveBeenCalledTimes(2);
  });

  it('surfaces a token cleanup error without counting 410 tokens as removed', async () => {
    const send = vi.fn(async () => ({ status: 410, body: '' }));
    const { d, deleted } = deps(
      { send },
      [{ token: 't1', environment: 'production' }],
      { deleteError: { message: 'cleanup unavailable' } }
    );

    const out = await handlePush(insertBody, 's3cret', d);

    expect(out).toEqual({
      code: 500,
      body: {
        error: 'db_error',
        detail: 'cleanup unavailable',
        sent: 0,
        removed: 0,
      },
    });
    expect(deleted).toEqual([['t1']]);
  });

  it('logs only safe aggregate event and APNs status data', async () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => undefined);
    const send = vi.fn(async () => ({ status: 200, body: 'provider response must not be logged' }));
    const { d } = deps(
      { send },
      [{ token: 'token-secret-suffix', environment: 'production' }]
    );

    try {
      await handlePush(insertBody, 's3cret', d);
      const output = log.mock.calls.map(([line]) => String(line)).join('\n');
      expect(output).toMatch(/event=video/);
      expect(output).toMatch(/status=200/);
      expect(output).not.toContain('rcv-1');
      expect(output).not.toContain('snd-1');
      expect(output).not.toContain('room-1');
      expect(output).not.toContain('secret-suffix');
      expect(output).not.toContain('provider response must not be logged');
    } finally {
      log.mockRestore();
    }
  });

  it('returns sent:0 when receiver has no tokens', async () => {
    const { d, send } = deps({}, []);
    const out = await handlePush(insertBody, 's3cret', d);
    expect(out.code).toBe(200);
    expect(out.body).toEqual({ sent: 0, removed: 0 });
    expect(send).not.toHaveBeenCalled();
  });

  it('routes video push to the macOS token while the receiver has fresh desktop presence', async () => {
    const { d, send } = deps(
      {},
      [{ token: 't1', environment: 'production', platform: 'macos' }],
      { desktopPresence: [{ uid: 'rcv-1', updated_at: new Date().toISOString() }] }
    );
    const out = await handlePush(insertBody, 's3cret', d);
    expect(out.code).toBe(200);
    expect(out.body).toEqual({ sent: 1, removed: 0 });
    expect(send).toHaveBeenCalledTimes(1);
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
  tokens: Array<{ token: string; environment: string; platform?: 'macos' | 'ios' | 'watchos' }>,
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
  tokens: Array<{ token: string; environment: string; platform?: 'macos' | 'ios' | 'watchos' }>,
  desktopPresence: PresenceRow[] = []
) {
  const { supabase, deleted } = chatFakeSupabase(members, tokens, desktopPresence);
  const send = vi.fn(async () => ({ status: 200, body: '' }));
  const d: PushDeps = {
    supabase: supabase as unknown as PushDeps['supabase'],
    makeJwt: async () => 'jwt-abc',
    send,
    bundleIds: {
      macos: 'com.example.app',
      ios: 'com.example.app',
      watchos: 'com.example.app',
    },
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

  it('routes chat push to the macOS token for members with fresh desktop presence', async () => {
    const { d, send } = chatDeps(
      [{ user_id: 'rcv-1' }],
      [{ token: 't1', environment: 'production', platform: 'macos' }],
      [{ uid: 'rcv-1', updated_at: new Date().toISOString() }]
    );
    const out = await handlePush(chatBody, 's3cret', d);
    expect(out.code).toBe(200);
    expect(out.body).toEqual({ sent: 1, removed: 0, kind: 'chat' });
    expect(send).toHaveBeenCalledTimes(1);
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

  it('does not log chat room, sender, or token identifiers', async () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => undefined);
    const { d } = chatDeps(
      [{ user_id: 'receiver-secret' }],
      [{ token: 'chat-token-secret-suffix', environment: 'production' }]
    );

    try {
      await handlePush(chatBody, 's3cret', d);
      const output = log.mock.calls.map(([line]) => String(line)).join('\n');
      expect(output).toMatch(/event=chat/);
      expect(output).toMatch(/status=200/);
      expect(output).not.toContain('room-1');
      expect(output).not.toContain('snd-1');
      expect(output).not.toContain('receiver-secret');
      expect(output).not.toContain('secret-suffix');
    } finally {
      log.mockRestore();
    }
  });
});

// --- Platform-aware routing and invitation pushes ---

interface ModernTokenRow {
  uid: string;
  token: string;
  platform: 'macos' | 'ios' | 'watchos';
  environment: 'production' | 'sandbox';
  sound_preference: 'default' | 'none';
}

interface ModernOptions {
  tokens: ModernTokenRow[];
  desktopPresence?: Array<PresenceRow & { platform?: 'macos' | 'windows' }>;
  members?: Array<{ user_id: string; room_id?: string }>;
  signedUrl?: string;
}

function modernSupabase(options: ModernOptions) {
  const deleted: string[][] = [];
  let signedUrlCalls = 0;

  function rowsFor(table: string): Array<Record<string, unknown>> {
    if (table === 'device_tokens') return options.tokens as unknown as Array<Record<string, unknown>>;
    if (table === 'desktop_presence') return (options.desktopPresence ?? []) as unknown as Array<Record<string, unknown>>;
    if (table === 'room_members') return (options.members ?? []) as unknown as Array<Record<string, unknown>>;
    return [];
  }

  function table(tableName: string) {
    return {
      select() {
        let result = rowsFor(tableName);
        const builder = {
          eq(column: string, value: unknown) {
            result = result.filter((row) => row[column] === value);
            return builder;
          },
          neq(column: string, value: unknown) {
            result = result.filter((row) => row[column] !== value);
            return builder;
          },
          in(column: string, values: unknown[]) {
            result = result.filter((row) => values.includes(row[column]));
            return builder;
          },
          gte(column: string, value: string) {
            result = result.filter((row) => String(row[column]) >= value);
            return builder;
          },
          is(column: string, value: null) {
            result = result.filter((row) => (row[column] ?? null) === value);
            return builder;
          },
          then(
            resolve: (value: { data: Array<Record<string, unknown>>; error: null }) => unknown,
            reject?: (reason: unknown) => unknown
          ) {
            return Promise.resolve({ data: result, error: null }).then(resolve, reject);
          },
        };
        return builder;
      },
      delete() {
        return {
          in: async (_column: string, values: string[]) => {
            deleted.push(values);
            return { data: null, error: null };
          },
        };
      },
    };
  }

  const supabase = {
    from(tableName: string) {
      return table(tableName);
    },
    storage: {
      from() {
        return {
          createSignedUrl: async () => {
            signedUrlCalls += 1;
            return {
              data: { signedUrl: options.signedUrl ?? 'https://signed.example/clip.mp4' },
              error: null,
            };
          },
        };
      },
    },
  };
  return { supabase, deleted, get signedUrlCalls() { return signedUrlCalls; } };
}

function modernDeps(options: ModernOptions) {
  const fake = modernSupabase(options);
  const send = vi.fn(async () => ({ status: 200, body: '' }));
  const d: PushDeps = {
    supabase: fake.supabase as unknown as PushDeps['supabase'],
    makeJwt: async () => 'jwt-abc',
    send,
    bundleIds: {
      macos: 'com.example.mac',
      ios: 'com.example.ios',
      watchos: 'com.example.watch',
    },
    expectedSecret: 's3cret',
  };
  return { d, send, fake };
}

const modernVideoBody = {
  type: 'INSERT',
  table: 'messages',
  record: {
    id: 'msg-modern',
    receiver_uid: 'receiver-1',
    sender_uid: 'sender-1',
    video_id: 'video-modern',
    room_id: 'room-modern',
    sender_nickname: '보낸 사람',
  },
};

const modernTokenRows: ModernTokenRow[] = [
  {
    uid: 'receiver-1',
    token: 'mac-modern',
    platform: 'macos',
    environment: 'production',
    sound_preference: 'default',
  },
  {
    uid: 'receiver-1',
    token: 'ios-modern',
    platform: 'ios',
    environment: 'production',
    sound_preference: 'default',
  },
  {
    uid: 'receiver-1',
    token: 'watch-modern',
    platform: 'watchos',
    environment: 'sandbox',
    sound_preference: 'default',
  },
];

describe('handlePush (platform-aware routing)', () => {
  it('routes a live Mac receiver exclusively to macOS tokens and skips signed URL creation', async () => {
    const { d, send, fake } = modernDeps({
      tokens: modernTokenRows,
      desktopPresence: [{ uid: 'receiver-1', updated_at: new Date().toISOString(), platform: 'macos' }],
    });

    const out = await handlePush(modernVideoBody, 's3cret', d);

    expect(out.body).toEqual({ sent: 1, removed: 0 });
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0][0].token).toBe('mac-modern');
    expect(send.mock.calls[0][0].bundleId).toBe('com.example.mac');
    expect(send.mock.calls[0][0].payload.aps.category).toBe('ping.message');
    expect(send.mock.calls[0][0].payload).not.toHaveProperty('videoSignedUrl');
    expect(fake.signedUrlCalls).toBe(0);
  });

  it('routes an absent Mac receiver exclusively to mobile tokens and keeps the signed URL', async () => {
    const { d, send, fake } = modernDeps({ tokens: modernTokenRows });

    await handlePush(modernVideoBody, 's3cret', d);

    expect(send).toHaveBeenCalledTimes(2);
    expect(send.mock.calls.map((call) => call[0].token)).toEqual(['ios-modern', 'watch-modern']);
    expect(send.mock.calls.map((call) => call[0].bundleId)).toEqual([
      'com.example.ios',
      'com.example.watch',
    ]);
    expect(send.mock.calls.every((call) => call[0].payload.aps.category === 'PING_MESSAGE')).toBe(true);
    expect(send.mock.calls.every((call) => call[0].payload.videoSignedUrl === 'https://signed.example/clip.mp4')).toBe(true);
    expect(fake.signedUrlCalls).toBe(1);
  });

  it('falls back to macOS tokens when the receiver has no live Mac and no mobile token', async () => {
    const { d, send, fake } = modernDeps({ tokens: [modernTokenRows[0]] });

    await handlePush(modernVideoBody, 's3cret', d);

    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0][0].token).toBe('mac-modern');
    expect(send.mock.calls[0][0].payload).not.toHaveProperty('videoSignedUrl');
    expect(fake.signedUrlCalls).toBe(0);
  });

  it('does not treat an ended Mac presence row as live', async () => {
    const now = new Date().toISOString();
    const { d, send } = modernDeps({
      tokens: modernTokenRows,
      desktopPresence: [{ uid: 'receiver-1', updated_at: now, ended_at: now, platform: 'macos' }],
    });

    await handlePush(modernVideoBody, 's3cret', d);

    expect(send.mock.calls.map((call) => call[0].token)).toEqual(['ios-modern', 'watch-modern']);
  });

  it('routes each chat recipient independently by UID', async () => {
    const tokens: ModernTokenRow[] = [
      { ...modernTokenRows[0], uid: 'receiver-1', token: 'mac-r1' },
      { ...modernTokenRows[1], uid: 'receiver-1', token: 'ios-r1' },
      { ...modernTokenRows[1], uid: 'receiver-2', token: 'ios-r2' },
      { ...modernTokenRows[2], uid: 'receiver-2', token: 'watch-r2' },
    ];
    const { d, send } = modernDeps({
      tokens,
      members: [
        { user_id: 'receiver-1', room_id: 'room-1' },
        { user_id: 'receiver-2', room_id: 'room-1' },
      ],
      desktopPresence: [{ uid: 'receiver-1', updated_at: new Date().toISOString(), platform: 'macos' }],
    });

    await handlePush(chatBody, 's3cret', d);

    expect(send.mock.calls.map((call) => call[0].token)).toEqual(['mac-r1', 'ios-r2', 'watch-r2']);
    expect(send.mock.calls[0][0].payload.type).toBe('chat');
    expect(send.mock.calls[0][0].payload.chat_id).toBe('chat-1');
    expect(send.mock.calls[1][0].payload.kind).toBe('chat');
  });

  it('pushes invitation inserts to the record recipient with macOS keys', async () => {
    const invitation = {
      type: 'INSERT',
      table: 'invitations',
      record: {
        id: 'invite-modern',
        to_uid: 'receiver-1',
        room_id: 'room-modern',
        from_nickname: '초대한 사람',
        room_name: 'Ping 룸',
      },
    };
    const { d, send } = modernDeps({ tokens: [modernTokenRows[0]] });

    const out = await handlePush(invitation, 's3cret', d);

    expect(out.body).toEqual({ sent: 1, removed: 0, kind: 'invitation' });
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0][0].collapseId).toBe('invite-modern');
    expect(send.mock.calls[0][0].payload).toMatchObject({
      inviteId: 'invite-modern',
      room_id: 'room-modern',
      from_nickname: '초대한 사람',
      room_name: 'Ping 룸',
    });
    expect(send.mock.calls[0][0].payload.aps.category).toBe('ping.invitation');
  });

  it('omits sound for a selected macOS token with sound preference none', async () => {
    const { d, send } = modernDeps({
      tokens: [{ ...modernTokenRows[0], sound_preference: 'none' }],
      desktopPresence: [{ uid: 'receiver-1', updated_at: new Date().toISOString(), platform: 'macos' }],
    });

    await handlePush(modernVideoBody, 's3cret', d);

    expect(send.mock.calls[0][0].payload.aps).not.toHaveProperty('sound');
  });

  it('falls back to the iOS topic when no watchOS topic is configured', async () => {
    const { d, send } = modernDeps({
      tokens: [modernTokenRows[2]],
    });
    d.bundleIds = { macos: 'com.example.mac', ios: 'com.example.ios' };

    await handlePush(modernVideoBody, 's3cret', d);

    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0][0].bundleId).toBe('com.example.ios');
  });

  it('returns a configuration error instead of using a legacy topic when the macOS topic is missing', async () => {
    const { d, send } = modernDeps({ tokens: [modernTokenRows[0]] });
    d.bundleIds = { ios: 'com.example.ios', watchos: 'com.example.watch' };
    d.bundleId = 'com.example.legacy';

    const out = await handlePush(modernVideoBody, 's3cret', d);

    expect(out).toEqual({
      code: 500,
      body: { error: 'config_error', detail: 'APNS_MACOS_BUNDLE_ID is required for macOS push' },
    });
    expect(send).not.toHaveBeenCalled();
  });

  it('returns a configuration error instead of using a legacy topic when the macOS topic is blank', async () => {
    const { d, send } = modernDeps({ tokens: [modernTokenRows[0]] });
    d.bundleIds = { macos: '   ', ios: 'com.example.ios', watchos: 'com.example.watch' };
    d.bundleId = 'com.example.legacy';

    const out = await handlePush(modernVideoBody, 's3cret', d);

    expect(out).toEqual({
      code: 500,
      body: { error: 'config_error', detail: 'APNS_MACOS_BUNDLE_ID is required for macOS push' },
    });
    expect(send).not.toHaveBeenCalled();
  });

  it('trims mobile topics and ignores whitespace before using the safe legacy fallback', async () => {
    const { d, send } = modernDeps({
      tokens: [modernTokenRows[1], modernTokenRows[2]],
    });
    d.bundleIds = { macos: ' com.example.mac ', ios: '   ', watchos: '\t' };
    d.bundleId = ' com.example.legacy ';

    const out = await handlePush(modernVideoBody, 's3cret', d);

    expect(out.body).toEqual({ sent: 2, removed: 0 });
    expect(send.mock.calls.map((call) => call[0].bundleId)).toEqual([
      'com.example.legacy',
      'com.example.legacy',
    ]);
  });

  it('trims the iOS topic before using it as the watchOS fallback', async () => {
    const { d, send } = modernDeps({
      tokens: [modernTokenRows[1], modernTokenRows[2]],
    });
    d.bundleIds = { macos: 'com.example.mac', ios: ' com.example.ios ', watchos: '  ' };
    d.bundleId = 'com.example.legacy';

    await handlePush(modernVideoBody, 's3cret', d);

    expect(send.mock.calls.map((call) => call[0].bundleId)).toEqual([
      'com.example.ios',
      'com.example.ios',
    ]);
  });

  it('fails before APNs when mobile topics and all fallbacks are empty', async () => {
    const { d, send } = modernDeps({
      tokens: [modernTokenRows[1]],
    });
    d.bundleIds = { macos: 'com.example.mac', ios: '   ', watchos: '\n' };
    d.bundleId = '  ';

    const out = await handlePush(modernVideoBody, 's3cret', d);

    expect(out).toEqual({
      code: 500,
      body: { error: 'config_error', detail: 'APNS_IOS_BUNDLE_ID is required for ios push' },
    });
    expect(send).not.toHaveBeenCalled();
  });
});
