import type { VercelRequest, VercelResponse } from '@vercel/node';
import { createClient } from '@supabase/supabase-js';
import { createHmac, scryptSync } from 'node:crypto';
import { isIP } from 'node:net';

const projectUrl = 'https://qxjtprxvjmaxlbtljcjw.supabase.co';
const internalEmail = (uid: string) => `${uid}@accounts.ping.invalid`;
const normalizeName = (name: string) => name.trim().replace(/\s+/gu, ' ').toLowerCase();

export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Pragma', 'no-cache');
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST'); res.status(405).json({ error: 'method_not_allowed' }); return;
  }
  const fail = (code: number, error: string) => { res.status(code).json({ error }); };
  const pepper = process.env.PING_ACCOUNT_KEY_PEPPER;
  const url = process.env.SUPABASE_URL?.replace(/\/$/u, '');
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (process.env.PING_ACCOUNT_KEY_ENABLED !== '1' || !pepper || pepper.length < 43 ||
      url !== projectUrl || !serviceKey) { fail(503, 'service_unavailable'); return; }
  const hmac = (purpose: string, value: string) => createHmac('sha256', pepper).update(`${purpose}\0${value}`).digest('hex');
  const client = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
  try {
    if (!req.headers['content-type']?.startsWith('application/json') ||
        Number(req.headers['content-length'] ?? 0) > 4096 ||
        !req.body || typeof req.body !== 'object' || Array.isArray(req.body) ||
        Buffer.byteLength(JSON.stringify(req.body), 'utf8') > 4096) { fail(400, 'invalid_request'); return; }
    const { action, nickname, key } = req.body as Record<string, unknown>;
    if (!['status', 'set', 'login'].includes(action as string)) { fail(400, 'invalid_request'); return; }
    const forwarded = req.headers['x-vercel-forwarded-for'];
    const ip = process.env.VERCEL === '1'
      ? (typeof forwarded === 'string' ? forwarded.split(',')[0].trim() : '')
      : req.socket.remoteAddress ?? '';
    if (!isIP(ip)) { fail(503, 'service_unavailable'); return; }
    const take = async (scope: string, window: number, limit: number) => {
      const result = await client.rpc('ping_account_key_limit', { p_scope: scope, p_window: window, p_limit: limit });
      if (result.error) throw new Error('limiter_unavailable');
      return result.data === true;
    };
    if (!await take(`ip:${hmac('ip', ip)}`, 60, 12)) { res.setHeader('Retry-After', '60'); fail(429, 'rate_limited'); return; }
    const authPassword = (uid: string) => `Aa1!${hmac('auth-password-v1', uid)}`;
    if (action === 'login') {
      if (typeof nickname !== 'string' || nickname.length < 1 || nickname.length > 256 ||
          typeof key !== 'string' || key.length < 12 || key.length > 128) { fail(401, 'invalid_credentials'); return; }
      const name = normalizeName(nickname);
      if (!await take(`name:${hmac('name', name)}`, 3600, 40)) { res.setHeader('Retry-After', '3600'); fail(429, 'rate_limited'); return; }
      const fingerprint = scryptSync(key, hmac('key-salt-v1', ''), 32).toString('hex');
      const args = { p_name: name, p_fingerprint: fingerprint };
      const found = await client.rpc('ping_account_key_lookup', args);
      if (found.error) throw new Error('registry_unavailable');
      const row = found.data as { uid?: string; nickname?: string; revision?: string } | null;
      if (!row?.uid || !row.revision) { fail(401, 'invalid_credentials'); return; }
      const signer = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
      const signed = await signer.auth.signInWithPassword({ email: internalEmail(row.uid), password: authPassword(row.uid) });
      if (signed.error || !signed.data.session || signed.data.user?.id !== row.uid) { fail(401, 'invalid_credentials'); return; }
      // A key/nickname changed during sign-in must not authorize the old credential.
      const current = await client.rpc('ping_account_key_lookup', args);
      if (current.error || current.data?.uid !== row.uid || current.data?.revision !== row.revision) {
        await signer.auth.signOut({ scope: 'local' }); fail(401, 'invalid_credentials'); return;
      }
      const session = signed.data.session;
      res.status(200).json({ access_token: session.access_token, refresh_token: session.refresh_token,
        expires_at: session.expires_at, expires_in: session.expires_in, user: { id: row.uid },
        nickname: current.data.nickname, project_url: url }); return;
    }
    const authorization = req.headers.authorization;
    if (!authorization?.startsWith('Bearer ') || authorization.length > 8192) { fail(401, 'session_required'); return; }
    const owner = await client.auth.getUser(authorization.slice(7));
    if (owner.error || !owner.data.user) { fail(401, 'session_required'); return; }
    const user = owner.data.user;
    if (!await take(`owner:${hmac('owner', user.id)}`, 60, 6)) { res.setHeader('Retry-After', '60'); fail(429, 'rate_limited'); return; }
    const state = await client.rpc('ping_account_key_status', { p_uid: user.id });
    if (state.error) throw new Error('registry_unavailable');
    if (action === 'status') { res.status(200).json({ enabled: state.data === true }); return; }
    if (typeof key !== 'string' || key.length < 12 || key.length > 128) { fail(400, 'key_length'); return; }
    if (user.email && user.email !== internalEmail(user.id)) { fail(409, 'identity_conflict'); return; }
    if (!user.is_anonymous && user.email !== internalEmail(user.id)) { fail(409, 'identity_conflict'); return; }
    const profile = await client.from('profiles').select('nickname').eq('id', user.id).maybeSingle();
    if (profile.error || !profile.data?.nickname) { fail(409, 'profile_required'); return; }
    // Only the first setup adds an internal identity. Key changes never change the Auth password.
    if (state.data !== true) {
      const updated = await client.auth.admin.updateUserById(user.id, {
        email: internalEmail(user.id), email_confirm: true, password: authPassword(user.id),
      });
      if (updated.error || updated.data.user?.id !== user.id) throw new Error('identity_update_failed');
    }
    const fingerprint = scryptSync(key, hmac('key-salt-v1', ''), 32).toString('hex');
    const written = await client.rpc('ping_account_key_write', { p_uid: user.id, p_fingerprint: fingerprint });
    if (written.error?.code === '23505') { fail(409, 'key_conflict'); return; }
    if (written.error) throw new Error('registry_write_failed');
    res.status(200).json({ enabled: true });
  } catch {
    // Never emit request bodies, Auth errors, keys, fingerprints or sessions to logs.
    fail(503, 'service_unavailable');
  }
}
