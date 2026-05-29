import type { VercelRequest, VercelResponse } from '@vercel/node';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { verifyWebhookSecret, parseMessageRecord, parseChatRecord } from './_lib/webhook';
import { buildPingPayload, buildChatPayload } from './_lib/payload';
import { makeApnsJwt, sendApns, type SendApnsInput, type SendApnsResult } from './_lib/apns';

export interface PushDeps {
  supabase: SupabaseClient;
  makeJwt: () => Promise<string>;
  send: (input: SendApnsInput) => Promise<SendApnsResult>;
  bundleId: string;
  expectedSecret: string;
}

export interface PushResult {
  code: number;
  body: unknown;
}

export async function handlePush(
  body: unknown,
  secretHeader: string | undefined,
  deps: PushDeps
): Promise<PushResult> {
  if (!verifyWebhookSecret(secretHeader, deps.expectedSecret)) {
    return { code: 401, body: { error: 'unauthorized' } };
  }

  // Video ping → push to the message's receiver.
  const video = parseMessageRecord(body);
  if (video) {
    const { data: tokens, error: tokenError } = await deps.supabase
      .from('device_tokens')
      .select('token, environment')
      .eq('uid', video.receiverUid);
    if (tokenError) return { code: 500, body: { error: 'db_error', detail: tokenError.message } };
    console.log(`[push] video receiver=${video.receiverUid} tokens=${tokens?.length ?? 0}`);
    if (!tokens || tokens.length === 0) return { code: 200, body: { sent: 0, removed: 0 } };

    const path = `${video.senderUid}/${video.videoId}.mp4`;
    const { data: signed, error: signedError } = await deps.supabase.storage
      .from('ping-videos')
      .createSignedUrl(path, 600);
    if (signedError || !signed?.signedUrl) return { code: 500, body: { error: 'storage_error' } };
    const videoSignedUrl = signed.signedUrl;

    const result = await sendToTokens(deps, tokens, video.messageId, () =>
      buildPingPayload({
        senderName: video.senderNickname,
        messageId: video.messageId,
        roomId: video.roomId,
        videoSignedUrl,
      })
    );
    return { code: 200, body: result };
  }

  // Text chat → push to the room's other members (chat is room-scoped).
  const chat = parseChatRecord(body);
  if (chat) {
    const { data: members, error: memberError } = await deps.supabase
      .from('room_members')
      .select('user_id')
      .eq('room_id', chat.roomId)
      .neq('user_id', chat.senderUid);
    if (memberError) return { code: 500, body: { error: 'db_error', detail: memberError.message } };
    const uids = (members ?? []).map((m: { user_id: string }) => m.user_id);
    console.log(`[push] chat room=${chat.roomId} sender=${chat.senderUid} otherMembers=${uids.length}`);
    if (uids.length === 0) return { code: 200, body: { sent: 0, removed: 0 } };

    const { data: tokens, error: tokenError } = await deps.supabase
      .from('device_tokens')
      .select('token, environment')
      .in('uid', uids);
    if (tokenError) return { code: 500, body: { error: 'db_error', detail: tokenError.message } };
    console.log(`[push] chat tokens=${tokens?.length ?? 0}`);
    if (!tokens || tokens.length === 0) return { code: 200, body: { sent: 0, removed: 0 } };

    const result = await sendToTokens(deps, tokens, chat.chatId, () =>
      buildChatPayload({
        senderName: chat.senderNickname,
        body: chat.body,
        roomId: chat.roomId,
        chatId: chat.chatId,
      })
    );
    return { code: 200, body: { ...result, kind: 'chat' } };
  }

  return { code: 200, body: { ignored: true } };
}

/// Send one push per token (same payload), prune 410 Unregistered tokens.
async function sendToTokens(
  deps: PushDeps,
  tokens: unknown,
  collapseId: string,
  makePayload: () => unknown
): Promise<{ sent: number; removed: number }> {
  const jwt = await deps.makeJwt();
  let sent = 0;
  const gone: string[] = [];
  for (const t of tokens as Array<{ token: string; environment: 'production' | 'sandbox' }>) {
    const res = await deps.send({
      token: t.token,
      environment: t.environment,
      jwt,
      bundleId: deps.bundleId,
      collapseId,
      payload: makePayload(),
    });
    console.log(
      `[push] apns status=${res.status} env=${t.environment} token=…${t.token.slice(-6)} body=${(res.body || '').slice(0, 160)}`
    );
    if (res.status === 200) sent++;
    else if (res.status === 410) gone.push(t.token);
  }
  if (gone.length > 0) {
    await deps.supabase.from('device_tokens').delete().in('token', gone);
  }
  console.log(`[push] result sent=${sent} removed=${gone.length}`);
  return { sent, removed: gone.length };
}

export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'method not allowed' });
    return;
  }

  const supabase = createClient(
    process.env.SUPABASE_URL as string,
    process.env.SUPABASE_SERVICE_ROLE_KEY as string,
    { auth: { persistSession: false } }
  );

  const deps: PushDeps = {
    supabase,
    makeJwt: () =>
      makeApnsJwt({
        keyId: process.env.APNS_KEY_ID as string,
        teamId: process.env.APNS_TEAM_ID as string,
        p8: process.env.APNS_P8 as string,
      }),
    send: sendApns,
    bundleId: process.env.APNS_BUNDLE_ID as string,
    expectedSecret: process.env.PUSH_WEBHOOK_SECRET as string,
  };

  try {
    const out = await handlePush(req.body, req.headers['x-webhook-secret'] as string | undefined, deps);
    res.status(out.code).json(out.body);
  } catch (err) {
    console.error('push handler unhandled error', err);
    res.status(500).json({ error: 'internal_error' });
  }
}
