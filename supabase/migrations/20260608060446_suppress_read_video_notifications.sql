-- Do not return video notifications for messages in rooms the receiver has
-- already opened. Room open writes profiles.last_read_chat_at; this RPC is the
-- polling source for desktop push notifications.

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
    read_map jsonb := '{}'::jsonb;
begin
    current_uid := ping_private.require_uid();

    select coalesce(p.last_read_chat_at, '{}'::jsonb)
    into read_map
    from public.profiles p
    where p.id = current_uid;

    if read_map is null then
        read_map := '{}'::jsonb;
    end if;

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
          and m.expires_at > now()
          and coalesce(m.hidden_for_receiver, false) = false
          and m.created_at > coalesce(
              (read_map ->> m.room_id::text)::timestamptz,
              'epoch'::timestamptz
          )
        order by m.created_at desc;
end;
$$;

grant execute on function public.ping_incoming_messages() to authenticated;
