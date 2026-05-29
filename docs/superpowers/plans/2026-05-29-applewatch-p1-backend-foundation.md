# Apple Watch Push — P1: Backend Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the server-side foundation for Apple Watch push: a `device_tokens` table + register/remove RPCs in Supabase, and a Vercel serverless function that turns a `messages` INSERT webhook into an APNs push carrying a short-lived signed video URL.

**Architecture:** Supabase stores device tokens (RLS: owner-only) and fires a Database Webhook on `messages` INSERT → POST to `https://ping0min.vercel.app/api/push`. The Vercel function (`/api/push.ts`) verifies a shared secret, looks up the receiver's tokens with the service-role key, mints a short-lived signed Storage URL for the 3s clip, builds an APNs payload (`mutable-content` so a later Notification Service Extension can attach the video), signs an ES256 APNs JWT, and sends over HTTP/2. Pure logic (webhook parse, payload build, JWT) is split into `/api/_lib/*` for unit testing; the network send and DB webhook wiring are verified manually at the end (full E2E push needs a real device token from P3).

**Tech Stack:** Supabase Postgres + pgTAP (`supabase test db`), Vercel Node serverless functions (`@vercel/node`), `@supabase/supabase-js`, `jose` (ES256 JWT), Node built-in `http2`, Vitest.

This is **P1 of 6**. It produces independently testable software (RPCs + push function units). Later plans: P2 shared Swift package, P3 iOS app + Notification Service Extension, P4 session handoff, P5 watchOS app, P6 TestFlight E2E.

Design source: `docs/superpowers/specs/2026-05-29-applewatch-push-stt-design.md`.

---

## Prerequisites

- **Docker running** (for `npx supabase start` / `npx supabase test db`). Verify: `docker info` succeeds.
- Supabase CLI via `npx supabase` (already used in repo).
- **Vercel CLI** for Tasks 3 & 8: `npm i -g vercel` (or `npx vercel`). Project is already linked (`.vercel/project.json`, project `ping`).
- **Apple secrets** (needed only for Task 8 live verification, not for unit tests): an APNs Auth Key `.p8` from the Apple Developer portal (Keys → new key with "Apple Push Notifications service" enabled), its `Key ID`, the `Team ID`, and the iOS bundle id (will be `com.youngminpark.ping.PingMobile`, finalized in P3). Tasks 1–7 do **not** need these.

**Environment variables** the deployed function will read (set in Task 8, Vercel dashboard → Project `ping` → Settings → Environment Variables):

| Var | Meaning |
|---|---|
| `SUPABASE_URL` | `https://<ref>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | service-role key (server-only; never client) |
| `PUSH_WEBHOOK_SECRET` | random string shared with the DB webhook header |
| `APNS_KEY_ID` | APNs key id (10 chars) |
| `APNS_TEAM_ID` | Apple Team ID (10 chars) |
| `APNS_P8` | full contents of the `.p8` file (PKCS#8 PEM, with newlines) |
| `APNS_BUNDLE_ID` | iOS app bundle id (APNs topic) |

---

## File Structure

**Create:**
- `supabase/tests/device_tokens_test.sql` — pgTAP tests for table, RLS isolation, and RPCs.
- `supabase/migrations/20260529000100_device_tokens_and_push.sql` — `device_tokens` table + RLS policies + `ping_register_device_token` / `ping_remove_device_token`.
- `api/health.ts` — trivial health endpoint to verify Vercel function wiring (kept after as a liveness probe).
- `api/_lib/webhook.ts` — webhook secret check + `messages` record parser (pure).
- `api/_lib/payload.ts` — APNs payload builder (pure).
- `api/_lib/apns.ts` — APNs ES256 JWT signer + HTTP/2 sender.
- `api/push.ts` — Vercel handler: wires env/deps → `handlePush`.
- `api/_lib/__tests__/webhook.test.ts`
- `api/_lib/__tests__/payload.test.ts`
- `api/_lib/__tests__/apns.test.ts`
- `api/_lib/__tests__/push.test.ts`
- `vitest.config.ts` — root vitest config.

**Modify:**
- `package.json` (repo root) — add deps + `test` scripts.
- `.vercelignore` — allowlist `/api`.

> **Why repo-root `/api` and not `web/api`:** the Vercel project's `rootDirectory` is `null` (repo root), so Vercel only auto-detects functions in a top-level `/api`. `.vercelignore` currently allowlists only `web/` + `package.json`, so we must add `/api`. Files under an underscore segment (`api/_lib/…`) are not routed by Vercel, so helpers and `__tests__` won't become endpoints.

---

## Task 1: Failing pgTAP test for `device_tokens`

**Files:**
- Create: `supabase/tests/device_tokens_test.sql`

- [ ] **Step 1: Write the failing pgTAP test**

Create `supabase/tests/device_tokens_test.sql`:

```sql
begin;
select plan(10);

