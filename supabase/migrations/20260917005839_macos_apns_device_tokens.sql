-- Register macOS APNs tokens and retain per-device sound preferences.

alter table public.device_tokens
    drop constraint if exists device_tokens_platform_check;

alter table public.device_tokens
    add constraint device_tokens_platform_check
    check (platform in ('ios', 'watchos', 'macos'));

alter table public.device_tokens
    add column if not exists sound_preference text not null default 'default';

alter table public.device_tokens
    drop constraint if exists device_tokens_sound_preference_check;

alter table public.device_tokens
    add constraint device_tokens_sound_preference_check
    check (sound_preference in ('default', 'none'));

-- A token can survive an app reinstall or move between anonymous sessions.
-- Keep the most recently refreshed owner before enforcing global ownership.
with ranked_tokens as (
    select
        id,
        row_number() over (
            partition by platform, token
            order by updated_at desc, id desc
        ) as ownership_rank
    from public.device_tokens
)
delete from public.device_tokens as device_token
using ranked_tokens
where device_token.id = ranked_tokens.id
  and ranked_tokens.ownership_rank > 1;

alter table public.device_tokens
    drop constraint if exists device_tokens_uid_token_key;

alter table public.device_tokens
    add constraint device_tokens_platform_token_key unique (platform, token);

-- Drop the old overload so PostgREST has one unambiguous RPC signature.
drop function if exists public.ping_register_device_token(text, text, text, text);
drop function if exists public.ping_register_device_token(text, text, text);

create function public.ping_register_device_token(
    token_text text,
    platform_text text,
    environment_text text default 'production',
    sound_preference_text text default 'default'
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_uid uuid := auth.uid();
    normalized_token text := btrim(token_text);
    normalized_platform text := btrim(platform_text);
    normalized_environment text := btrim(environment_text);
    normalized_sound_preference text := btrim(sound_preference_text);
begin
    if caller_uid is null then
        raise exception 'not authenticated';
    end if;

    if token_text is null or normalized_token = '' then
        raise exception using
            errcode = '22023',
            message = 'device token must not be empty';
    end if;

    if platform_text is null or normalized_platform = '' then
        raise exception using
            errcode = '22023',
            message = 'device token platform must not be empty';
    end if;

    if environment_text is null or normalized_environment = '' then
        raise exception using
            errcode = '22023',
            message = 'device token environment must not be empty';
    end if;

    if sound_preference_text is null or normalized_sound_preference = '' then
        raise exception using
            errcode = '22023',
            message = 'device token sound preference must not be empty';
    end if;

    if normalized_platform not in ('ios', 'watchos', 'macos') then
        raise exception using
            errcode = '22023',
            message = format('unsupported device token platform: %s', normalized_platform);
    end if;

    if normalized_environment not in ('production', 'sandbox') then
        raise exception using
            errcode = '22023',
            message = format('unsupported device token environment: %s', normalized_environment);
    end if;

    if normalized_sound_preference not in ('default', 'none') then
        raise exception using
            errcode = '22023',
            message = format('unsupported sound preference: %s', normalized_sound_preference);
    end if;

    insert into public.device_tokens (
        uid,
        token,
        platform,
        environment,
        sound_preference,
        updated_at
    ) values (
        caller_uid,
        normalized_token,
        normalized_platform,
        normalized_environment,
        normalized_sound_preference,
        now()
    )
    on conflict (platform, token)
    do update set
        uid = excluded.uid,
        environment = excluded.environment,
        sound_preference = excluded.sound_preference,
        updated_at = excluded.updated_at;
end;
$$;

revoke all privileges
    on function public.ping_register_device_token(text, text, text, text)
    from public, anon;
grant execute
    on function public.ping_register_device_token(text, text, text, text)
    to authenticated;

-- The existing removal RPC is also SECURITY DEFINER, so harden its lookup path
-- and remove the implicit PUBLIC execution grant while this API is being revised.
alter function public.ping_remove_device_token(text) set search_path = '';
revoke all privileges
    on function public.ping_remove_device_token(text)
    from public, anon;
grant execute
    on function public.ping_remove_device_token(text)
    to authenticated;
