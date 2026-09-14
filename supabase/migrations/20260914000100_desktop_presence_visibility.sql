-- 같은 방 멤버의 맥이 켜져 있는지 Ping에서 보여준다.
--
-- 하트비트는 이미 desktop_presence에 쌓이지만 RLS가 본인 행만 허용한다(푸시 억제용).
-- 남의 상태는 테이블을 열어주는 대신 RPC 하나로만 노출한다 — 방 멤버십을 서버에서
-- 확인해야 하고, 정책을 풀면 uid/device_id/방 이동 이력까지 통째로 새어 나간다.
--
-- 종료·로그아웃 때 행을 지우던 것을 ended_at 기록으로 바꾼다. 지우면 "마지막 접속
-- 시각"을 보여줄 근거가 사라진다. 대신 푸시 억제 쿼리는 ended_at을 함께 봐야 한다.
-- 그러지 않으면 Ping을 끈 뒤에도 마지막 하트비트가 만료될 때까지(최대 45초) 휴대폰
-- 알림이 계속 막힌다. 예전엔 행 삭제로 즉시 풀렸던 부분이다.

alter table public.desktop_presence
    add column if not exists ended_at timestamptz;

-- 살아 있는 세션만 조회하는 경로. 종료된 행은 마지막 접속 시각용으로만 남는다.
create index if not exists desktop_presence_live_idx
    on public.desktop_presence (uid, updated_at desc)
    where ended_at is null;

-- 하트비트는 종료 표식을 지운다. 앱을 다시 켜면 같은 기기 행이 되살아난다.
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

    insert into public.desktop_presence (uid, device_id, platform, active_room_id, updated_at, ended_at)
    values (me, device_value, platform_value, active_room_uuid, now(), null)
    on conflict (uid, device_id)
    do update set
        platform = excluded.platform,
        active_room_id = excluded.active_room_id,
        updated_at = excluded.updated_at,
        ended_at = null;
end;
$$;

grant execute on function public.ping_update_desktop_presence(text, text, uuid) to authenticated;

-- 종료는 삭제가 아니다. updated_at을 마지막 접속 시각으로 남기고 끝난 표식만 찍는다.
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

    update public.desktop_presence
    set ended_at = now(),
        active_room_id = null
    where uid = me
      and device_id = device_value
      and platform = platform_value
      and ended_at is null;
end;
$$;

grant execute on function public.ping_clear_desktop_presence(text, text) to authenticated;

-- 호출자가 속한 방의 멤버 상태만 돌려준다. 기기가 여러 대면 행도 여러 개라
-- 사람 단위로 합쳐서 내보낸다.
create or replace function public.ping_room_desktop_presence(room_uuids uuid[])
returns table (
    uid text,
    last_seen_at timestamptz,
    is_live boolean
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
            bool_or(dp.ended_at is null and dp.updated_at >= live_cutoff)
        from public.desktop_presence dp
        join visible_members vm on vm.user_id = dp.uid
        group by dp.uid;
end;
$$;

grant execute on function public.ping_room_desktop_presence(uuid[]) to authenticated;
