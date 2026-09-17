import type { VercelRequest, VercelResponse } from '@vercel/node';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import {
  verifyWebhookSecret,
  parseMessageRecord,
  parseChatRecord,
  parseInvitationRecord,
} from './_lib/webhook';
import {
  buildChatPayload,
  buildInvitationPayload,
  buildMacChatPayload,
  buildMacInvitationPayload,
  buildMacPingPayload,
  buildPingPayload,
} from './_lib/payload';
import { makeApnsJwt, sendApns, type SendApnsInput, type SendApnsResult } from './_lib/apns';
import {
  isMobilePlatform,
  selectPushTokens,
  type DeviceToken,
  type PushPlatform,
  type SoundPreference,
} from './_lib/routing';

export type PushBundleIds = Partial<Record<PushPlatform, string>>;

export interface PushDeps {
  supabase: SupabaseClient;
  makeJwt: () => Promise<string>;
  send: (input: SendApnsInput) => Promise<SendApnsResult>;
  /** Platform-specific APNs topics. */
  bundleIds?: PushBundleIds;
  /** Legacy single topic kept during the transition to platform topics. */
  bundleId?: string;
  expectedSecret: string;
}

export interface PushResult {
  code: number;
  body: unknown;
}

const DEFAULT_DESKTOP_PRESENCE_TTL_SECONDS = 45;
type PushEventType = 'video' | 'chat' | 'invitation';

interface ReceiverBatch {
  uid: string;
  tokens: DeviceToken[];
}

interface DeviceTokenRow {
  uid?: unknown;
  token?: unknown;
  platform?: unknown;
  environment?: unknown;
  sound_preference?: unknown;
  soundPreference?: unknown;
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
    const result = await receiverBatches(deps, [video.receiverUid]);
    if (result.error) {
      return { code: 500, body: { error: 'db_error', detail: result.error.message } };
    }

    const selected = result.batches.flatMap((batch) => batch.tokens);
    console.log(`[push] event=video selected=${selected.length}`);
    if (selected.length === 0) return { code: 200, body: { sent: 0, removed: 0 } };

    let videoSignedUrl: string | undefined;
    if (selected.some((token) => isMobilePlatform(token.platform))) {
      const path = `${video.senderUid}/${video.videoId}.mp4`;
      const { data: signed, error: signedError } = await deps.supabase.storage
        .from('ping-videos')
        .createSignedUrl(path, 600);
      if (signedError || !signed?.signedUrl) return { code: 500, body: { error: 'storage_error' } };
      videoSignedUrl = signed.signedUrl;
    }

    const sendResult = await sendToTokens(deps, selected, video.messageId, 'video', (token) => {
      if (token.platform === 'macos') {
        return buildMacPingPayload({
          senderName: video.senderNickname,
          messageId: video.messageId,
          roomId: video.roomId,
          soundPreference: token.soundPreference,
        });
      }
      // The selected mobile set always has a signed URL, but retaining the
      // guard prevents an accidental malformed payload if routing changes.
      if (!videoSignedUrl) return undefined;
      return buildPingPayload({
        senderName: video.senderNickname,
        messageId: video.messageId,
        roomId: video.roomId,
        videoSignedUrl,
      });
    });
    return responseForSendResult(sendResult);
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
    const uids = (members ?? [])
      .map((m: { user_id?: unknown }) => (m.user_id ? String(m.user_id) : ''))
      .filter(Boolean);
    console.log(`[push] event=chat recipients=${uids.length}`);
    if (uids.length === 0) return { code: 200, body: { sent: 0, removed: 0 } };

    const result = await receiverBatches(deps, uids);
    if (result.error) {
      return { code: 500, body: { error: 'db_error', detail: result.error.message } };
    }
    const selected = result.batches.flatMap((batch) => batch.tokens);
    console.log(`[push] event=chat selected=${selected.length}`);
    if (selected.length === 0) return { code: 200, body: { sent: 0, removed: 0, kind: 'chat' } };

