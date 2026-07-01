-- Desktop availability heartbeat used by the mobile push backend.
-- If a desktop client stops, sleeps, or loses network, updated_at naturally goes
-- stale and iOS/watch push resumes without a server-side scheduler.

create table if not exists public.desktop_presence (
    uid uuid not null references auth.users(id) on delete cascade,
    device_id text not null,
    platform text not null default 'macos',
    active_room_id uuid references public.rooms(id) on delete set null,
    updated_at timestamptz not null default now(),
    primary key (uid, device_id),
    constraint desktop_presence_device_id_check
        check (char_length(device_id) between 8 and 128),
    constraint desktop_presence_platform_check
        check (platform in ('macos', 'windows'))
);

create index if not exists desktop_presence_uid_updated_at_idx
    on public.desktop_presence (uid, updated_at desc);

alter table public.desktop_presence enable row level security;

drop policy if exists desktop_presence_select_own on public.desktop_presence;
create policy desktop_presence_select_own
    on public.desktop_presence for select to authenticated
    using (uid = auth.uid());

drop policy if exists desktop_presence_insert_own on public.desktop_presence;
create policy desktop_presence_insert_own
    on public.desktop_presence for insert to authenticated
    with check (uid = auth.uid());

drop policy if exists desktop_presence_update_own on public.desktop_presence;
create policy desktop_presence_update_own
    on public.desktop_presence for update to authenticated
    using (uid = auth.uid())
    with check (uid = auth.uid());

drop policy if exists desktop_presence_delete_own on public.desktop_presence;
create policy desktop_presence_delete_own
    on public.desktop_presence for delete to authenticated
    using (uid = auth.uid());

grant select, insert, update, delete on public.desktop_presence to authenticated;
grant select, delete on public.desktop_presence to service_role;

create or replace function public.ping_update_desktop_presence(
    device_id_text text,
    platform_text text default 'macos',
    active_room_uuid uuid default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := ping_private.require_uid();
    device_value text := nullif(trim(device_id_text), '');
    platform_value text := coalesce(nullif(trim(platform_text), ''), 'macos');
begin
    if device_value is null or char_length(device_value) < 8 or char_length(device_value) > 128 then
        raise exception 'invalid device id';
    end if;

    if platform_value not in ('macos', 'windows') then
        raise exception 'invalid desktop platform';
    end if;

    if active_room_uuid is not null and not exists (
        select 1
        from public.room_members
        where room_id = active_room_uuid
          and user_id = me
    ) then
        raise exception 'active room is not a membership';
    end if;

    insert into public.desktop_presence (uid, device_id, platform, active_room_id, updated_at)
    values (me, device_value, platform_value, active_room_uuid, now())
    on conflict (uid, device_id)
    do update set
        platform = excluded.platform,
        active_room_id = excluded.active_room_id,
        updated_at = excluded.updated_at;
end;
$$;

grant execute on function public.ping_update_desktop_presence(text, text, uuid) to authenticated;

create or replace function public.ping_clear_desktop_presence(
    device_id_text text,
    platform_text text default 'macos'
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := ping_private.require_uid();
    device_value text := nullif(trim(device_id_text), '');
    platform_value text := coalesce(nullif(trim(platform_text), ''), 'macos');
begin
    if device_value is null then
        return;
    end if;

    delete from public.desktop_presence
    where uid = me
      and device_id = device_value
      and platform = platform_value;
end;
$$;

grant execute on function public.ping_clear_desktop_presence(text, text) to authenticated;
