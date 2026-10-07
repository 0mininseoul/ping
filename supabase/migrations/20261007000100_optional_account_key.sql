-- Credential and throttle RPCs are exclusively for the existing Vercel broker.
create table ping_private.account_keys (
    user_id uuid primary key references public.profiles(id) on delete cascade,
    login_name text not null check (length(login_name) between 1 and 256),
    key_fingerprint text not null check (key_fingerprint ~ '^[0-9a-f]{64}$'),
    revision uuid not null default gen_random_uuid(),
    updated_at timestamptz not null default now(),
    unique (login_name, key_fingerprint)
);
create table ping_private.account_key_limits (
    scope text not null check (length(scope) between 1 and 100),
    window_start timestamptz not null,
    attempts integer not null,
    primary key (scope, window_start)
);
alter table ping_private.account_keys enable row level security;
alter table ping_private.account_key_limits enable row level security;
revoke all on ping_private.account_keys, ping_private.account_key_limits from public, anon, authenticated, service_role;

create function public.ping_account_key_limit(p_scope text, p_window integer, p_limit integer)
returns boolean language plpgsql security definer set search_path = '' as $$
declare bucket timestamptz; used integer;
begin
    if p_window not between 60 and 3600 or p_limit not between 1 and 120 then
        raise exception 'invalid limit';
    end if;
    bucket := to_timestamp(floor(extract(epoch from clock_timestamp()) / p_window) * p_window);
    delete from ping_private.account_key_limits where window_start < now() - interval '2 hours';
    insert into ping_private.account_key_limits as limits (scope, window_start, attempts)
    values (p_scope, bucket, 1)
    on conflict (scope, window_start) do update set attempts = least(limits.attempts + 1, p_limit + 1)
    returning attempts into used;
    return used <= p_limit;
end $$;

create function public.ping_account_key_status(p_uid uuid)
returns boolean language sql security definer set search_path = '' as $$
    select exists(select 1 from ping_private.account_keys where user_id = p_uid);
$$;

create function public.ping_account_key_write(p_uid uuid, p_fingerprint text)
returns void language plpgsql security definer set search_path = '' as $$
declare name text;
begin
    select searchable_nickname into name from public.profiles where id = p_uid for update;
    if name is null or length(name) = 0 then raise exception 'profile_required'; end if;
    insert into ping_private.account_keys (user_id, login_name, key_fingerprint)
    values (p_uid, name, p_fingerprint)
    on conflict (user_id) do update set login_name = excluded.login_name,
        key_fingerprint = excluded.key_fingerprint, revision = gen_random_uuid(), updated_at = now();
end $$;

create function public.ping_account_key_lookup(p_name text, p_fingerprint text)
returns jsonb language sql security definer set search_path = '' as $$
    select jsonb_build_object('uid', k.user_id, 'nickname', p.nickname, 'revision', k.revision)
    from ping_private.account_keys k join public.profiles p on p.id = k.user_id
    where k.login_name = p_name and k.key_fingerprint = p_fingerprint;
$$;

create function ping_private.sync_account_key_nickname()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    update ping_private.account_keys set login_name = new.searchable_nickname,
        revision = gen_random_uuid(), updated_at = now() where user_id = new.id;
    return new;
end $$;
create trigger sync_account_key_nickname after update of searchable_nickname on public.profiles
    for each row when (old.searchable_nickname is distinct from new.searchable_nickname)
    execute function ping_private.sync_account_key_nickname();

revoke all on function public.ping_account_key_limit(text, integer, integer) from public, anon, authenticated;
revoke all on function public.ping_account_key_status(uuid) from public, anon, authenticated;
revoke all on function public.ping_account_key_write(uuid, text) from public, anon, authenticated;
revoke all on function public.ping_account_key_lookup(text, text) from public, anon, authenticated;
revoke all on function ping_private.sync_account_key_nickname() from public, anon, authenticated;
grant execute on function public.ping_account_key_limit(text, integer, integer) to service_role;
grant execute on function public.ping_account_key_status(uuid) to service_role;
grant execute on function public.ping_account_key_write(uuid, text) to service_role;
grant execute on function public.ping_account_key_lookup(text, text) to service_role;