    const sendResult = await sendToTokens(deps, selected, chat.chatId, 'chat', (token) => {
      if (token.platform === 'macos') {
        return buildMacChatPayload({
          senderName: chat.senderNickname,
          body: chat.body,
          roomId: chat.roomId,
          chatId: chat.chatId,
          soundPreference: token.soundPreference,
        });
      }
      return buildChatPayload({
        senderName: chat.senderNickname,
        body: chat.body,
        roomId: chat.roomId,
        chatId: chat.chatId,
      });
    });
    return responseForSendResult(sendResult, { kind: 'chat' });
  }

  // Room invitation → push to the invitation's recipient only.
  const invitation = parseInvitationRecord(body);
  if (invitation) {
    const result = await receiverBatches(deps, [invitation.recipientUid]);
    if (result.error) {
      return { code: 500, body: { error: 'db_error', detail: result.error.message } };
    }
    const selected = result.batches.flatMap((batch) => batch.tokens);
    console.log(`[push] event=invitation selected=${selected.length}`);
    if (selected.length === 0) {
      return { code: 200, body: { sent: 0, removed: 0, kind: 'invitation' } };
    }

    const sendResult = await sendToTokens(deps, selected, invitation.inviteId, 'invitation', (token) => {
      const input = {
        inviteId: invitation.inviteId,
        roomId: invitation.roomId,
        fromNickname: invitation.fromNickname,
        roomName: invitation.roomName,
        soundPreference: token.soundPreference,
      };
      return token.platform === 'macos'
        ? buildMacInvitationPayload(input)
        : buildInvitationPayload(input);
    });
    return responseForSendResult(sendResult, { kind: 'invitation' });
  }

  return { code: 200, body: { ignored: true } };
}

async function receiverBatches(
  deps: PushDeps,
  uids: string[]
): Promise<{ batches: ReceiverBatch[]; error: { message: string } | null }> {
  const uniqueUids = [...new Set(uids)];
  if (uniqueUids.length === 0) return { batches: [], error: null };

  const desktopPresence = await freshDesktopPresenceUids(deps, uniqueUids);
  if (desktopPresence.error) return { batches: [], error: desktopPresence.error };

  const queried = await queryDeviceTokens(deps, uniqueUids);
  if (queried.error) return { batches: [], error: queried.error };

  const batches: ReceiverBatch[] = [];
  for (const uid of uniqueUids) {
    const tokens = queried.rows
      .filter((row) => row.uid === uid)
      .map((row) => normalizeDeviceToken(row, uid))
      .filter((token): token is DeviceToken => token !== null);
    batches.push({
      uid,
      tokens: selectPushTokens(tokens, desktopPresence.uids.has(uid)),
    });
  }
  return { batches, error: null };
}

async function queryDeviceTokens(
  deps: PushDeps,
  uids: string[]
): Promise<{ rows: DeviceTokenRow[]; error: { message: string } | null }> {
  const table = deps.supabase.from('device_tokens');
  let query = table.select('uid, token, platform, environment, sound_preference');
  // Keep the single-receiver form compatible with the existing PostgREST
  // stub and avoid an unnecessary `in` filter for the common video path.
  const filterable = query as typeof query & {
    eq?: (column: string, value: string) => typeof query;
    in?: (column: string, values: string[]) => typeof query;
  };
  if (uids.length === 1 && typeof filterable.eq === 'function') {
    query = filterable.eq('uid', uids[0]);
  } else if (typeof filterable.in === 'function') {
    query = filterable.in('uid', uids);
  } else {
    query = filterable.eq?.('uid', uids[0]) ?? query;
  }
  const { data, error } = await query;
  if (error) return { rows: [], error };

  const rows = (data ?? []) as unknown as DeviceTokenRow[];
  // Legacy rows from before platform-aware routing have no uid/platform. A
  // single receiver can safely inherit its uid and the old mobile default.
  return {
    rows: rows.map((row) => ({
      ...row,
      uid: row.uid ?? (uids.length === 1 ? uids[0] : undefined),
    })),
    error: null,
  };
}

function normalizeDeviceToken(row: DeviceTokenRow, fallbackUid: string): DeviceToken | null {
  if (!row.token) return null;
  const platform = row.platform === 'macos' || row.platform === 'watchos' || row.platform === 'ios'
    ? row.platform
    : 'ios';
  const environment = row.environment === 'sandbox' ? 'sandbox' : 'production';
  const soundPreference: SoundPreference = row.sound_preference === 'none' || row.soundPreference === 'none'
    ? 'none'
    : 'default';
  return {
    uid: row.uid ? String(row.uid) : fallbackUid,
    token: String(row.token),
    platform,
    environment,
    soundPreference,
  };
}

