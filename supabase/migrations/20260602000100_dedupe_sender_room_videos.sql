-- v0.3.40: In room history, sender-created receiver rows share one storage
-- object. Show the sender one timeline entry per room/video_url while keeping
-- receiver rows intact.

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
    hidden_for_receiver boolean,
    allows_local_save boolean
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
    with ranked_messages as (
        select
            m.*,
            row_number() over (
                partition by m.room_id, m.video_url
                order by m.created_at asc, m.id asc
            ) as sender_video_rank
        from public.messages m
        where m.room_id = room_uuid
          and (m.receiver_uid = me or m.sender_uid = me)
          and (m.hidden_for_receiver = false or m.sender_uid = me)
    ),
    deduped_messages as (
        select m.*
        from ranked_messages m
        where m.sender_uid <> me or m.sender_video_rank = 1
    )
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
        m.hidden_for_receiver,
        m.allows_local_save
    from deduped_messages m
    where before_ts is null or m.created_at < before_ts
    order by m.created_at desc
    limit page_limit;
end;
$$;

grant execute on function public.ping_room_messages(uuid, timestamptz, int) to authenticated;
