-- Persist notification delivery separately from message read state. A local
-- UserDefaults ledger can be lost or capped; the server should still avoid
-- returning the same uploaded video as a fresh push candidate after relaunch.

alter table public.messages
    add column if not exists notified_at timestamptz;

-- Backfill existing uploaded messages so upgrading clients do not replay a
-- backlog of already surfaced or already viewed videos. They still appear in
-- room history/unread state until the room is opened or the video is played.
update public.messages
   set notified_at = coalesce(notified_at, now())
 where status = 'uploaded'
   and notified_at is null
   and expires_at > now()
   and coalesce(hidden_for_receiver, false) = false;

create or replace function public.ping_mark_message_notified(message_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
begin
    current_uid := ping_private.require_uid();

    update public.messages
       set notified_at = coalesce(notified_at, now())
     where id = message_uuid
       and receiver_uid = current_uid
       and status = 'uploaded'
       and expires_at > now()
       and coalesce(hidden_for_receiver, false) = false;
end;
$$;

grant execute on function public.ping_mark_message_notified(uuid) to authenticated;

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
          and m.notified_at is null
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