-- Structure
select has_table('public', 'device_tokens', 'device_tokens table exists');
select has_column('public', 'device_tokens', 'uid', 'has uid column');
select has_column('public', 'device_tokens', 'token', 'has token column');
select has_column('public', 'device_tokens', 'platform', 'has platform column');
select has_function('public', 'ping_register_device_token', 'register rpc exists');
select has_function('public', 'ping_remove_device_token', 'remove rpc exists');

-- Seed two auth users + profiles (local Supabase auth columns are nullable/defaulted)
insert into auth.users (id, aud, role, instance_id, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now(), now()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now(), now())
on conflict (id) do nothing;

insert into public.profiles (id, nickname, searchable_nickname)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'alice', 'alice'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bob', 'bob')
on conflict (id) do nothing;

-- Act as alice and register a token
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);
select lives_ok(
  $$ select public.ping_register_device_token('tok-alice', 'ios', 'production') $$,
  'alice can register a token'
);
select is(
  (select count(*)::int from public.device_tokens where token = 'tok-alice'),
  1,
  'exactly one row after register'
);

-- RLS isolation: as bob (authenticated role enforces RLS), alice's token is invisible
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);
select is(
  (select count(*)::int from public.device_tokens),
  0,
  'bob sees zero tokens (RLS isolates by uid)'
);
reset role;

select * from finish();
rollback;
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
docker info >/dev/null && npx supabase start
npx supabase test db
```

Expected: FAIL — the suite errors/fails because `public.device_tokens` and the RPCs do not exist yet (e.g. `relation "public.device_tokens" does not exist` / `has_table … not ok`).

---

## Task 2: `device_tokens` migration (table + RLS + RPCs)

**Files:**
- Create: `supabase/migrations/20260529000100_device_tokens_and_push.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260529000100_device_tokens_and_push.sql`:

```sql
-- Apple Watch push: per-device APNs token registry (P1 backend foundation).

create table if not exists public.device_tokens (
    id uuid primary key default extensions.gen_random_uuid(),
    uid uuid not null references public.profiles(id) on delete cascade,
    token text not null check (length(trim(token)) > 0),
    platform text not null check (platform in ('ios', 'watchos')),
    environment text not null default 'production' check (environment in ('production', 'sandbox')),
    updated_at timestamptz not null default now(),
    unique (uid, token)
);

create index if not exists device_tokens_uid_idx on public.device_tokens (uid);

alter table public.device_tokens enable row level security;

create policy device_tokens_select_own on public.device_tokens
    for select to authenticated using (uid = auth.uid());
create policy device_tokens_insert_own on public.device_tokens
    for insert to authenticated with check (uid = auth.uid());
create policy device_tokens_update_own on public.device_tokens
    for update to authenticated using (uid = auth.uid()) with check (uid = auth.uid());
create policy device_tokens_delete_own on public.device_tokens
    for delete to authenticated using (uid = auth.uid());

