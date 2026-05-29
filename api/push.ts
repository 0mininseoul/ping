import type { VercelRequest, VercelResponse } from '@vercel/node';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { verifyWebhookSecret, parseMessageRecord } from './_lib/webhook';
import { buildPingPayload } from './_lib/payload';
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

  const rec = parseMessageRecord(body);
  if (!rec) return { code: 200, body: { ignored: true } };

  const { data: tokens } = await deps.supabase
    .from('device_tokens')
    .select('token, environment')
    .eq('uid', rec.receiverUid);

  if (!tokens || tokens.length === 0) return { code: 200, body: { sent: 0, removed: 0 } };

  const path = `${rec.senderUid}/${rec.videoId}.mp4`;
  const { data: signed } = await deps.supabase.storage
    .from('ping-videos')
    .createSignedUrl(path, 600);
  const videoSignedUrl = signed?.signedUrl ?? '';

  const jwt = await deps.makeJwt();
  let sent = 0;
  const gone: string[] = [];

  for (const t of tokens as Array<{ token: string; environment: 'production' | 'sandbox' }>) {
    const payload = buildPingPayload({
      senderName: rec.senderNickname,
      messageId: rec.messageId,
      roomId: rec.roomId,
      videoSignedUrl,
    });
    const res = await deps.send({
      token: t.token,
      environment: t.environment,
      jwt,
      bundleId: deps.bundleId,
      collapseId: rec.messageId,
      payload,
    });
    if (res.status === 200) sent++;
    else if (res.status === 410) gone.push(t.token);
  }

  if (gone.length > 0) {
    await deps.supabase.from('device_tokens').delete().in('token', gone);
  }

  return { code: 200, body: { sent, removed: gone.length } };
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

  const out = await handlePush(
    req.body,
    req.headers['x-webhook-secret'] as string | undefined,
    deps
  );
  res.status(out.code).json(out.body);
}
