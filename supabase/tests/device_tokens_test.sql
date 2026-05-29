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
