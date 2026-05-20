-- Phase C: 30-day retention + history RPCs + hidden_for_receiver flag

alter table public.messages
    add column if not exists hidden_for_receiver boolean not null default false;

-- Update cleanup function: 24h → 30d
create or replace function public.ping_cleanup_expired_data()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    msg_record record;
begin
    -- Delete messages older than 30 days (regardless of expires_at)
    for msg_record in
        select m.id, m.video_url, m.sender_uid
        from public.messages m
        where m.created_at < now() - interval '30 days'
    loop
        delete from storage.objects
        where bucket_id = 'ping-videos'
          and name = msg_record.video_url;
        delete from public.messages where id = msg_record.id;
    end loop;

    -- Invitations / links: keep 7-day rule
    delete from public.invitations where expires_at < now();
    delete from public.invite_links where expires_at < now();
end;
$$;

-- Room messages with pagination
create or replace function public.ping_room_messages(
    room_uuid uuid,
    before_ts timestamptz default null,
    page_limit int default 50
) returns setof public.messages
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then
        raise exception 'auth required';
    end if;

    if not exists (
        select 1 from public.room_members where room_id = room_uuid and uid = me
    ) then
        raise exception 'not a member';
    end if;

    return query
    select * from public.messages
    where room_id = room_uuid
      and (receiver_uid = me or sender_uid = me)
      and (before_ts is null or created_at < before_ts)
      and (hidden_for_receiver = false or sender_uid = me)
    order by created_at desc
    limit page_limit;
end;
$$;

create or replace function public.ping_delete_message(message_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    msg record;
begin
    select sender_uid, video_url into msg from public.messages where id = message_uuid;
    if msg is null then return; end if;
    if msg.sender_uid != me then
        raise exception 'only sender can delete';
    end if;

    delete from storage.objects where bucket_id = 'ping-videos' and name = msg.video_url;
    delete from public.messages where id = message_uuid;
end;
$$;

create or replace function public.ping_hide_message_for_receiver(message_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    update public.messages
       set hidden_for_receiver = true
     where id = message_uuid
       and receiver_uid = me;
end;
$$;

grant execute on function public.ping_room_messages(uuid, timestamptz, int) to authenticated;
grant execute on function public.ping_delete_message(uuid) to authenticated;
grant execute on function public.ping_hide_message_for_receiver(uuid) to authenticated;
