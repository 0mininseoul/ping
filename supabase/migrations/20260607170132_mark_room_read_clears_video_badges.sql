-- Treat opening a room as reading both text chat and received video pings.
-- `ping_my_rooms()` sums chat unread rows with uploaded receiver video rows, so
-- the room-level read RPC must clear both sources or badges remain stuck.

create or replace function public.ping_mark_room_read(room_uuid uuid)
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

    update public.messages
       set status = 'seen'
     where room_id = room_uuid
       and receiver_uid = me
       and status = 'uploaded'
       and expires_at > now()
       and coalesce(hidden_for_receiver, false) = false;
end;
$$;

grant execute on function public.ping_mark_room_read(uuid) to authenticated;