async function freshDesktopPresenceUids(
  deps: PushDeps,
  uids: string[]
): Promise<{ uids: Set<string>; error: { message: string } | null }> {
  if (uids.length === 0) return { uids: new Set(), error: null };

  const ttlSeconds = Number(process.env.PUSH_DESKTOP_PRESENCE_TTL_SECONDS ?? DEFAULT_DESKTOP_PRESENCE_TTL_SECONDS);
  const effectiveTtlSeconds = Number.isFinite(ttlSeconds) && ttlSeconds > 0
    ? ttlSeconds
    : DEFAULT_DESKTOP_PRESENCE_TTL_SECONDS;
  const cutoff = new Date(Date.now() - effectiveTtlSeconds * 1000).toISOString();

  // ended_at이 찍힌 행은 Ping을 끈 기기다. 마지막 접속 시각을 남기려고 행을
  // 지우지 않으므로, live 라우팅은 ended_at과 45초 TTL을 함께 확인한다.
  const { data, error } = await deps.supabase
    .from('desktop_presence')
    .select('uid, platform, updated_at, ended_at')
    .in('uid', uids)
    .gte('updated_at', cutoff)
    .is('ended_at', null);

  if (error) return { uids: new Set(), error };

  const fresh = new Set<string>();
  for (const row of (data ?? []) as Array<{ uid?: unknown; platform?: unknown }>) {
    // Older rows/stubs predate the platform column and represent macOS.
    if (row.uid && (row.platform === undefined || row.platform === 'macos')) {
      fresh.add(String(row.uid));
    }
  }
  return { uids: fresh, error: null };
}

/// Send one push per token (same event, platform-specific payload), pruning
/// 410 Unregistered tokens.
interface SendTokensError {
  error: 'config_error' | 'apns_error' | 'db_error';
  detail: string;
  sent?: number;
  removed?: number;
}

type SendTokensResult = { sent: number; removed: number } | SendTokensError;

function responseForSendResult(
  result: SendTokensResult,
  extra?: Record<string, unknown>
): PushResult {
  if ('error' in result) return { code: 500, body: result };
  return { code: 200, body: { ...result, ...extra } };
}

async function sendToTokens(
  deps: PushDeps,
  tokens: DeviceToken[],
  collapseId: string,
  eventType: PushEventType,
  makePayload: (token: DeviceToken) => unknown
): Promise<SendTokensResult> {
  const bundleIds = new Map<PushPlatform, string>();
  for (const token of tokens) {
    const bundleId = bundleIdFor(deps, token.platform);
    if (!bundleId) {
      return {
        error: 'config_error',
        detail: token.platform === 'macos'
          ? 'APNS_MACOS_BUNDLE_ID is required for macOS push'
          : `${bundleEnvName(token.platform)} is required for ${token.platform} push`,
      };
    }
    bundleIds.set(token.platform, bundleId);
  }

  const jwt = await deps.makeJwt();
  let sent = 0;
  const gone: string[] = [];
  const failureStatuses = new Set<number>();
  let failureCount = 0;
  let transportFailures = 0;
  const statusCounts = new Map<number, number>();

  // APNs and the database webhook are at-least-once boundaries. Attempt each
  // selected token once so one provider failure does not starve healthy
  // recipients, then return 500 for any non-200/non-410 result so the webhook
  // retries. A replay can duplicate earlier successes because this endpoint
  // has no durable per-token delivery ledger; the event collapse ID lets APNs
  // coalesce pending copies while preserving the retry signal for failures.
  for (const token of tokens) {
    const payload = makePayload(token);
    if (payload === undefined) continue;
    try {
      const res = await deps.send({
        token: token.token,
        environment: token.environment,
        jwt,
        bundleId: bundleIds.get(token.platform) as string,
        collapseId,
        payload,
      });
      statusCounts.set(res.status, (statusCounts.get(res.status) ?? 0) + 1);
      if (res.status === 200) sent++;
      else if (res.status === 410) gone.push(token.token);
      else {
        failureStatuses.add(res.status);
        failureCount++;
      }
    } catch {
      transportFailures++;
    }
  }

  const statusSummary = formatStatusCounts(statusCounts, transportFailures);
  if (statusSummary) {
    console.log(`[push] apns event=${eventType} status=${statusSummary}`);
  }

  let removed = 0;
  if (gone.length > 0) {
    const { error: cleanupError } = await deps.supabase
      .from('device_tokens')
      .delete()
      .in('token', gone);
    if (cleanupError) {
      console.log(`[push] result event=${eventType} status=cleanup_error sent=${sent} removed=0`);
      return {
        error: 'db_error',
        detail: cleanupError.message,
        sent,
        removed: 0,
      };
    }
    removed = gone.length;
  }

  if (failureStatuses.size > 0 || transportFailures > 0) {
    console.log(
      `[push] result event=${eventType} status=error sent=${sent} removed=${removed} failures=${failureCount + transportFailures}`
    );
    return {
      error: 'apns_error',
      detail: apnsFailureDetail(failureStatuses, transportFailures),
      sent,
      removed,
    };
  }

  console.log(`[push] result event=${eventType} status=ok sent=${sent} removed=${removed}`);
  return { sent, removed };
}

