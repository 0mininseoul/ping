-- Mac이 잠들면 "접속 중"이 아니라 "잠자기 중"으로 구분해서 보여준다.
--
-- 지금까지는 updated_at이 45초 안에만 갱신되면 무조건 is_live였다. 그런데
-- DarkWake(Power Nap) 때문에 화면이 꺼지고 잠들어 있어도 macOS가 앱을 잠깐씩
-- 깨워 네트워크를 허용하는 순간이 있어서, 그 타이밍에 하트비트가 새어나가
-- updated_at이 계속 갱신되고 "접속 중"이 안 꺼지는 문제가 있었다. 클라이언트가
-- 매 하트비트마다 "지금 시스템이 잠들어 있는가"를 함께 실어 보내게 하고,
-- is_live는 잠자기 중이 아닐 때만 true가 되도록 서버에서 강제한다.

alter table public.desktop_presence
    add column if not exists is_sleeping boolean not null default false;

-- 시그니처(인자 개수)가 바뀌므로 create or replace로는 안 되고 기존 함수를
-- 명시적으로 지워야 한다. 안 그러면 오버로드가 두 개 남아 PostgREST가
-- named-arg 호출에서 "어느 쪽인지 모르겠다"고 죽는다.
drop function if exists public.ping_update_desktop_presence(text, text, uuid);

create or replace function public.ping_update_desktop_presence(
    device_id_text text,
    platform_text text default 'macos',
    active_room_uuid uuid default null,
    sleeping_bool boolean default false
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

    insert into public.desktop_presence (uid, device_id, platform, active_room_id, updated_at, ended_at, is_sleeping)
    values (me, device_value, platform_value, active_room_uuid, now(), null, coalesce(sleeping_bool, false))
    on conflict (uid, device_id)
    do update set
        platform = excluded.platform,
        active_room_id = excluded.active_room_id,
        updated_at = excluded.updated_at,
        ended_at = null,
        is_sleeping = excluded.is_sleeping;
end;
$$;

grant execute on function public.ping_update_desktop_presence(text, text, uuid, boolean) to authenticated;

-- 리턴 컬럼이 늘어나므로 이것도 drop 후 재생성해야 한다.
drop function if exists public.ping_room_desktop_presence(uuid[]);

create or replace function public.ping_room_desktop_presence(room_uuids uuid[])
returns table (
    uid text,
    last_seen_at timestamptz,
    is_live boolean,
    is_sleeping boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    me uuid := ping_private.require_uid();
    -- api/push.ts의 PUSH_DESKTOP_PRESENCE_TTL_SECONDS 기본값과 같다. 하트비트는 15초 주기.
    live_cutoff timestamptz := now() - interval '45 seconds';
    -- wake 신호를 영영 못 받는 극단적 상황(배터리 방전 등)에 "잠자기 중" 배지가
    -- 무기한 고정되지 않도록 하는 안전장치. 보통은 didWake에서 즉시 갱신된다.
    sleep_cutoff timestamptz := now() - interval '24 hours';
begin
    if room_uuids is null or array_length(room_uuids, 1) is null then
        return;
    end if;

    return query
        with my_rooms as (
            select rm.room_id
            from public.room_members rm
            where rm.user_id = me
              and rm.room_id = any(room_uuids)
        ),
        visible_members as (
            select distinct rm.user_id
            from public.room_members rm
            join my_rooms mr on mr.room_id = rm.room_id
        )
        select
            dp.uid::text,
            max(dp.updated_at),
            bool_or(dp.ended_at is null and dp.updated_at >= live_cutoff and not dp.is_sleeping),
            bool_or(dp.ended_at is null and dp.is_sleeping and dp.updated_at >= sleep_cutoff)
        from public.desktop_presence dp
        join visible_members vm on vm.user_id = dp.uid
        group by dp.uid;
end;
$$;

grant execute on function public.ping_room_desktop_presence(uuid[]) to authenticated;
