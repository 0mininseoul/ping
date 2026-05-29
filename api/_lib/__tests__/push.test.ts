import { describe, it, expect, vi } from 'vitest';
import { handlePush, type PushDeps } from '../../push';

function fakeSupabase(tokens: Array<{ token: string; environment: string }>) {
  const deleted: string[][] = [];
  const supabase = {
    from(_table: string) {
      return {
        select() {
          return { eq: async () => ({ data: tokens, error: null }) };
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
          createSignedUrl: async () => ({
            data: { signedUrl: 'https://signed.example/clip.mp4' },
            error: null,
          }),
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

function deps(overrides: Partial<PushDeps>, tokens = [{ token: 't1', environment: 'production' }]): {
  d: PushDeps;
  send: ReturnType<typeof vi.fn>;
  deleted: string[][];
} {
  const { supabase, deleted } = fakeSupabase(tokens);
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
});