function bundleIdFor(deps: PushDeps, platform: PushPlatform): string | undefined {
  const mapped = normalizeBundleId(deps.bundleIds?.[platform]);
  if (platform === 'macos') return mapped;
  if (mapped) return mapped;
  if (platform === 'watchos') {
    const iosTopic = normalizeBundleId(deps.bundleIds?.ios);
    if (iosTopic) return iosTopic;
  }
  return normalizeBundleId(deps.bundleId);
}

function normalizeBundleId(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const normalized = value.trim();
  return normalized || undefined;
}

function bundleEnvName(platform: PushPlatform): string {
  return platform === 'watchos'
    ? 'APNS_WATCHOS_BUNDLE_ID or APNS_IOS_BUNDLE_ID'
    : 'APNS_IOS_BUNDLE_ID';
}

function formatStatusCounts(statusCounts: Map<number, number>, transportFailures: number): string {
  const statuses = [...statusCounts.entries()]
    .sort(([left], [right]) => left - right)
    .map(([status, count]) => `${status}:${count}`);
  if (transportFailures > 0) statuses.push(`transport_error:${transportFailures}`);
  return statuses.join(',');
}

function apnsFailureDetail(failureStatuses: Set<number>, transportFailures: number): string {
  const statuses = [...failureStatuses].sort((left, right) => left - right);
  if (statuses.length === 1 && transportFailures === 0) {
    return `APNs returned failure status ${statuses[0]}`;
  }
  if (statuses.length > 0) {
    return `APNs returned failure statuses ${statuses.join(', ')}`;
  }
  return 'APNs request failed before receiving a response';
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

  const legacyBundleId = normalizeBundleId(process.env.APNS_BUNDLE_ID);
  const iosBundleId = normalizeBundleId(process.env.APNS_IOS_BUNDLE_ID) ?? legacyBundleId;
  const watchosBundleId = normalizeBundleId(process.env.APNS_WATCHOS_BUNDLE_ID) ?? iosBundleId;
  const deps: PushDeps = {
    supabase,
    makeJwt: () =>
      makeApnsJwt({
        keyId: process.env.APNS_KEY_ID as string,
        teamId: process.env.APNS_TEAM_ID as string,
        p8: process.env.APNS_P8 as string,
      }),
    send: sendApns,
    bundleIds: {
      // APNS_BUNDLE_ID is the historical iOS topic. Do not reuse it for
      // macOS, whose topic is a distinct App ID; an unset macOS topic should
      // fail at APNs rather than silently target the wrong application.
      macos: normalizeBundleId(process.env.APNS_MACOS_BUNDLE_ID),
      ios: iosBundleId,
      watchos: watchosBundleId,
    },
    expectedSecret: process.env.PUSH_WEBHOOK_SECRET as string,
  };

  try {
    const out = await handlePush(req.body, req.headers['x-webhook-secret'] as string | undefined, deps);
    res.status(out.code).json(out.body);
  } catch (err) {
    console.error('[push] event=unknown status=internal_error');
    res.status(500).json({ error: 'internal_error' });
  }
}