create or replace function public.ping_register_device_token(
    token_text text,
    platform_text text,
    environment_text text default 'production'
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
    if auth.uid() is null then
        raise exception 'not authenticated';
    end if;
    insert into public.device_tokens (uid, token, platform, environment, updated_at)
    values (auth.uid(), token_text, platform_text, environment_text, now())
    on conflict (uid, token)
    do update set platform = excluded.platform,
                  environment = excluded.environment,
                  updated_at = now();
end;
$$;

create or replace function public.ping_remove_device_token(token_text text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
    delete from public.device_tokens
    where uid = auth.uid() and token = token_text;
end;
$$;

grant execute on function public.ping_register_device_token(text, text, text) to authenticated;
grant execute on function public.ping_remove_device_token(text) to authenticated;
```

- [ ] **Step 2: Run the test to verify it passes**

```bash
npx supabase test db
```

Expected: PASS — `device_tokens_test.sql .. ok` with `All 10 subtests passed` (the CLI applies migrations to a fresh test DB, then runs pgTAP).

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260529000100_device_tokens_and_push.sql supabase/tests/device_tokens_test.sql
git commit -m "feat(backend): device_tokens table + register/remove RPCs with pgTAP

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Vercel function wiring smoke test (`/api/health.ts`)

De-risk the repo-root `/api` + `.vercelignore` setup before building real logic.

**Files:**
- Create: `api/health.ts`
- Modify: `.vercelignore`
- Modify: `package.json`

- [ ] **Step 1: Add the health function**

Create `api/health.ts`:

```ts
import type { VercelRequest, VercelResponse } from '@vercel/node';

export default function handler(_req: VercelRequest, res: VercelResponse) {
  res.status(200).json({ ok: true, service: 'ping-push' });
}
```

- [ ] **Step 2: Allowlist `/api` in `.vercelignore`**

The current `.vercelignore` ignores everything (`*`) and allowlists `web/` + `package.json`. Add `/api` to the allowlist. Edit `.vercelignore` to read:

```
*
!.vercel/
!.vercel/output/
!.vercel/output/**
!package.json
!api/
!api/**
!web/
!web/**
web/.DS_Store
web/.vercel/**
web/dist/**
web/node_modules/**
```

- [ ] **Step 3: Add deps + test scripts to root `package.json`**

Replace `package.json` (repo root) with:

```json
{
  "name": "ping",
  "private": true,
  "scripts": {
    "build": "npm --prefix web ci && npm --prefix web run build && rm -rf dist && cp -R web/dist dist",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.45.0",
    "jose": "^5.9.0"
  },
  "devDependencies": {
    "@vercel/node": "^3.2.0",
    "@types/node": "^22.0.0",
    "typescript": "^5.6.2",
    "vitest": "^2.1.0"
  }
}
```

- [ ] **Step 4: Install root deps**

```bash
npm install
```

Expected: creates root `node_modules` + `package-lock.json` with `jose`, `@supabase/supabase-js`, `vitest`, `@vercel/node`.

- [ ] **Step 5: Deploy a preview and probe the function**

```bash
npx vercel pull --yes
npx vercel deploy 2>&1 | tee /tmp/ping-deploy.txt
DEPLOY_URL=$(grep -oE 'https://[a-z0-9-]+\.vercel\.app' /tmp/ping-deploy.txt | head -1)
curl -s "$DEPLOY_URL/api/health"
```

Expected: `{"ok":true,"service":"ping-push"}`. If you instead get the SPA HTML or a 404, the `/api` allowlist or root-directory wiring is wrong — fix before proceeding (this is exactly the unknown this task de-risks).

- [ ] **Step 6: Commit**

```bash
git add api/health.ts .vercelignore package.json package-lock.json
git commit -m "chore(push): scaffold repo-root /api functions + health probe

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Webhook secret check + record parser (`api/_lib/webhook.ts`)

**Files:**
- Create: `vitest.config.ts`
- Create: `api/_lib/__tests__/webhook.test.ts`
- Create: `api/_lib/webhook.ts`

- [ ] **Step 1: Add vitest config**

Create `vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['api/**/__tests__/**/*.test.ts'],
    environment: 'node',
  },
});
```

- [ ] **Step 2: Write the failing test**

Create `api/_lib/__tests__/webhook.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { verifyWebhookSecret, parseMessageRecord } from '../webhook';

describe('verifyWebhookSecret', () => {
  it('accepts matching non-empty secret', () => {
    expect(verifyWebhookSecret('s3cret', 's3cret')).toBe(true);
  });
  it('rejects mismatch, missing, or empty expected', () => {
    expect(verifyWebhookSecret('a', 'b')).toBe(false);
    expect(verifyWebhookSecret(undefined, 'b')).toBe(false);
    expect(verifyWebhookSecret('a', '')).toBe(false);
  });
});

