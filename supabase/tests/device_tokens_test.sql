begin;
select plan(24);

-- Structure
select has_table('public', 'device_tokens', 'device_tokens table exists');
select has_column('public', 'device_tokens', 'uid', 'has uid column');
select has_column('public', 'device_tokens', 'token', 'has token column');
select has_column('public', 'device_tokens', 'platform', 'has platform column');
select has_column('public', 'device_tokens', 'sound_preference', 'has sound preference column');
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
  'three-argument iOS clients can still register a token'
);
select is(
  (select count(*)::int from public.device_tokens where token = 'tok-alice'),
  1,
  'exactly one row after register'
);
select is(
  (select sound_preference from public.device_tokens where token = 'tok-alice'),
  'default',
  'three-argument registration defaults to the normal APNs sound'
);

select lives_ok(
  $$ select public.ping_register_device_token('  tok-macos  ', '  macos  ', '  production  ', '  none  ') $$,
  'macOS clients can register a token with no notification sound'
);
select results_eq(
  $$
    select token, platform, environment, sound_preference
    from public.device_tokens
    where token = 'tok-macos'
  $$,
  $$ values ('tok-macos'::text, 'macos'::text, 'production'::text, 'none'::text) $$,
  'registration trims and stores the macOS token preferences'
);

select throws_ok(
  $$ select public.ping_register_device_token('tok-invalid-platform', 'tvos', 'production', 'default') $$,
  '22023',
  'unsupported device token platform: tvos',
  'unsupported platforms are rejected'
);
select throws_ok(
  $$ select public.ping_register_device_token('tok-invalid-sound', 'macos', 'production', 'critical') $$,
  '22023',
  'unsupported sound preference: critical',
  'unsupported sound preferences are rejected'
);
select throws_ok(
  $$ select public.ping_register_device_token('   ', 'macos', 'production', 'default') $$,
  '22023',
  'device token must not be empty',
  'blank tokens are rejected'
);
select throws_ok(
  $$ select public.ping_register_device_token('tok-blank-platform', '   ', 'production', 'default') $$,
  '22023',
  'device token platform must not be empty',
  'blank platforms are rejected'
);
select throws_ok(
  $$ select public.ping_register_device_token('tok-blank-environment', 'macos', '   ', 'default') $$,
  '22023',
  'device token environment must not be empty',
  'blank environments are rejected'
);
select throws_ok(
  $$ select public.ping_register_device_token('tok-blank-sound', 'macos', 'production', '   ') $$,
  '22023',
  'device token sound preference must not be empty',
  'blank sound preferences are rejected'
);

select lives_ok(
  $$ select public.ping_register_device_token('tok-transfer', 'macos', 'production', 'default') $$,
  'alice can register the token that will be transferred'
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

select lives_ok(
  $$ select public.ping_register_device_token('tok-transfer', 'macos', 'sandbox', 'none') $$,
  'bob can register a stale token previously owned by alice'
);
select is(
  (
    select count(*)::int
    from public.device_tokens
    where platform = 'macos' and token = 'tok-transfer'
  ),
  1,
  'ownership transfer leaves exactly one platform and token row'
);
select results_eq(
  $$
    select uid, environment, sound_preference
    from public.device_tokens
    where platform = 'macos' and token = 'tok-transfer'
  $$,
  $$
    values (
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid,
      'sandbox'::text,
      'none'::text
    )
  $$,
  'ownership and preferences move to the second authenticated user'
);

select set_config('request.jwt.claims', '{}', true);
select throws_ok(
  $$ select public.ping_register_device_token('tok-unauthenticated', 'macos', 'production', 'default') $$,
  'P0001',
  'not authenticated',
  'registration requires an authenticated user'
);

select * from finish();
rollback;
