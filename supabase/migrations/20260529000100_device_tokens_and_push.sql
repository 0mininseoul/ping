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

-- Idempotent: safe to re-run via dashboard SQL editor or a later `supabase db push`.
drop policy if exists device_tokens_select_own on public.device_tokens;
create policy device_tokens_select_own on public.device_tokens
    for select to authenticated using (uid = auth.uid());
drop policy if exists device_tokens_insert_own on public.device_tokens;
create policy device_tokens_insert_own on public.device_tokens
    for insert to authenticated with check (uid = auth.uid());
drop policy if exists device_tokens_update_own on public.device_tokens;
create policy device_tokens_update_own on public.device_tokens
    for update to authenticated using (uid = auth.uid()) with check (uid = auth.uid());
drop policy if exists device_tokens_delete_own on public.device_tokens;
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