describe('parseMessageRecord', () => {
  const good = {
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

  it('parses a valid INSERT on messages', () => {
    expect(parseMessageRecord(good)).toEqual({
      messageId: 'msg-1',
      receiverUid: 'rcv-1',
      senderUid: 'snd-1',
      videoId: 'vid-1',
      roomId: 'room-1',
      senderNickname: '박영민',
    });
  });

  it('defaults sender nickname when absent', () => {
    const r = { ...good, record: { ...good.record, sender_nickname: undefined } };
    expect(parseMessageRecord(r)?.senderNickname).toBe('Ping');
  });

  it('ignores non-INSERT, wrong table, or missing fields', () => {
    expect(parseMessageRecord({ ...good, type: 'UPDATE' })).toBeNull();
    expect(parseMessageRecord({ ...good, table: 'chat_messages' })).toBeNull();
    expect(parseMessageRecord({ ...good, record: { ...good.record, video_id: undefined } })).toBeNull();
    expect(parseMessageRecord(null)).toBeNull();
  });
});
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
npx vitest run api/_lib/__tests__/webhook.test.ts
```

Expected: FAIL — `Failed to resolve import "../webhook"` (file does not exist yet).

- [ ] **Step 4: Write the implementation**

Create `api/_lib/webhook.ts`:

```ts
export function verifyWebhookSecret(provided: string | undefined, expected: string): boolean {
  return Boolean(provided) && Boolean(expected) && provided === expected;
}

export interface MessageRecord {
  messageId: string;
  receiverUid: string;
  senderUid: string;
  videoId: string;
  roomId: string;
  senderNickname: string;
}

export function parseMessageRecord(body: unknown): MessageRecord | null {
  if (!body || typeof body !== 'object') return null;
  const b = body as Record<string, unknown>;
  if (b.type !== 'INSERT' || b.table !== 'messages' || !b.record) return null;
  const r = b.record as Record<string, unknown>;
  if (!r.id || !r.receiver_uid || !r.sender_uid || !r.video_id || !r.room_id) return null;
  return {
    messageId: String(r.id),
    receiverUid: String(r.receiver_uid),
    senderUid: String(r.sender_uid),
    videoId: String(r.video_id),
    roomId: String(r.room_id),
    senderNickname: r.sender_nickname ? String(r.sender_nickname) : 'Ping',
  };
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
npx vitest run api/_lib/__tests__/webhook.test.ts
```

Expected: PASS — `Test Files 1 passed`, all cases green.

- [ ] **Step 6: Commit**

```bash
git add vitest.config.ts api/_lib/webhook.ts api/_lib/__tests__/webhook.test.ts
git commit -m "feat(push): webhook secret check + messages record parser

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: APNs payload builder (`api/_lib/payload.ts`)

**Files:**
- Create: `api/_lib/__tests__/payload.test.ts`
- Create: `api/_lib/payload.ts`

- [ ] **Step 1: Write the failing test**

Create `api/_lib/__tests__/payload.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { buildPingPayload } from '../payload';

describe('buildPingPayload', () => {
  const p = buildPingPayload({
    senderName: '박영민',
    messageId: 'msg-1',
    roomId: 'room-1',
    videoSignedUrl: 'https://signed.example/clip.mp4',
  });

  it('sets mutable-content so the NSE can attach the video', () => {
    expect(p.aps['mutable-content']).toBe(1);
  });

  it('sets the PING_MESSAGE category for the reply action', () => {
    expect(p.aps.category).toBe('PING_MESSAGE');
  });

  it('shows the sender name in the alert title', () => {
    expect(p.aps.alert.title).toBe('박영민');
  });

  it('carries custom keys the client needs', () => {
    expect(p.messageId).toBe('msg-1');
    expect(p.roomId).toBe('room-1');
    expect(p.videoSignedUrl).toBe('https://signed.example/clip.mp4');
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
npx vitest run api/_lib/__tests__/payload.test.ts
```

Expected: FAIL — cannot resolve `../payload`.

- [ ] **Step 3: Write the implementation**

Create `api/_lib/payload.ts`:

```ts
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
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
npx vitest run api/_lib/__tests__/payload.test.ts
```

Expected: PASS — 4 tests green.

- [ ] **Step 5: Commit**

```bash
git add api/_lib/payload.ts api/_lib/__tests__/payload.test.ts
git commit -m "feat(push): APNs ping payload builder

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: APNs ES256 JWT signer (`api/_lib/apns.ts`)

The JWT is unit-tested. The HTTP/2 `sendApns` transport is included here but verified live in Task 8 (network calls are not unit-tested).

**Files:**
- Create: `api/_lib/__tests__/apns.test.ts`
- Create: `api/_lib/apns.ts`

- [ ] **Step 1: Write the failing test**

Create `api/_lib/__tests__/apns.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { generateKeyPair, exportPKCS8, decodeJwt, decodeProtectedHeader } from 'jose';
import { makeApnsJwt } from '../apns';

describe('makeApnsJwt', () => {
  it('signs an ES256 token with kid header and team iss', async () => {
    const { privateKey } = await generateKeyPair('ES256');
    const p8 = await exportPKCS8(privateKey);

    const jwt = await makeApnsJwt({ keyId: 'KEY1234567', teamId: 'TEAM999999', p8 });

    const header = decodeProtectedHeader(jwt);
    const claims = decodeJwt(jwt);
    expect(header.alg).toBe('ES256');
    expect(header.kid).toBe('KEY1234567');
    expect(claims.iss).toBe('TEAM999999');
    expect(typeof claims.iat).toBe('number');
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
npx vitest run api/_lib/__tests__/apns.test.ts
```

Expected: FAIL — cannot resolve `../apns`.

- [ ] **Step 3: Write the implementation**

Create `api/_lib/apns.ts`:

```ts
import http2 from 'node:http2';
import { SignJWT, importPKCS8 } from 'jose';

export interface ApnsKey {
  keyId: string;
  teamId: string;
  p8: string;
}

export async function makeApnsJwt(key: ApnsKey): Promise<string> {
  const privateKey = await importPKCS8(key.p8, 'ES256');
  return new SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: key.keyId })
    .setIssuer(key.teamId)
    .setIssuedAt()
    .sign(privateKey);
}

export interface SendApnsInput {
  token: string;
  environment: 'production' | 'sandbox';
  jwt: string;
  bundleId: string;
  collapseId?: string;
  payload: unknown;
}

export interface SendApnsResult {
  status: number;
  body: string;
}

export function sendApns(input: SendApnsInput): Promise<SendApnsResult> {
  const host =
    input.environment === 'sandbox'
      ? 'https://api.sandbox.push.apple.com'
      : 'https://api.push.apple.com';

  return new Promise((resolve, reject) => {
    const client = http2.connect(host);
    client.on('error', reject);

    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${input.token}`,
      authorization: `bearer ${input.jwt}`,
      'apns-topic': input.bundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
      ...(input.collapseId ? { 'apns-collapse-id': input.collapseId } : {}),
    });

    let status = 0;
    let body = '';
    req.on('response', (headers) => {
      status = Number(headers[':status']);
    });
    req.setEncoding('utf8');
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      client.close();
      resolve({ status, body });
    });
    req.on('error', (err) => {
      client.close();
      reject(err);
    });

    req.write(JSON.stringify(input.payload));
    req.end();
  });
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
npx vitest run api/_lib/__tests__/apns.test.ts
```

Expected: PASS — ES256 JWT decoded with correct `alg`, `kid`, `iss`, `iat`.

- [ ] **Step 5: Commit**

```bash
git add api/_lib/apns.ts api/_lib/__tests__/apns.test.ts
git commit -m "feat(push): APNs ES256 JWT signer + HTTP/2 sender

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Push handler with injected deps (`api/push.ts`)

`handlePush` holds the orchestration and is unit-tested with fakes; the default export wires real env + deps.

**Files:**
- Create: `api/_lib/__tests__/push.test.ts`
- Create: `api/push.ts`

- [ ] **Step 1: Write the failing test**

Create `api/_lib/__tests__/push.test.ts`:

```ts
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
npx vitest run api/_lib/__tests__/push.test.ts
```

Expected: FAIL — cannot resolve `../../push`.

- [ ] **Step 3: Write the implementation**

Create `api/push.ts`:

```ts
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
```

- [ ] **Step 4: Run the full test suite to verify it passes**

```bash
npm test
```

Expected: PASS — all 4 test files (webhook, payload, apns, push) green.

- [ ] **Step 5: Commit**

```bash
git add api/push.ts api/_lib/__tests__/push.test.ts
git commit -m "feat(push): /api/push handler (webhook -> signed url -> APNs)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Live wiring — env vars, DB webhook, end-to-end verification

Unit tests are green; now connect the real pieces. Requires the Apple secrets from Prerequisites.

- [ ] **Step 1: Set Vercel environment variables**

In Vercel dashboard → Project `ping` → Settings → Environment Variables, add all seven vars from the Prerequisites table (Production + Preview). Generate the webhook secret:

```bash
openssl rand -hex 24
```

Use that value for `PUSH_WEBHOOK_SECRET` (you'll paste the same value into the DB webhook in Step 3).

- [ ] **Step 2: Deploy to production**

```bash
npx vercel deploy --prod 2>&1 | tee /tmp/ping-prod.txt
curl -s "https://ping0min.vercel.app/api/health"
```

Expected: `{"ok":true,"service":"ping-push"}`.

- [ ] **Step 3: Create the Supabase Database Webhook**

In Supabase dashboard → Database → Webhooks → Create:
- Table: `public.messages`, Events: **Insert** only.
- Type: HTTP Request, Method: `POST`, URL: `https://ping0min.vercel.app/api/push`.
- HTTP Header: `x-webhook-secret` = the value from Step 1.

(Per the design doc this is configured in the dashboard, not a migration, to avoid depending on `supabase_functions`/`pg_net` in local pgTAP runs.)

- [ ] **Step 4: Verify the webhook fires (secret accepted, no token yet)**

Insert a throwaway message row against the **remote** project as an authenticated test user (or via the dashboard SQL editor with a valid `sender_uid`/`receiver_uid`/`room_id` from existing data), then check the function log:

```bash
npx vercel logs https://ping0min.vercel.app --since 5m
```

Expected: a `POST /api/push` entry returning `200` with `{"sent":0,"removed":0}` (no device token registered for that receiver yet). A `401` means the `x-webhook-secret` header/value is mismatched — fix and re-test.

- [ ] **Step 5: (Optional) Real APNs round-trip with a scratch token**

If you have a real APNs device token from any test build, insert it via SQL editor:

```sql
insert into public.device_tokens (uid, token, platform, environment)
values ('<receiver_uid>', '<real_apns_hex_token>', 'ios', 'sandbox');
```

Insert a message for that `<receiver_uid>` and confirm the device receives the push and the log shows `{"sent":1,...}`. (Full app-driven E2E is deferred to P3/P6; this step is optional confirmation.)

- [ ] **Step 6: Document the live setup**

Append a short "Apple Watch push (P1)" section to `docs/superpowers/specs/2026-05-29-applewatch-push-stt-design.md` (or a new `docs/PUSH_BACKEND_SETUP.md`) listing the seven env vars and the webhook config, so P3/P6 can reproduce it. Then commit:

```bash
git add docs/
git commit -m "docs(push): record P1 backend env vars + webhook wiring

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push the branch/main**

```bash
git push origin main
```

---

## Self-Review

**1. Spec coverage (against the design doc §5.4, §5.5, §10):**
- `device_tokens` table + RLS + `ping_register_device_token`/`ping_remove_device_token` → Tasks 1–2. ✅
- Push backend = Vercel serverless + DB Webhook + APNs → Tasks 3–8. ✅
- Short-lived signed Storage URL in payload (5–10 min) → `createSignedUrl(path, 600)` in Task 7. ✅
- `mutable-content` for NSE + `PING_MESSAGE` category for reply → Task 5. ✅
- Webhook shared-secret verification → Tasks 4, 8. ✅
- `apns-collapse-id = messageId` dedup → Tasks 6–7. ✅
- 410 token pruning → Task 7. ✅
- APNs environment per token (production/sandbox) → table column (Task 2) + send host switch (Task 6) + handler pass-through (Task 7). ✅
- Secrets server-only in Vercel env → Task 8. ✅
- **Deferred (correctly out of P1):** device-token registration from the app (P3), NSE download/attach (P3), watch playback/reply (P5), session handoff (P4). Noted in header.

**2. Placeholder scan:** No "TBD"/"add error handling"/"similar to" — every code step has complete content. Angle-bracket items in Task 8 (`<receiver_uid>`, `<real_apns_hex_token>`, `<ref>`) are runtime values an operator substitutes, not unwritten code.

**3. Type consistency:** `MessageRecord` fields (`messageId`, `receiverUid`, `senderUid`, `videoId`, `roomId`, `senderNickname`) are produced by `parseMessageRecord` (Task 4) and consumed identically in `handlePush` (Task 7). `buildPingPayload` input/output (Task 5) matches its use in Task 7. `SendApnsInput`/`SendApnsResult` (Task 6) match the `send` signature in `PushDeps` and the test fakes (Task 7). RPC arg names (`token_text`, `platform_text`, `environment_text`) are internal to the migration; the app will call them by name in P3. Column names (`receiver_uid`, `sender_uid`, `video_id`, `room_id`, `sender_nickname`) match the verified `messages` schema.

---

## Execution Handoff

See the closing message for execution-mode options.
