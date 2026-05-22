-- v0.3.8: resolve plpgsql output-column vs SQL column ambiguity in ping_room_messages.
-- "returns table (..., room_id uuid, ...)" 의 output columns가 plpgsql scope variable이 되어
-- body 안에서 "m.room_id" 등 SQL reference와 충돌. #variable_conflict use_column로 column 우선시.

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
#variable_conflict use_column
declare
    me uuid := auth.uid();
begin
    if me is null then raise exception 'auth required'; end if;
    if not exists (
        select 1 from public.room_members rm where rm.room_id = room_uuid and rm.user_id = me
    ) and not exists (
        select 1 from public.messages mm where mm.room_id = room_uuid and (mm.sender_uid = me or mm.receiver_uid = me)
    ) and not exists (
        select 1 from public.chat_messages cm where cm.room_id = room_uuid and cm.sender_uid = me
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
