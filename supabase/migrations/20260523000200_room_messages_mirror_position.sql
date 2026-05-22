-- v0.3.7: ping_room_messages가 mirror_position jsonb를 합성해 반환.
-- messages 테이블에는 mirror_position 컬럼이 없고 x_ratio/y_ratio 두 컬럼만 있음.
-- 이전 setof public.messages 반환은 VideoMessage decode에서 keyNotFound 유발.

drop function if exists public.ping_room_messages(uuid, timestamptz, int);

create or replace function public.ping_room_messages(
    room_uuid uuid,
    before_ts timestamptz default null,
    page_limit int default 50
) returns table (
    id uuid,
    room_id uuid,
    sender_uid uuid,
    receiver_uid uuid,
    sender_nickname text,
    video_id text,
    video_url text,
    duration_ms integer,
    mirror_position jsonb,
    status text,
    created_at timestamptz,
    expires_at timestamptz,
    capture_mode text,
    aspect_ratio real,
    hidden_for_receiver boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then raise exception 'auth required'; end if;
    if not exists (
        select 1 from public.room_members where room_id = room_uuid and user_id = me
    ) and not exists (
        select 1 from public.messages where room_id = room_uuid and (sender_uid = me or receiver_uid = me)
    ) and not exists (
        select 1 from public.chat_messages where room_id = room_uuid and sender_uid = me
    ) then
        raise exception 'not a member';
    end if;

    return query
    select
        m.id,
        m.room_id,
        m.sender_uid,
        m.receiver_uid,
        m.sender_nickname,
        m.video_id,
        m.video_url,
        m.duration_ms,
        jsonb_build_object('xRatio', m.x_ratio, 'yRatio', m.y_ratio) as mirror_position,
        m.status,
        m.created_at,
        m.expires_at,
        m.capture_mode,
        m.aspect_ratio,
        m.hidden_for_receiver
    from public.messages m
    where m.room_id = room_uuid
      and (m.receiver_uid = me or m.sender_uid = me)
      and (before_ts is null or m.created_at < before_ts)
      and (m.hidden_for_receiver = false or m.sender_uid = me)
    order by m.created_at desc
    limit page_limit;
end;
$$;

grant execute on function public.ping_room_messages(uuid, timestamptz, int) to authenticated;
