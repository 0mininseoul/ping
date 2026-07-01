-- Keep realtime chat read receipts from consuming video notification candidates.
-- Opening a room still marks both chat and video read through ping_mark_room_read;
-- a chat INSERT in an already-open room should only advance the chat read marker.

create or replace function public.ping_mark_room_chat_read(room_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := ping_private.require_uid();
    current_map jsonb;
begin
    select last_read_chat_at
    into current_map
    from public.profiles
    where id = me;

    if current_map is null then
        current_map := '{}'::jsonb;
    end if;

    update public.profiles
       set last_read_chat_at = current_map || jsonb_build_object(room_uuid::text, to_jsonb(now()))
     where id = me;
end;
$$;

grant execute on function public.ping_mark_room_chat_read(uuid) to authenticated;

create or replace function public.ping_incoming_messages()
returns table (
    id text,
    room_id text,
    sender_uid text,
    receiver_uid text,
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
declare
    current_uid uuid;
begin
    current_uid := ping_private.require_uid();

    return query
        select
            m.id::text,
            m.room_id::text,
            m.sender_uid::text,
            m.receiver_uid::text,
            m.sender_nickname,
            m.video_id,
            m.video_url,
            m.duration_ms,
            jsonb_build_object('xRatio', m.x_ratio, 'yRatio', m.y_ratio),
            m.status,
            m.created_at,
            m.expires_at,
            m.capture_mode,
            m.aspect_ratio,
            m.hidden_for_receiver,
            m.allows_local_save
        from public.messages m
        where m.receiver_uid = current_uid
          and m.status = 'uploaded'
          and m.notified_at is null
          and m.expires_at > now()
          and coalesce(m.hidden_for_receiver, false) = false
        order by m.created_at desc;
end;
$$;

grant execute on function public.ping_incoming_messages() to authenticated;
